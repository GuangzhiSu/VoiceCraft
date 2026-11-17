import XCTest
@testable import VoiceCraft

final class VoiceCraftTests: XCTestCase {
    func testOverlappingChunkMerge() {
        XCTAssertEqual(TranscriptMerger.merge("We are testing the microphone.", "the microphone works well."), "We are testing the microphone. works well.")
        XCTAssertEqual(TranscriptMerger.merge("", " Hello world "), "Hello world")
        XCTAssertEqual(TranscriptMerger.merge("One thought.", "Another thought."), "One thought. Another thought.")
        XCTAssertEqual(TranscriptMerger.merge("Hello", ""), "Hello")
    }
    func testWAVHeaderAndClipping() {
        let data = WAVEncoder.encode([0, 1, -1, 5, .nan])
        XCTAssertEqual(data.count, 54)
        XCTAssertEqual(String(data: data.prefix(4), encoding: .utf8), "RIFF")
        XCTAssertEqual(Array(data[24..<28]), [128, 62, 0, 0]) // 16000 Hz
        XCTAssertEqual(Array(data[44..<50]), [0, 0, 255, 127, 1, 128])
    }
    func testRemoteURLPolicy() throws {
        _ = try RemoteWhisperService.validate("https://speech.example.com")
        _ = try RemoteWhisperService.validate("http://my-mac.local:8000")
        XCTAssertThrowsError(try RemoteWhisperService.validate("http://public.example.com"))
        XCTAssertThrowsError(try RemoteWhisperService.validate("https://user:password@example.com"))
        XCTAssertThrowsError(try RemoteWhisperService.validate("https://example.com?token=secret"))
    }
    func testRecordingPersistenceAndCorruptIndex() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RecordingStore(directory: directory)
        XCTAssertTrue(try store.load().isEmpty)
        let recording = Recording(id: UUID(), date: Date(), duration: 5, engine: .whisper,
                                  transcript: "Hello", audioFilename: "hello.caf", incomplete: false)
        try store.save([recording])
        XCTAssertEqual(try store.load().first?.id, recording.id)
        try Data("corrupt".utf8).write(to: store.indexURL)
        XCTAssertThrowsError(try store.load())
    }
}
