import Foundation

/// How a lyrics document is timed. Mirrors Spicy Lyrics' `Syllable` / `Line` / `Static` types.
enum LyricsKind: String, Codable {
    case syllable = "Syllable"
    case line = "Line"
    case `static` = "Static"
}

/// One timed piece of text. All times are in seconds.
struct LyricSyllable: Codable, Hashable {
    var text: String
    var romanized: String?
    var start: Double
    var end: Double
    /// The next syllable belongs to the same word (no space between them).
    var joinsNext: Bool
}

struct LyricLine: Codable, Hashable {
    var start: Double
    var end: Double
    /// Duet partner: drawn on the opposite side.
    var oppositeAligned: Bool
    /// Plain text for `line` / `static` documents.
    var text: String
    var romanizedText: String?
    /// Word-timed lead vocal (only for `syllable` documents).
    var lead: [LyricSyllable]
    /// Word-timed background vocals, all groups flattened (kept for lyrics cached before
    /// `backgroundGroups` existed).
    var background: [LyricSyllable]
    /// Each background group on its own: the extension gives every one its own `bg-line`, so a
    /// line can have two background vocals one after the other.
    var backgroundGroups: [[LyricSyllable]]? = nil

    var backgroundVocals: [[LyricSyllable]] {
        backgroundGroups ?? (background.isEmpty ? [] : [background])
    }
}

/// A person credited for a sync (Spicy Lyrics' `UploadAttribution` / `TTMLUploadMetadata`).
struct LyricsContributor: Codable, Hashable {
    var name: String
    var profileURL: URL?
    var avatarURL: URL?
}

/// The attribution shown after the lyrics, as the Spicy Lyrics API asks clients to.
/// Optional fields so lyrics cached before they existed still decode.
struct LyricsCredits: Codable, Hashable {
    /// The catalogue that answered: "Apple Music", "Spotify", "Spicy Lyrics", "LRCLIB"…
    var providedBy: String?
    /// A Spicy Lyrics community sync ("These lyrics have been provided by our community").
    var isCommunity: Bool?
    var maker: LyricsContributor?
    var uploader: LyricsContributor?
}

struct LyricsDocument: Codable, Hashable {
    var kind: LyricsKind
    var lines: [LyricLine]
    var songwriters: [String]
    /// Human readable provider, e.g. "Spicy Lyrics · Apple Music".
    var sourceName: String
    var credits: LyricsCredits? = nil

    var hasRomanization: Bool {
        lines.contains { line in
            line.romanizedText != nil
                || line.lead.contains { $0.romanized != nil }
                || line.background.contains { $0.romanized != nil }
        }
    }
}

// MARK: - Prepared (render-ready) model

/// A letter of an emphasized ("letter capable") syllable, with its own slice of the syllable's time.
struct PreparedLetter: Hashable {
    var text: String
    var start: Double
    var end: Double
}

struct PreparedSyllable: Hashable {
    var text: String
    var start: Double
    var end: Double
    /// Non-nil when the syllable is long enough to animate letter by letter.
    var letters: [PreparedLetter]?
}

/// Syllables that are glued together into one word and must never wrap apart.
struct PreparedWord: Hashable {
    var syllables: [PreparedSyllable]
}

enum PreparedLineKind: Hashable {
    case syllable(lead: [PreparedWord], background: [PreparedWord])
    case line(text: String)
    case `static`(text: String)
    /// "• • •" shown during instrumental gaps.
    case interlude(dots: [PreparedLetter])
}

struct PreparedLine: Identifiable, Hashable {
    let id: Int
    var start: Double
    var end: Double
    var oppositeAligned: Bool
    var kind: PreparedLineKind
    /// A background vocal (`.line.bg-line`): its own row under its lead line, smaller and dimmer.
    var isBackground = false
    /// For background rows: the lead line they belong to (focus never stops on a background row).
    var leadID: Int?
    /// The line in its original language and script, what gets translated.
    var sourceText = ""

