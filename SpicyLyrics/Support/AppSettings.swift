import Foundation
import Observation

/// User preferences, persisted in UserDefaults. The Spicy Lyrics key lives here too: it is a
/// public client key (`sl_pk_…`), not a secret.
@Observable
final class AppSettings {
    private let defaults: UserDefaults

    var spotifyClientID: String { didSet { defaults.set(spotifyClientID, forKey: Keys.clientID) } }
    var spicyLyricsKey: String { didSet { defaults.set(spicyLyricsKey, forKey: Keys.spicyKey) } }
    /// Shifts lyrics against the playback clock, in milliseconds. Positive = lyrics earlier.
    var timingOffsetMs: Double { didSet { defaults.set(timingOffsetMs, forKey: Keys.offset) } }
    var fontSize: Double { didSet { defaults.set(fontSize, forKey: Keys.fontSize) } }
    var blurInactiveLines: Bool { didSet { defaults.set(blurInactiveLines, forKey: Keys.blur) } }
    var dynamicBackground: Bool { didSet { defaults.set(dynamicBackground, forKey: Keys.background) } }
    var showRomanization: Bool { didSet { defaults.set(showRomanization, forKey: Keys.romanization) } }
    var useLRCLibFallback: Bool { didSet { defaults.set(useLRCLibFallback, forKey: Keys.lrclib) } }
    var keepScreenOn: Bool { didSet { defaults.set(keepScreenOn, forKey: Keys.keepScreenOn) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Keys.offset: 0.0,
            Keys.fontSize: 32.0,
            Keys.blur: true,
            Keys.background: true,
            Keys.romanization: false,
            Keys.lrclib: true,
            Keys.keepScreenOn: true,
        ])
        spotifyClientID = defaults.string(forKey: Keys.clientID) ?? ""
        spicyLyricsKey = defaults.string(forKey: Keys.spicyKey) ?? ""
        timingOffsetMs = defaults.double(forKey: Keys.offset)
        fontSize = defaults.double(forKey: Keys.fontSize)
        blurInactiveLines = defaults.bool(forKey: Keys.blur)
        dynamicBackground = defaults.bool(forKey: Keys.background)
        showRomanization = defaults.bool(forKey: Keys.romanization)
        useLRCLibFallback = defaults.bool(forKey: Keys.lrclib)
        keepScreenOn = defaults.bool(forKey: Keys.keepScreenOn)
    }

    /// The Spicy Lyrics client key when it looks like one (`sl_pk_…`).
    var validSpicyKey: String? {
        let key = spicyLyricsKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.hasPrefix("sl_pk_"), key.count >= 14 else { return nil }
        return key
    }

    private enum Keys {
        static let clientID = "spotifyClientID"
        static let spicyKey = "spicyLyricsKey"
        static let offset = "timingOffsetMs"
        static let fontSize = "fontSize"
        static let blur = "blurInactiveLines"
        static let background = "dynamicBackground"
        static let romanization = "showRomanization"
        static let lrclib = "useLRCLibFallback"
        static let keepScreenOn = "keepScreenOn"
    }
}
