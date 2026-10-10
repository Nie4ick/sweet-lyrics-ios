import SwiftUI

@main
@MainActor
struct SpicyLyricsApp: App {
    @State private var settings: AppSettings
    @StateObject private var auth: SpotifyAuth
    @State private var player: PlayerModel
    @State private var performance = PerformanceMonitor()
    @State private var pip = LyricsPictureInPicture()

    init() {
        AudioRoute.prepare()
        let settings = AppSettings()
        let auth = SpotifyAuth(settings: settings)
        let api = SpotifyAPI(auth: auth)
        let localLyrics = LocalLyricsStore()
        let lyrics = LyricsService(settings: settings, auth: auth, local: localLyrics)
        _settings = State(initialValue: settings)
        _auth = StateObject(wrappedValue: auth)
        _player = State(initialValue: PlayerModel(api: api, lyrics: lyrics, settings: settings, localLyrics: localLyrics))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(player)
                .environment(performance)
                .environment(pip)
                .environmentObject(auth)
                .preferredColorScheme(.dark)
                .tint(.white)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var auth: SpotifyAuth
    @Environment(PlayerModel.self) private var player
    @Environment(AppSettings.self) private var settings
    @Environment(\.scenePhase) private var scenePhase
    @Environment(LyricsPictureInPicture.self) private var pip

    var body: some View {
        Group {
            if auth.isLoggedIn {
                NowPlayingView()
            } else {
                OnboardingView()
            }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in updateActivity(phase) }
        .onChange(of: auth.isLoggedIn) { _, _ in updateActivity(scenePhase) }
        .onChange(of: settings.keepScreenOn) { _, _ in updateActivity(scenePhase) }
        .onChange(of: pip.isActive) { _, _ in updateActivity(scenePhase) }
    }

    private func updateActivity(_ phase: ScenePhase) {
        let active = phase == .active && auth.isLoggedIn
        // The floating lyrics window keeps following Spotify while the app is in the background.
        if active || (pip.isActive && auth.isLoggedIn) {
            player.startPolling()
        } else {
            player.stopPolling()
        }
        UIApplication.shared.isIdleTimerDisabled = active && settings.keepScreenOn
    }
}
