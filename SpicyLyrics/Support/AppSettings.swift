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
    /// Fade the header and controls out while lyrics play, like Apple Music.
    var autoHideControls: Bool { didSet { defaults.set(autoHideControls, forKey: Keys.autoHide) } }

    /// Keys baked in at build time from `Config/Secrets.xcconfig` or CI secrets (may be empty).
    let bundledSpotifyClientID = AppSettings.bundled("SpicyBundledSpotifyClientID")
    let bundledSpicyLyricsKey = AppSettings.bundled("SpicyBundledLyricsKey")

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
            Keys.autoHide: true,
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
        autoHideControls = defaults.bool(forKey: Keys.autoHide)
    }

    /// The Client ID typed in the app, else the one built into it.
    var effectiveSpotifyClientID: String {
        spotifyClientID.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank ?? bundledSpotifyClientID ?? ""
    }

    var hasBundledSpotifyClientID: Bool { bundledSpotifyClientID != nil }

    /// The Spicy Lyrics client key typed in the app (when it looks like one), else the built-in one.
    var validSpicyKey: String? {
        Self.clientKey(spicyLyricsKey) ?? bundledSpicyLyricsKey.flatMap(Self.clientKey)
    }

    var hasBundledSpicyKey: Bool { bundledSpicyLyricsKey.flatMap(Self.clientKey) != nil }

    private static func clientKey(_ raw: String) -> String? {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.hasPrefix("sl_pk_"), key.count >= 14 else { return nil }
        return key
    }

    private static func bundled(_ infoKey: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: infoKey) as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        // An unset build setting can leak through as the literal "$(NAME)".
        guard !trimmed.isEmpty, !trimmed.hasPrefix("$(") else { return nil }
        return trimmed
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
        static let autoHide = "autoHideControls"
    }
}
