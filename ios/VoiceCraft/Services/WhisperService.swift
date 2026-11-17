import Foundation
import WhisperKit

actor WhisperService {
    private var pipe: WhisperKit?
    func prepare(progress: @escaping @Sendable (Double) -> Void) async throws {
        if pipe != nil { return }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WhisperModels", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        var excluded = base
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try excluded.setResourceValues(values)
        let folder = try await WhisperKit.download(variant: "openai_whisper-tiny.en", downloadBase: base) { p in
            progress(p.fractionCompleted)
        }
        pipe = try await WhisperKit(WhisperKitConfig(modelFolder: folder.path, verbose: false, prewarm: true, load: true, download: false))
    }
    func transcribe(_ samples: [Float]) async throws -> String {
        guard let pipe else { throw VoiceCraftError.message("Download the Whisper model first.") }
        let options = DecodingOptions(language: "en", temperatureFallbackCount: 2,
                                      detectLanguage: false, skipSpecialTokens: true, withoutTimestamps: true)
        let results: [TranscriptionResult] = try await pipe.transcribe(audioArray: samples, decodeOptions: options)
        return results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum WAVEncoder {
    static func encode(_ samples: [Float]) -> Data {
        var data = Data()
        func string(_ s: String) { data.append(contentsOf: s.utf8) }
        func u16(_ v: UInt16) { var v = v.littleEndian; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }
        func u32(_ v: UInt32) { var v = v.littleEndian; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }
        string("RIFF"); u32(UInt32(36 + samples.count * 2)); string("WAVEfmt "); u32(16)
        u16(1); u16(1); u32(16000); u32(32000); u16(2); u16(16)
        string("data"); u32(UInt32(samples.count * 2))
        for sample in samples {
            let clamped = max(-1, min(1, sample.isFinite ? sample : 0))
            u16(UInt16(bitPattern: Int16(clamped * 32767)))
        }
        return data
    }
}

struct RemoteWhisperService {
    static func validate(_ address: String) throws -> URL {
        guard let url = URL(string: address), let host = url.host,
              url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil,
              url.scheme == "https" || (url.scheme == "http" && (host == "localhost" || host.hasSuffix(".local"))) else {
            throw VoiceCraftError.message("Use an HTTPS server URL, or http://your-mac.local:8000 for local development.")
        }
        return url
    }
    static func transcribe(_ samples: [Float], address: String, token: String) async throws -> String {
        let base = try validate(address)
        guard !token.isEmpty else { throw VoiceCraftError.message("Enter your server access token in Settings.") }
        var request = URLRequest(url: base.appendingPathComponent("v1/transcribe"))
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = WAVEncoder.encode(samples)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw VoiceCraftError.message("Whisper server returned HTTP \(status). Check its address, access token and logs.")
        }
        struct Response: Decodable { var text: String }
        return try JSONDecoder().decode(Response.self, from: data).text
    }
}
