import Foundation

struct RecordingStore {
    let directory: URL
    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Recordings", isDirectory: true)
    }
    var indexURL: URL { directory.appendingPathComponent("recordings.json") }
    func prepare() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                                             ofItemAtPath: directory.path)
    }
    func audioURL(_ filename: String) -> URL { directory.appendingPathComponent(filename) }
    func load() throws -> [Recording] {
        try prepare()
        guard FileManager.default.fileExists(atPath: indexURL.path) else { return [] }
        return try JSONDecoder().decode([Recording].self, from: Data(contentsOf: indexURL))
    }
    func save(_ recordings: [Recording]) throws {
        try prepare()
        try JSONEncoder().encode(recordings).write(to: indexURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
