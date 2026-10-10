import Foundation
import Observation

/// The user's own TTML files, kept per Spotify track (Spicy Lyrics' "Local DB",
/// `utils/Lyrics/manager`). Saved lyrics win over every online source for their track.
@MainActor
@Observable
final class LocalLyricsStore {
    struct Entry: Codable, Identifiable, Hashable {
        var trackID: String
        var title: String
        var artist: String
        var savedAt: Date

        var id: String { trackID }
    }

    static let sourceName = "Local TTML"

    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let indexURL: URL
    private(set) var entries: [Entry] = []

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("local-ttml", isDirectory: true)
        indexURL = directory.appendingPathComponent("index.json")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: indexURL),
           let decoded = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = decoded
        }
    }

    func contains(_ trackID: String) -> Bool {
        entries.contains { $0.trackID == trackID }
    }

    /// The saved lyrics for a track, parsed; nil when there are none (or the file broke).
    func document(for trackID: String) -> LyricsDocument? {
        guard contains(trackID),
              let text = try? String(contentsOf: file(trackID), encoding: .utf8)
        else { return nil }
        return try? TTMLParser.parse(text, sourceName: Self.sourceName)
    }

    /// Validates and saves a TTML for a track, replacing any earlier one.
    @discardableResult
    func save(_ ttml: String, for track: TrackInfo) throws -> LyricsDocument {
        let document = try TTMLParser.parse(ttml, sourceName: Self.sourceName)
        try ttml.write(to: file(track.id), atomically: true, encoding: .utf8)
        entries.removeAll { $0.trackID == track.id }
        entries.insert(Entry(trackID: track.id, title: track.title, artist: track.artistLine, savedAt: Date()), at: 0)
        persistIndex()
        return document
    }

    func remove(_ trackID: String) {
        try? FileManager.default.removeItem(at: file(trackID))
        entries.removeAll { $0.trackID == trackID }
        persistIndex()
    }

    private func file(_ trackID: String) -> URL {
        let safe = trackID.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
        return directory.appendingPathComponent(safe + ".ttml")
    }

    private func persistIndex() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }
}