    var isInterlude: Bool {
        if case .interlude = kind { return true }
        return false
    }

    /// The line as plain text (copy / share).
    var plainText: String {
        switch kind {
        case .syllable(let lead, let background):
            return (lead + background).map { $0.syllables.map(\.text).joined() }.joined(separator: " ")
        case .line(let text), .static(let text):
            return text
        case .interlude:
            return ""
        }
    }
}

struct PreparedLyrics: Hashable {
    var kind: LyricsKind
    var lines: [PreparedLine]
    var songwriters: [String]
    var sourceName: String
    var credits: LyricsCredits

    /// Gap (seconds) that earns an interlude, like Spicy Lyrics' `getLyricsBetweenShow()`.
    static let interludeThreshold: Double = 3
    /// The dots finish this long before the next line (Spicy's `preHiddenDotLineMs + 50`).
    static let interludePadding: Double = 0.55
    /// Syllables at least this long are animated per letter (Spicy's `IsLetterCapable`).
    static let letterCapableDuration: Double = 1.0
    /// Emphasized letters end early so the last one gets to breathe (Spicy's `Emphasize`).
    static let emphasisEndSubtraction: Double = 0.25

    init(document: LyricsDocument, romanized: Bool, simple: Bool = false) {
        kind = document.kind
        songwriters = document.songwriters
        sourceName = document.sourceName
        credits = document.credits ?? LyricsCredits(providedBy: document.sourceName)

        // Romanization: the API's own where it has one, otherwise done on the device.
        let script = romanized ? Romanizer.script(of: document) : nil
        func roman(_ text: String, _ fromAPI: String?) -> String {
            guard romanized else { return text }
            return fromAPI ?? script.map { Romanizer.romanize(text, script: $0) } ?? text
        }

        var result: [PreparedLine] = []
        func append(_ start: Double, _ end: Double, _ opposite: Bool, _ kind: PreparedLineKind, source: String = "") {
            result.append(PreparedLine(id: result.count, start: start, end: end, oppositeAligned: opposite, kind: kind,
                                       sourceText: source))
        }

        let source = document.lines
        switch document.kind {
        case .static:
            for line in source {
                append(0, 0, line.oppositeAligned, .static(text: roman(line.text, line.romanizedText)), source: line.text)
            }
        case .line, .syllable:
            if let first = source.first, first.start >= Self.interludeThreshold {
                append(0, first.start, first.oppositeAligned, .interlude(dots: Self.dots(from: 0, to: first.start)))
            }
            // A long line (e.g. a trailing backing vocal) can outlast the lines after it, so a
            // gap only counts once every line before it has finished.
            var latestEnd = 0.0
            for (index, line) in source.enumerated() {
                latestEnd = max(latestEnd, line.end)
                if document.kind == .syllable {
                    // The lead and each background group become rows of their own, timed by their
                    // own syllables (`Applyer/Synced/Syllable.ts`).
                    var leadID: Int?
                    let lead = Self.words(from: line.lead, simple: simple) { roman($0.text, $0.romanized) }
                    if !lead.isEmpty {
                        leadID = result.count
                        append(line.lead.map(\.start).min() ?? line.start, line.lead.map(\.end).max() ?? line.end,
                               line.oppositeAligned, .syllable(lead: lead, background: []), source: Self.plain(line.lead))
                    }
                    for group in line.backgroundVocals {
                        let words = Self.words(from: group, simple: simple) { roman($0.text, $0.romanized) }
                        guard !words.isEmpty, let start = group.map(\.start).min(), let end = group.map(\.end).max() else { continue }
                        result.append(PreparedLine(id: result.count, start: start, end: end,
                                                   oppositeAligned: line.oppositeAligned,
                                                   kind: .syllable(lead: words, background: []),
                                                   isBackground: true, leadID: leadID, sourceText: Self.plain(group)))
                    }
                } else {
                    append(line.start, line.end, line.oppositeAligned, .line(text: roman(line.text, line.romanizedText)),
                           source: line.text)
                }
                if index + 1 < source.count {
                    let next = source[index + 1]
                    if next.start - latestEnd >= Self.interludeThreshold {
                        append(latestEnd, next.start, next.oppositeAligned,
                               .interlude(dots: Self.dots(from: latestEnd, to: next.start)))
                    }
                }
            }
        }
        lines = result
    }

