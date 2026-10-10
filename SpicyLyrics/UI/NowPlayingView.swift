import QuartzCore
import SwiftUI

/// The main screen: background, header, lyrics and the playback bar.
struct NowPlayingView: View {
    @Environment(PlayerModel.self) private var player
    @Environment(AppSettings.self) private var settings
    @EnvironmentObject private var auth: SpotifyAuth
    @State private var showSettings = false
    @State private var showControls = true

    var body: some View {
        ZStack {
            DynamicBackground(
                image: settings.dynamicBackground ? player.backgroundArtwork : nil,
                imageID: player.artworkID,
                animated: settings.dynamicBackground
            )

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                lyricsArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if showControls {
                    PlaybackBar()
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environment(settings)
                .environment(player)
                .environmentObject(auth)
        }
        .onChange(of: settings.showRomanization) { _, _ in player.settingsChanged() }
        .alert("Spotify", isPresented: Binding(
            get: { player.transientError != nil },
            set: { if !$0 { player.transientError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(player.transientError ?? "")
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            Group {
                if let artwork = player.artwork {
                    Image(uiImage: artwork).resizable().scaledToFill()
                } else {
                    Image(systemName: "music.note")
                        .font(.title2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.white.opacity(0.1))
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)

            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) { showControls.toggle() }
            } label: {
                Image(systemName: showControls ? "chevron.down.circle" : "chevron.up.circle")
                    .font(.title2)
            }
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.title2)
            }
        }
        .foregroundStyle(.white)
    }

    private var title: String {
        switch player.content {
        case .track(let track): return track.title
        case .episode(let title, _, _): return title
        case .ad: return "Реклама"
        case .unknown: return "Неизвестный трек"
        case .none: return "Spicy Lyrics"
        }
    }

    private var subtitle: String {
        switch player.content {
        case .track(let track): return track.artistLine
        case .episode(_, let show, _): return show
        default: return player.statusMessage ?? "Ожидание Spotify…"
        }
    }

    // MARK: Lyrics

    @ViewBuilder
    private var lyricsArea: some View {
        switch player.lyricsState {
        case .loaded(let lyrics):
            LyricsView(lyrics: lyrics, player: player, settings: settings)
                .id(player.lyricsRevision)
                .transition(.opacity)
        case .loading:
            LyricsSkeleton()
        case .notFound:
            message(icon: "text.badge.xmark", title: "Текст не найден",
                    detail: "Для этого трека пока нет текста ни в Spicy Lyrics, ни в LRCLIB.",
                    retry: true)
        case .failed(let reason):
            message(icon: "wifi.exclamationmark", title: "Не удалось загрузить текст", detail: reason, retry: true)
        case .unavailable(let reason):
            message(icon: "music.note", title: reason, detail: nil, retry: false)
        case .idle:
            idleState
        }
    }

    private var idleState: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.quarternote.3")
                .font(.system(size: 44))
            Text(player.statusMessage ?? "Включите музыку в Spotify")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            Button {
                if let url = URL(string: "spotify:") { UIApplication.shared.open(url) }
            } label: {
                Label("Открыть Spotify", systemImage: "arrow.up.forward.app")
                    .font(.headline)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(.white.opacity(0.15), in: Capsule())
            }
        }
        .foregroundStyle(.white)
        .padding(32)
    }

    private func message(icon: String, title: String, detail: String?, retry: Bool) -> some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 40))
            Text(title)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            if let detail {
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            if retry {
                Button("Повторить") { player.loadLyrics(force: true) }
                    .buttonStyle(.bordered)
            }
        }
        .foregroundStyle(.white)
        .padding(32)
    }
}

/// Placeholder bars while lyrics load (the extension's LyricsSkeleton).
private struct LyricsSkeleton: View {
    @State private var pulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            ForEach(0..<6, id: \.self) { i in
                RoundedRectangle(cornerRadius: 10)
                    .fill(.white.opacity(pulse ? 0.16 : 0.08))
                    .frame(width: [260, 200, 300, 170, 240, 210][i], height: 30)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

// MARK: - Playback bar

struct PlaybackBar: View {
    @Environment(PlayerModel.self) private var player
    @State private var dragFraction: Double?

    var body: some View {
        VStack(spacing: 10) {
            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                let duration = max(player.track?.duration ?? 0, 0.001)
                let position = player.playbackPosition(at: CACurrentMediaTime())
                let fraction = dragFraction ?? clamp(position / duration, 0, 1)
                VStack(spacing: 6) {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.2))
                            Capsule().fill(.white)
                                .frame(width: geometry.size.width * fraction)
                        }
                        .frame(height: dragFraction == nil ? 4 : 8)
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    dragFraction = Double(clamp(value.location.x / max(geometry.size.width, 1), 0, 1))
                                }
                                .onEnded { value in
                                    let f = Double(clamp(value.location.x / max(geometry.size.width, 1), 0, 1))
                                    player.seek(to: f * duration)
                                    dragFraction = nil
                                }
                        )
                    }
                    .frame(height: 20)
                    .animation(.easeOut(duration: 0.15), value: dragFraction == nil)

                    HStack {
                        Text(Self.format(fraction * duration))
                        Spacer()
                        Text("-" + Self.format(duration - fraction * duration))
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.7))
                }
            }
            .disabled(player.track == nil)

            HStack(spacing: 44) {
                Button { player.previous() } label: {
                    Image(systemName: "backward.fill").font(.title2)
                }
                Button { player.togglePlay() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 34))
                        .frame(width: 44)
                        .contentTransition(.symbolEffect(.replace))
                }
                Button { player.next() } label: {
                    Image(systemName: "forward.fill").font(.title2)
                }
            }
            .foregroundStyle(.white)
        }
    }

    static func format(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
