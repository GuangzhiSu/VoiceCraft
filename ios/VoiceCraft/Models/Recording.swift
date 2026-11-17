import Foundation

enum SpeechEngine: String, Codable, CaseIterable, Identifiable {
    case apple = "Apple Speech"
    case whisper = "Whisper"
    var id: String { rawValue }
}

struct Recording: Codable, Identifiable {
    var id: UUID
    var date: Date
    var duration: TimeInterval
    var engine: SpeechEngine
    var transcript: String
    var audioFilename: String
    var incomplete: Bool
    var title: String {
        let words = transcript.split(separator: " ").prefix(7).joined(separator: " ")
        return words.isEmpty ? "Untitled recording" : words
    }
}

enum VoiceCraftError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        if case .message(let message) = self { return message }
        return nil
    }
}

/// Windows overlap in time; remove only an exact, punctuation-insensitive word overlap.
/// This is a lightweight heuristic, not word-timestamp alignment.
enum TranscriptMerger {
    static func merge(_ existing: String, _ incoming: String) -> String {
        let a = existing.split(whereSeparator: \.isWhitespace).map(String.init)
        let b = incoming.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !a.isEmpty else { return b.joined(separator: " ") }
        guard !b.isEmpty else { return existing }
        func normalized(_ word: String) -> String {
            word.lowercased().trimmingCharacters(in: .punctuationCharacters)
        }
        var overlap = 0
        for count in stride(from: min(18, a.count, b.count), through: 1, by: -1) {
            if a.suffix(count).map(normalized) == b.prefix(count).map(normalized) {
                overlap = count
                break
            }
        }
        return (a + b.dropFirst(overlap)).joined(separator: " ")
    }
}