    /// The three dots' timing, exactly as `Applyer/Synced/Syllable.ts` lays them out: thirds of the
    /// gap, each pulled earlier by a third of the padding, the last one ending `padding` early.
    private static func dots(from start: Double, to end: Double) -> [PreparedLetter] {
        let total = end - start
        let third = total / 3
        let padding = interludePadding / 3
        let dot1 = max(start, start + third - padding)
        let dot2 = max(dot1, start + third * 2 - padding * 2)
        let dot3 = max(dot2, start + total - interludePadding)
        return [
            PreparedLetter(text: "•", start: start, end: dot1),
            PreparedLetter(text: "•", start: dot1, end: dot2),
            PreparedLetter(text: "•", start: dot2, end: dot3),
        ]
    }

    /// Syllables as one string, spaced where words end.
    private static func plain(_ syllables: [LyricSyllable]) -> String {
        syllables.map { $0.text + ($0.joinsNext ? "" : " ") }.joined().trimmingCharacters(in: .whitespaces)
    }

    private static func words(from syllables: [LyricSyllable], simple: Bool,
                              display: (LyricSyllable) -> String) -> [PreparedWord] {
        var words: [PreparedWord] = []
        var current: [PreparedSyllable] = []
        // Syllables are drawn left to right, so they must also light up left to right. Some
        // sources time a word slightly before the one in front of it; start it with that one
        // instead of lighting the line out of order.
        var earliestStart = -Double.infinity
        for syllable in syllables {
            let raw = display(syllable)
            let text = raw.replacingOccurrences(of: "\u{200B}", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                let start = max(syllable.start, earliestStart)
                earliestStart = start
                current.append(prepare(text: text, start: start, end: max(syllable.end, start), simple: simple))
            }
            if !syllable.joinsNext, !current.isEmpty {
                words.append(PreparedWord(syllables: current))
                current = []
            }
        }
        if !current.isEmpty { words.append(PreparedWord(syllables: current)) }
        return words
    }

    /// `IsLetterCapable` and `Emphasize`: long syllables animate per letter. Simple Lyrics Mode
    /// only does so for up to 12 letters lasting 1.05 s, and shifts the letters a little later.
    private static func prepare(text: String, start: Double, end: Double, simple: Bool) -> PreparedSyllable {
        let characters = text.map(String.init)
        let duration = end - start
        let capable = characters.count > 1 && !TextDirection.isRightToLeft(text)
            && (simple ? characters.count <= 12 && duration >= 1.05 : duration >= letterCapableDuration)
        guard capable else { return PreparedSyllable(text: text, start: start, end: end, letters: nil) }

        let letterStart = simple ? start + 0.021 : start
        let letterEnd = simple ? end + 0.04 : max(start + 0.05, end - emphasisEndSubtraction)
        let each = (letterEnd - letterStart) / Double(characters.count)
        let letters = characters.enumerated().map { index, character in
            PreparedLetter(text: character, start: letterStart + Double(index) * each,
                           end: letterStart + Double(index + 1) * each)
        }
        return PreparedSyllable(text: text, start: start, end: end, letters: letters)
    }
}

enum TextDirection {
    static func isRightToLeft(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x0590...0x08FF, 0xFB1D...0xFDFF, 0xFE70...0xFEFF:
                return true
            default:
                continue
            }
        }
        return false
    }
}
