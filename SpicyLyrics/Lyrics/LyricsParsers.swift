import Foundation

/// Turns a Spicy Lyrics API body (`{ Type, Content, Lines, StartTime, SongWriters, source }`)
/// into a `LyricsDocument`. Times in the API are seconds.
enum SpicyLyricsParser {
    static func parse(body: [String: Any]) -> LyricsDocument? {
        let type = JSONLoose.string(body["Type"]) ?? ""
        let songwriters = (body["SongWriters"] as? [Any])?.compactMap { $0 as? String } ?? []
        let sourceName = "Spicy Lyrics · " + originName(JSONLoose.string(body["source"]))

        switch type.lowercased() {
        case "syllable":
            let lines = parseSyllableLines(JSONLoose.objects(body["Content"]))
            guard !lines.isEmpty else { return nil }
            return LyricsDocument(kind: .syllable, lines: lines, songwriters: songwriters, sourceName: sourceName)
        case "line":
            let lines = parseLineLines(JSONLoose.objects(body["Content"]))
            guard !lines.isEmpty else { return nil }
            return LyricsDocument(kind: .line, lines: lines, songwriters: songwriters, sourceName: sourceName)
        default:
            let staticLines = JSONLoose.objects(body["Lines"]).compactMap { item -> LyricLine? in
                guard let text = JSONLoose.string(item["Text"]) else { return nil }
                let trimmed = text.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return nil }
                return LyricLine(start: 0, end: 0, oppositeAligned: false, text: trimmed,
                                 romanizedText: JSONLoose.string(item["TransliteratedText"]),
                                 lead: [], background: [])
            }
            guard !staticLines.isEmpty else { return nil }
            return LyricsDocument(kind: .static, lines: staticLines, songwriters: songwriters, sourceName: sourceName)
        }
    }

    private static func parseSyllables(_ raw: Any?) -> [LyricSyllable] {
        JSONLoose.objects(raw).compactMap { item in
            guard let text = JSONLoose.string(item["Text"]),
                  let start = JSONLoose.double(item["StartTime"]),
                  let end = JSONLoose.double(item["EndTime"])
            else { return nil }
            return LyricSyllable(
                text: text,
                romanized: JSONLoose.string(item["TransliteratedText"])?.nilIfBlank,
                start: start,
                end: max(end, start),
                joinsNext: JSONLoose.bool(item["IsPartOfWord"]) ?? false
            )
        }
    }

    private static func parseSyllableLines(_ content: [[String: Any]]) -> [LyricLine] {
        let defaultAgent = content.lazy.compactMap { JSONLoose.string($0["Agent"]) }.first
        var lines: [LyricLine] = []
        for item in content {
            if JSONLoose.string(item["Type"])?.lowercased() == "interlude" { continue }
            guard let lead = item["Lead"] as? [String: Any] else { continue }
            let leadSyllables = parseSyllables(lead["Syllables"]).filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
            let background = JSONLoose.objects(item["Background"]).flatMap { parseSyllables($0["Syllables"]) }
                .filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
            if leadSyllables.isEmpty && background.isEmpty { continue }

            let all = leadSyllables + background
            let start = min(JSONLoose.double(lead["StartTime"]) ?? .infinity, all.map(\.start).min() ?? .infinity)
            let end = max(JSONLoose.double(lead["EndTime"]) ?? 0, all.map(\.end).max() ?? 0)
            let agent = JSONLoose.string(item["Agent"])
            let opposite = JSONLoose.bool(item["OppositeAligned"])
                ?? (agent != nil && defaultAgent != nil && agent != defaultAgent)

            lines.append(LyricLine(
                start: start.isFinite ? start : 0,
                end: end,
                oppositeAligned: opposite,
                text: leadSyllables.map(\.text).joined(separator: " "),
                romanizedText: nil,
                lead: leadSyllables,
                background: background
            ))
        }
        return lines.sorted { $0.start < $1.start }
    }

    private static func parseLineLines(_ content: [[String: Any]]) -> [LyricLine] {
        content.compactMap { item -> LyricLine? in
            if JSONLoose.string(item["Type"])?.lowercased() == "interlude" { return nil }
            guard let text = JSONLoose.string(item["Text"])?.trimmingCharacters(in: .whitespaces), !text.isEmpty,
                  let start = JSONLoose.double(item["StartTime"]),
                  let end = JSONLoose.double(item["EndTime"])
            else { return nil }
            return LyricLine(
                start: start,
                end: max(end, start),
                oppositeAligned: JSONLoose.bool(item["OppositeAligned"]) ?? false,
                text: text,
                romanizedText: JSONLoose.string(item["TransliteratedText"])?.nilIfBlank,
                lead: [],
                background: []
            )
        }
        .sorted { $0.start < $1.start }
    }

    static func originName(_ raw: String?) -> String {
        let key = (raw ?? "").trimmingCharacters(in: .whitespaces).lowercased()
            .replacingOccurrences(of: "-", with: "_").replacingOccurrences(of: " ", with: "_")
        switch key {
        case "apple", "apple_music", "am", "aml": return "Apple Music"
        case "spotify", "spotify_lyrics", "spt": return "Spotify"
        case "spicy", "spicy_lyrics", "community", "spl": return "Community"
        case "": return "API"
        default: return raw ?? "API"
        }
    }
}

/// Parses `[mm:ss.xx] text` LRC (as served by LRCLIB) into a line-timed document.
enum LRCParser {
    static func parse(_ lrc: String, duration: Double?, sourceName: String) -> LyricsDocument? {
        var timed: [(Double, String)] = []
        let tagPattern = try! NSRegularExpression(pattern: #"\[(\d{1,3}):(\d{1,2}(?:[.:]\d{1,3})?)\]"#)

        for rawLine in lrc.components(separatedBy: .newlines) {
            let ns = rawLine as NSString
            let matches = tagPattern.matches(in: rawLine, range: NSRange(location: 0, length: ns.length))
            guard let last = matches.last else { continue }
            let text = ns.substring(from: last.range.location + last.range.length)
                .trimmingCharacters(in: .whitespaces)
            for match in matches {
                let minutes = Double(ns.substring(with: match.range(at: 1))) ?? 0
                let seconds = Double(ns.substring(with: match.range(at: 2)).replacingOccurrences(of: ":", with: ".")) ?? 0
                timed.append((minutes * 60 + seconds, text))
            }
        }
        timed.sort { $0.0 < $1.0 }

        var lines: [LyricLine] = []
        for (index, entry) in timed.enumerated() where !entry.1.isEmpty {
            let nextStart = index + 1 < timed.count ? timed[index + 1].0 : (duration ?? entry.0 + 5)
            // A line ends where the next one starts, but a long gap still deserves an interlude.
            let end = nextStart - entry.0 > 10 ? entry.0 + 6 : nextStart
            lines.append(LyricLine(start: entry.0, end: max(end, entry.0 + 0.1), oppositeAligned: false,
                                   text: entry.1, romanizedText: nil, lead: [], background: []))
        }
        guard !lines.isEmpty else { return nil }
        return LyricsDocument(kind: .line, lines: lines, songwriters: [], sourceName: sourceName)
    }

    static func plain(_ text: String, sourceName: String) -> LyricsDocument? {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { LyricLine(start: 0, end: 0, oppositeAligned: false, text: $0, romanizedText: nil, lead: [], background: []) }
        guard !lines.isEmpty else { return nil }
        return LyricsDocument(kind: .static, lines: lines, songwriters: [], sourceName: sourceName)
    }
}

extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
