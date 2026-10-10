import Foundation
import Observation

/// User preferences, persisted in UserDefaults. The Spicy Lyrics key lives here too: it is a
/// public client key (`sl_pk_…`), not a secret.
@Observable
final class AppSettings {
    private let defaults: UserDefaults

    /// The user's own Client ID (from their own Spotify developer app).
    var spotifyClientID: String { didSet { defaults.set(spotifyClientID, forKey: Keys.clientID) } }
    /// Use `spotifyClientID` instead of the built-in one (whose allowlist holds only five people).
    var useOwnClientID: Bool { didSet { defaults.set(useOwnClientID, forKey: Keys.useOwnClientID) } }
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
    /// Subtract the audio output delay (Bluetooth) when Spotify plays on this iPhone.
    var compensateOutputLatency: Bool { didSet { defaults.set(compensateOutputLatency, forKey: Keys.outputLatency) } }
    /// Swipes to change tracks and pinch to resize the lyrics.
    var gesturesEnabled: Bool { didSet { defaults.set(gesturesEnabled, forKey: Keys.gestures) } }
    /// The system volume slider under the playback buttons.
    var showVolumeSlider: Bool { didSet { defaults.set(showVolumeSlider, forKey: Keys.volumeSlider) } }
    /// Battery saver: 30 fps lyrics, no line blur, still background.
    var powerSaving: Bool { didSet { defaults.set(powerSaving, forKey: Keys.powerSaving) } }
    /// Landscape: show the big artwork / the title and artist next to the lyrics.
    var landscapeArtwork: Bool { didSet { defaults.set(landscapeArtwork, forKey: Keys.landscapeArtwork) } }
    var landscapeTitle: Bool { didSet { defaults.set(landscapeTitle, forKey: Keys.landscapeTitle) } }

    /// Keys baked in at build time from `Config/Secrets.xcconfig` or CI secrets (may be empty).
    /// When present they are fixed: the app ignores anything typed in settings.
    let bundledSpotifyClientID = BundledKeys.spotifyClientID
    let bundledSpicyLyricsKey = BundledKeys.spicyLyricsKey.flatMap(AppSettings.clientKey)

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
            Keys.useOwnClientID: false,
            Keys.landscapeArtwork: true,
            Keys.powerSaving: false,
            Keys.volumeSlider: true,
            Keys.gestures: true,
            Keys.outputLatency: true,
            Keys.landscapeTitle: true,
        ])
        spotifyClientID = defaults.string(forKey: Keys.clientID) ?? ""
        spicyLyricsKey = defaults.string(forKey: Keys.spicyKey) ?? ""
        useOwnClientID = defaults.bool(forKey: Keys.useOwnClientID)
        timingOffsetMs = defaults.double(forKey: Keys.offset)
        fontSize = defaults.double(forKey: Keys.fontSize)
        blurInactiveLines = defaults.bool(forKey: Keys.blur)
        dynamicBackground = defaults.bool(forKey: Keys.background)
        showRomanization = defaults.bool(forKey: Keys.romanization)
        useLRCLibFallback = defaults.bool(forKey: Keys.lrclib)
        keepScreenOn = defaults.bool(forKey: Keys.keepScreenOn)
        autoHideControls = defaults.bool(forKey: Keys.autoHide)
        powerSaving = defaults.bool(forKey: Keys.powerSaving)
        showVolumeSlider = defaults.bool(forKey: Keys.volumeSlider)
        gesturesEnabled = defaults.bool(forKey: Keys.gestures)
        compensateOutputLatency = defaults.bool(forKey: Keys.outputLatency)
        landscapeArtwork = defaults.bool(forKey: Keys.landscapeArtwork)
        landscapeTitle = defaults.bool(forKey: Keys.landscapeTitle)
    }

    /// The built-in Client ID, unless the user switched to their own (or none is built in).
    var effectiveSpotifyClientID: String {
        if usingBundledClientID, let bundled = bundledSpotifyClientID { return bundled }
        return spotifyClientID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var usingBundledClientID: Bool { bundledSpotifyClientID != nil && !useOwnClientID }

    /// A Spotify Client ID is 32 hex characters.
    static func isValidClientID(_ raw: String) -> Bool {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.count == 32 && value.allSatisfy(\.isHexDigit)
    }

    var hasBundledSpotifyClientID: Bool { bundledSpotifyClientID != nil }

    /// The Spicy Lyrics client key built into the app, else the one typed in settings.
    var validSpicyKey: String? {
        bundledSpicyLyricsKey ?? Self.clientKey(spicyLyricsKey)
    }

    var hasBundledSpicyKey: Bool { bundledSpicyLyricsKey != nil }

    private static func clientKey(_ raw: String) -> String? {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.hasPrefix("sl_pk_"), key.count >= 14 else { return nil }
        return key
    }

    /// Lyric font size limits (settings slider and pinch).
    static let fontRange: ClosedRange<CGFloat> = 22...56

    private enum Keys {
        static let clientID = "spotifyClientID"
        static let useOwnClientID = "useOwnClientID"
        static let spicyKey = "spicyLyricsKey"
        static let offset = "timingOffsetMs"
        static let fontSize = "fontSize"
        static let blur = "blurInactiveLines"
        static let background = "dynamicBackground"
        static let romanization = "showRomanization"
        static let lrclib = "useLRCLibFallback"
        static let keepScreenOn = "keepScreenOn"
        static let autoHide = "autoHideControls"
        static let powerSaving = "powerSaving"
        static let volumeSlider = "showVolumeSlider"
        static let gestures = "gesturesEnabled"
        static let outputLatency = "compensateOutputLatency"
        static let landscapeArtwork = "landscapeArtwork"
        static let landscapeTitle = "landscapeTitle"
    }
}
