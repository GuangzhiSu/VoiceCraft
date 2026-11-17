import AVFoundation

/// All file, converter and pending-audio mutations run on queue, never on the UI thread.
/// Speech request hand-off is synchronized by this same queue.
final class AudioCapture {
    private let engine = AVAudioEngine()
    private let queue = DispatchQueue(label: "voicecraft.capture", qos: .userInitiated)
    private var file: AVAudioFile?
    private var converter: AVAudioConverter?
    private var pending: [Float] = []
    private var overlap: [Float] = []
    private var recent: [AVAudioPCMBuffer] = []
    private var sink: ((AVAudioPCMBuffer) -> Void)?
    private var failure: ((Error) -> Void)?
    private var failed = false
    private var collecting = false
    private var tapInstalled = false
    var level: ((Float) -> Void)?

    func setSpeechSink(_ sink: ((AVAudioPCMBuffer) -> Void)?, replayRecent: Bool = false) {
        queue.sync {
            self.sink = sink
            if replayRecent { recent.forEach { sink?($0) } }
        }
    }

    func start(url: URL, collectPCM: Bool, onError: @escaping (Error) -> Void) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.allowBluetooth])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0,
              let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: format, to: target) else {
            throw VoiceCraftError.message("No microphone is available. Connect a microphone and try again.")
        }
        let outputFile = try AVAudioFile(forWriting: url, settings: format.settings)
        queue.sync {
            file = outputFile; self.converter = converter; pending = []; overlap = []
            recent = []; collecting = collectPCM; failure = onError; failed = false
        }
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            guard let self,
                  let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else { return }
            copy.frameLength = buffer.frameLength
            let source = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
            let destination = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
            for index in 0..<source.count {
                if let src = source[index].mData, let dst = destination[index].mData {
                    memcpy(dst, src, Int(source[index].mDataByteSize))
                }
            }
            self.queue.async { self.process(copy) }
        }
        tapInstalled = true
        engine.prepare()
        do { try engine.start() } catch { stop(); throw error }
    }

    private func process(_ buffer: AVAudioPCMBuffer) {
        guard !failed else { return }
        do {
            try file?.write(from: buffer)
            sink?(buffer)
            if !collecting {
                recent.append(buffer)
                while recent.count > 1 && recent.reduce(0, { $0 + Int($1.frameLength) }) > Int(buffer.format.sampleRate) {
                    recent.removeFirst()
                }
            }
            if let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 {
                var power: Float = 0
                for i in 0..<Int(buffer.frameLength) { power += samples[i] * samples[i] }
                level?(min(1, sqrt(power / Float(buffer.frameLength)) * 8))
            }
            guard collecting, let converter else { return }
            let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * 16000 / buffer.format.sampleRate) + 32)
            guard let converted = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: capacity) else { return }
            var supplied = false
            var error: NSError?
            let status = converter.convert(to: converted, error: &error) { _, state in
                if supplied { state.pointee = .noDataNow; return nil }
                supplied = true; state.pointee = .haveData; return buffer
            }
            if let error { throw error }
            guard status != .error, let floats = converted.floatChannelData?[0] else { return }
            pending.append(contentsOf: UnsafeBufferPointer(start: floats, count: Int(converted.frameLength)))
            if pending.count > 16000 * 120 {
                throw VoiceCraftError.message("Transcription cannot keep up with this device. Audio was saved. Try the Whisper server or Apple Speech.")
            }
        } catch {
            failed = true
            failure?(error)
        }
    }

    /// Take four seconds of new audio plus half a second of preceding context.
    func takeWindow(final: Bool = false) -> [Float]? {
        queue.sync {
            let count = min(pending.count, 64000)
            guard count > 0, final || count == 64000 else { return nil }
            let fresh = Array(pending.prefix(count))
            pending.removeFirst(count)
            let result = overlap + fresh
            overlap = Array(fresh.suffix(8000))
            return result
        }
    }

    func stop() {
        engine.stop()
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        queue.sync { file = nil; sink = nil }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
