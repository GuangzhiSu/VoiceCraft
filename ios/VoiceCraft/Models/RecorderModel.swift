import AVFoundation
import Combine
import SwiftUI
import UIKit

@MainActor
final class RecorderModel: ObservableObject {
    enum State: Equatable { case idle, preparing, recording, finishing }
    @Published var state: State = .idle
    @Published var engine: SpeechEngine = .apple
    @Published var transcript = ""
    @Published var elapsed: TimeInterval = 0
    @Published var level: Float = 0
    @Published var recordings: [Recording] = []
    @Published var errorMessage: String?
    @Published var progress: Double = 0
    @Published var status = "Ready when you are"
    @Published var pendingSave = false
    @AppStorage("useRemoteWhisper") var useRemoteWhisper = false
    @AppStorage("serverURL") var serverURL = ""
    let store = RecordingStore()
    private let capture = AudioCapture()
    private let apple = AppleSpeechService()
    private let whisper = WhisperService()
    private var worker: Task<Void, Never>?
    private var clock: Task<Void, Never>?
    private var active: Recording?
    private var startedAt = Date()
    private var lastRotation = Date()
    private var remoteAddress = ""
    private var remoteToken = ""
    private var remote = false
    private var transcriptionFailed = false
    private var storageLoadFailed = false
    private var observers: [NSObjectProtocol] = []
    var busy: Bool { state != .idle }
    var formattedTime: String { String(format: "%02d:%02d", Int(elapsed) / 60, Int(elapsed) % 60) }

