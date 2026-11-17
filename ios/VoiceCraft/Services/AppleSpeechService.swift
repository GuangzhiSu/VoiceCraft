import Speech

@MainActor
final class AppleSpeechService {
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var generation = UUID()
    private var committed = ""
    private var partial = ""
    var onText: ((String) -> Void)?
    var onError: ((Error) -> Void)?
    private(set) var isOnDevice = false

    static func authorize() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
    }

    func start(capture: AudioCapture, reset: Bool = true) throws {
        guard let recognizer, recognizer.isAvailable else {
            throw VoiceCraftError.message("Apple Speech is unavailable. Check your network or select Whisper.")
        }
        // Rotate well before Apple's per-request duration limit. Audio capture stays running.
        if reset { committed = ""; partial = "" }
        else {
            committed = TranscriptMerger.merge(committed, partial)
            partial = ""
        }
        generation = UUID()
        task?.cancel()
        let id = generation
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.addsPunctuation = true
        isOnDevice = recognizer.supportsOnDeviceRecognition
        request.requiresOnDeviceRecognition = isOnDevice
        self.request = request
        capture.setSpeechSink({ buffer in request.append(buffer) }, replayRecent: !reset)
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self, self.generation == id else { return }
                if let result {
                    self.partial = result.bestTranscription.formattedString
                    self.onText?(TranscriptMerger.merge(self.committed, self.partial))
                    // Natural utterance completion also needs a fresh request.
                    if result.isFinal { self.onFinal?() }
                } else if let error { self.onError?(error) }
            }
        }
    }
    var onFinal: (() -> Void)?
    func endAudio() { request?.endAudio() }
    func cancel() {
        generation = UUID(); task?.cancel(); task = nil; request = nil
    }
}