    init() {
        do { recordings = try store.load() } catch { storageLoadFailed = true; errorMessage = "Could not read saved recordings: \(error.localizedDescription)" }
        capture.level = { [weak self] value in Task { @MainActor in self?.level = value } }
        apple.onText = { [weak self] in self?.transcript = $0 }
        apple.onError = { [weak self] error in
            guard let self, self.state == .recording else { return }
            self.transcriptionFailed = true
            self.errorMessage = "Apple Speech stopped: \(error.localizedDescription). The audio will be saved."
            Task { await self.stop() }
        }
        apple.onFinal = { [weak self] in
            guard let self, self.state == .recording else { return }
            self.rotateApple()
        }
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
            let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            guard type == AVAudioSession.InterruptionType.began.rawValue else { return }
            Task { @MainActor in
                guard let self, self.state == .recording else { return }
                self.status = "Interrupted — saving recording"
                await self.stop()
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] notification in
            let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            guard reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue || reason == AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue else { return }
            Task { @MainActor in
                guard let self, self.state == .recording else { return }
                self.errorMessage = "Microphone changed. This recording was stopped and saved; start a new recording to use the new microphone."
                await self.stop()
            }
        })
    }

    func start() async {
        guard state == .idle, !pendingSave else { return }
        guard !storageLoadFailed else {
            errorMessage = "The recordings index could not be read. Export or repair recordings.json using Finder File Sharing before making a new recording; existing audio has been preserved."
            return
        }
        state = .preparing; status = "Checking microphone…"; progress = 0
        transcriptionFailed = false
        do {
            let allowed = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
            }
            guard allowed else { throw VoiceCraftError.message("Enable Microphone in iOS Settings → VoiceCraft to record.") }
            if engine == .apple {
                guard await AppleSpeechService.authorize() else {
                    throw VoiceCraftError.message("Enable Speech Recognition in iOS Settings → Privacy & Security, or select Whisper.")
                }
            }
            remote = useRemoteWhisper
            remoteAddress = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
            remoteToken = KeychainStore.read()
            if engine == .whisper {
                if remote {
                    _ = try RemoteWhisperService.validate(remoteAddress)
                    guard !remoteToken.isEmpty else { throw VoiceCraftError.message("Set the Whisper server token in Settings first.") }
                } else {
                    status = "Downloading / loading Whisper tiny.en…"
                    try await whisper.prepare { [weak self] value in Task { @MainActor in self?.progress = value } }
                }
            }
            // If the app left the foreground while permissions/model loading were in progress,
            // don't unexpectedly begin microphone capture in the background.
            guard UIApplication.shared.applicationState == .active else {
                throw VoiceCraftError.message("Return to VoiceCraft and tap Record to begin.")
            }
            try store.prepare()
            let id = UUID()
            let recording = Recording(id: id, date: Date(), duration: 0, engine: engine,
                                      transcript: "", audioFilename: "\(id.uuidString).caf", incomplete: false)
            active = recording
            transcript = ""; elapsed = 0
            if engine == .apple { try apple.start(capture: capture) }
            try capture.start(url: store.audioURL(recording.audioFilename), collectPCM: engine == .whisper) { [weak self] error in
                Task { @MainActor in
                    guard let self, self.state == .recording else { return }
                    self.transcriptionFailed = true; self.errorMessage = error.localizedDescription
                    await self.stop()
                }
            }
            startedAt = Date(); lastRotation = Date()
            state = .recording
            status = engine == .apple ? (apple.isOnDevice ? "Apple Speech · on device" : "Apple Speech · online") : (remote ? "Whisper · your server" : "Whisper tiny.en · on device")
            clock = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(200))
                    guard let self, self.state == .recording, !Task.isCancelled else { return }
                    self.elapsed = Date().timeIntervalSince(self.startedAt)
                    if self.engine == .apple, Date().timeIntervalSince(self.lastRotation) > 45 { self.rotateApple() }
                }
            }
            if engine == .whisper {
                worker = Task { [weak self] in
                    guard let self else { return }
                    while self.state == .recording {
                        if let samples = self.capture.takeWindow() {
                            do { try await self.decode(samples) }
                            catch {
                                self.transcriptionFailed = true
                                self.errorMessage = "Transcription stopped: \(error.localizedDescription). Your audio is preserved."
                                // Avoid awaiting stop here: stop awaits this worker.
                                Task { await self.stop() }
                                return
                            }
                        } else { try? await Task.sleep(for: .milliseconds(150)) }
                    }
                }
            }
        } catch {
            capture.stop(); apple.cancel()
            // Remove only the empty/failed-start audio file, never an existing recording.
            if let active { try? FileManager.default.removeItem(at: store.audioURL(active.audioFilename)) }
            active = nil; state = .idle; status = "Ready when you are"; errorMessage = error.localizedDescription
        }
    }

    private func rotateApple() {
        guard state == .recording else { return }
        do { try apple.start(capture: capture, reset: false); lastRotation = Date() }
        catch {
            transcriptionFailed = true; errorMessage = error.localizedDescription
            Task { await self.stop() }
        }
    }
    private func decode(_ samples: [Float]) async throws {
        guard samples.count > 400 else { return }
        let rms = sqrt(samples.reduce(Float(0)) { $0 + $1 * $1 } / Float(samples.count))
        guard rms > 0.0001 else { return }
        let text: String
        if remote { text = try await RemoteWhisperService.transcribe(samples, address: remoteAddress, token: remoteToken) }
        else { text = try await whisper.transcribe(samples) }
        transcript = TranscriptMerger.merge(transcript, text)
    }

    func stop() async {
        guard state == .recording else { return }
        state = .finishing; clock?.cancel(); clock = nil
        elapsed = Date().timeIntervalSince(startedAt)
        status = "Finishing transcript…"
        capture.stop() // drains audio queue and closes the audio file before saving
        // Persist a recoverable snapshot before any network/model await. If iOS suspends
        // or terminates us while finishing, the recording is already in the library.
        if var checkpoint = active {
            checkpoint.duration = elapsed; checkpoint.transcript = transcript; checkpoint.incomplete = true
            let updated = [checkpoint] + recordings.filter { $0.id != checkpoint.id }
            do { try store.save(updated); recordings = updated }
            catch { errorMessage = "Could not checkpoint recording: \(error.localizedDescription)" }
        }
        var backgroundTask: UIBackgroundTaskIdentifier = .invalid
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Finish recording") {
            Task { @MainActor in
                if backgroundTask != .invalid {
                    UIApplication.shared.endBackgroundTask(backgroundTask)
                    backgroundTask = .invalid
                }
            }
        }
        defer {
            if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask) }
        }
        if engine == .apple {
            apple.endAudio()
            // Allow final punctuation/results, bounded so saving never hangs on a recognizer.
            try? await Task.sleep(for: .seconds(1.5))
            apple.cancel()
        } else {
            await worker?.value; worker = nil
            if !transcriptionFailed {
                do {
                    while let samples = capture.takeWindow(final: true) { try await decode(samples) }
                } catch { transcriptionFailed = true; errorMessage = "Final transcription failed: \(error.localizedDescription). Audio is saved." }
            }
        }
        if var active {
            active.duration = elapsed; active.transcript = transcript; active.incomplete = transcriptionFailed
            self.active = active; pendingSave = true
            retrySave()
        }
        level = 0; state = .idle
        if !pendingSave { status = "Saved to your recordings" }
    }

    func retrySave() {
        guard pendingSave, let active else { return }
        do {
            let updated = [active] + recordings.filter { $0.id != active.id }
            try store.save(updated); recordings = updated; pendingSave = false; self.active = nil
            status = "Saved to your recordings"
        } catch { errorMessage = "Could not save the recording index: \(error.localizedDescription). Tap Retry Save before recording again." }
    }
    func delete(_ recording: Recording) {
        do {
            let updated = recordings.filter { $0.id != recording.id }
            try store.save(updated); recordings = updated
            try FileManager.default.removeItem(at: store.audioURL(recording.audioFilename))
        } catch { errorMessage = "Could not delete recording: \(error.localizedDescription)" }
    }
}
