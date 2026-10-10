import SwiftUI

/// The main screen, laid out like Apple Music's lyrics view: header and controls float over
/// full-height lyrics and fade away while a song plays. Landscape puts artwork and controls on
/// the left, lyrics on the right.
struct NowPlayingView: View {
    @Environment(PlayerModel.self) private var player
    @Environment(AppSettings.self) private var settings
    @EnvironmentObject private var auth: SpotifyAuth
    @Environment(PerformanceMonitor.self) private var performance
    @State private var showSettings = false
    @State private var showPicker = false
    @State private var showSetupGuide = false
    @State private var chromeVisible = true
    /// Bumped on every touch; restarts the auto-hide countdown.
    @State private var interactionTick = 0
    @State private var headerSwipe: CGFloat = 0
    @State private var headerHeight: CGFloat = 76
    @State private var controlsHeight: CGFloat = 250

    private static let autoHideDelay: Duration = .seconds(4)
    private static let chromeAnimation = Animation.easeInOut(duration: 0.45)

    var body: some View {
        GeometryReader { geometry in
            let landscape = geometry.size.width > geometry.size.height && geometry.size.width > 560
            ZStack {
                DynamicBackground(
                    image: settings.dynamicBackground ? player.backgroundArtwork : nil,
                    imageID: player.artworkID,
                    animated: settings.dynamicBackground && !reduced
                )

                if landscape {
                    landscapeLayout(geometry.size)
                } else {
                    portraitLayout(geometry.size)
                }
            }
        }
        .statusBarHidden(!chromeVisible)
        .persistentSystemOverlays(chromeVisible ? .automatic : .hidden)
        .task(id: AutoHideKey(tick: interactionTick, eligible: canAutoHide)) {
            guard canAutoHide else { return }
            try? await Task.sleep(for: Self.autoHideDelay)
            guard !Task.isCancelled, canAutoHide else { return }
            withAnimation(Self.chromeAnimation) { chromeVisible = false }
        }
        .onChange(of: player.isPlaying) { _, playing in
            // Pausing brings the controls back, like Apple Music.
            if !playing { showChrome() }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environment(settings)
                .environment(player)
                .environmentObject(auth)
        }
        .sheet(isPresented: $showSetupGuide) {
            NavigationStack {
                SpotifySetupGuideView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Закрыть") { showSetupGuide = false }
                        }
                    }
            }
            .environment(settings)
            .environmentObject(auth)
        }
        .sheet(isPresented: $showPicker) {
            TrackPickerView()
                .environment(player)
                .environmentObject(auth)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
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

    // MARK: Chrome visibility

    private struct AutoHideKey: Hashable {
        var tick: Int
        var eligible: Bool
    }

    /// Low Power Mode, a hot phone, or the battery saver setting.
    private var reduced: Bool { settings.powerSaving || performance.constrained }

    private var lyricsLoaded: Bool {
        if case .loaded = player.lyricsState { return true }
        return false
    }

    private var canAutoHide: Bool {
        settings.autoHideControls && chromeVisible && player.isPlaying && lyricsLoaded
            && !showSettings && !showPicker && !showSetupGuide
    }

    private func showChrome() {
        interactionTick += 1
        guard !chromeVisible else { return }
        withAnimation(Self.chromeAnimation) { chromeVisible = true }
    }

    private func toggleChrome() {
        interactionTick += 1
        withAnimation(Self.chromeAnimation) { chromeVisible.toggle() }
    }

    private func hideChrome() {
        withAnimation(Self.chromeAnimation) { chromeVisible = false }
    }

    // MARK: Portrait

    private func portraitLayout(_ size: CGSize) -> some View {
        ZStack {
            lyricsArea(
                topInset: chromeVisible ? headerHeight : 0,
                bottomInset: chromeVisible ? controlsHeight : 0,
                horizontalPadding: 28
            )

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 22)
                    .padding(.top, 10)
                    .padding(.bottom, 8)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
                    .opacity(chromeVisible ? 1 : 0)
                    .offset(y: chromeVisible ? 0 : -24)

                Spacer(minLength: 0)

                controls
                    .padding(.horizontal, 26)
                    .padding(.bottom, 6)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { controlsHeight = $0 }
                    .opacity(chromeVisible ? 1 : 0)
                    .offset(y: chromeVisible ? 0 : 40)
            }
            .allowsHitTesting(chromeVisible)

            // Like Apple Music: while the controls are hidden, where they live is not part of the
            // lyrics. A tap there brings them back instead of seeking to a line.
            if !chromeVisible {
                VStack(spacing: 0) {
                    wakeZone.frame(height: headerHeight)
                    Spacer(minLength: 0)
                    wakeZone.frame(height: controlsHeight)
                }
            }
        }
    }

    /// Invisible area that shows the controls on tap.
    private var wakeZone: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture { showChrome() }
            .accessibilityLabel("Показать элементы управления")
            .accessibilityAddTraits(.isButton)
    }

    // MARK: Landscape

    private func landscapeLayout(_ size: CGSize) -> some View {
        let showArtwork = settings.landscapeArtwork
        let showTitle = settings.landscapeTitle
        let column = min(size.width * 0.4, 420)
        let blockWidth = column - 40
        let artworkSide = min(blockWidth, size.height * (chromeVisible ? 0.42 : 0.62))
        let infoWidth = showArtwork ? artworkSide : min(blockWidth, 320)
        // With artwork and title switched off the column is empty once the controls hide:
        // slide the lyrics to the middle instead of leaving a gap (no re-wrapping).
        let columnEmpty = !showArtwork && !showTitle && !chromeVisible

        return HStack(spacing: 0) {
            VStack(spacing: 18) {
                Spacer(minLength: 0)
                if showArtwork {
                    artwork(side: artworkSide, cornerRadius: 12)
                        .scaleEffect(player.isPlaying ? 1 : 0.86)
                        .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
                        .animation(.spring(response: 0.5, dampingFraction: 0.75), value: player.isPlaying)
                        .onTapGesture { toggleChrome() }
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }

                if showTitle || chromeVisible {
                    HStack(alignment: .center, spacing: 10) {
                        if showTitle { titleBlock }
                        Spacer(minLength: 0)
                        moreMenu
                            .opacity(chromeVisible ? 1 : 0)
                    }
                    .frame(width: infoWidth)
                }

                if chromeVisible {
                    controls
                        .frame(width: max(infoWidth, 280))
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                Spacer(minLength: 0)
            }
            .frame(width: column)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            // Empty space in the column toggles the controls (the buttons keep their own taps).
            .onTapGesture { toggleChrome() }
            .padding(.leading, 12)
            .opacity(columnEmpty ? 0 : 1)

            lyricsArea(topInset: 0, bottomInset: 0, horizontalPadding: 24)
                .frame(width: max(0, size.width - column - 12))
        }
        .frame(width: size.width, alignment: .leading)
        .offset(x: columnEmpty ? -(column + 12) / 2 : 0)
        .overlay(alignment: .bottom) {
            if !chromeVisible {
                wakeZone.frame(height: size.height * 0.2)
            }
        }
        .animation(Self.chromeAnimation, value: showArtwork)
        .animation(Self.chromeAnimation, value: showTitle)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            trackInfo
            moreMenu
        }
        .foregroundStyle(.white)
    }

    /// Small artwork and title. Tap to pick a track, swipe sideways to skip.
    private var trackInfo: some View {
        HStack(spacing: 12) {
            artwork(side: 54, cornerRadius: 6)
            titleBlock
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .offset(x: headerSwipe)
        .opacity(1 - min(Double(abs(headerSwipe)) / 160, 0.6))
        .onTapGesture {
            showChrome()
            showPicker = true
        }
        .gesture(
            DragGesture(minimumDistance: 20)
                .onChanged { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    headerSwipe = value.translation.width * 0.5
                }
                .onEnded { value in
                    let width = value.translation.width
                    if abs(width) > 70, abs(width) > abs(value.translation.height) {
                        if width < 0 { player.next() } else { player.previous() }
                    }
                    showChrome()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { headerSwipe = 0 }
                }
        )
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Выбрать трек. Смахните влево или вправо, чтобы переключить трек.")
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .lineLimit(1)
            Text(subtitle)
                .font(.system(size: 17))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func artwork(side: CGFloat, cornerRadius: CGFloat) -> some View {
        Group {
            if let artwork = player.artwork {
                Image(uiImage: artwork).resizable().scaledToFill()
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: side * 0.35))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.white.opacity(0.1))
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    /// Apple Music's "•••" button.
    private var moreMenu: some View {
        Menu {
            Button {
                showPicker = true
            } label: {
                Label("Выбрать трек", systemImage: "music.note.list")
            }
            if let url = spotifyURL {
                Button {
                    UIApplication.shared.open(url)
                } label: {
                    Label("Открыть в Spotify", systemImage: "arrow.up.forward.app")
                }
            }
            Button {
                player.loadLyrics(force: true)
            } label: {
                Label("Перезагрузить текст", systemImage: "arrow.clockwise")
            }
            Divider()
            Button {
                showSettings = true
            } label: {
                Label("Настройки", systemImage: "gearshape")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(.white.opacity(0.18), in: Circle())
        }
        .simultaneousGesture(TapGesture().onEnded { showChrome() })
    }

    private var spotifyURL: URL? {
        guard let track = player.track else { return URL(string: "spotify:") }
        return URL(string: track.uri) ?? URL(string: "spotify:")
    }

    private var controls: some View {
        PlaybackBar(
            onInteraction: { showChrome() },
            onShowQueue: { showPicker = true },
            onHideControls: { hideChrome() },
            isVisible: chromeVisible
        )
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
    private func lyricsArea(topInset: CGFloat, bottomInset: CGFloat, horizontalPadding: CGFloat) -> some View {
        switch player.lyricsState {
        case .loaded(let lyrics):
            LyricsView(
                lyrics: lyrics, player: player, settings: settings,
                topInset: topInset, bottomInset: bottomInset,
                horizontalPadding: horizontalPadding, reduced: reduced,
                onInteraction: { showChrome() },
                onBackgroundTap: { toggleChrome() }
            )
            .id(player.lyricsRevision)
            .transition(.opacity)
        case .loading:
            LyricsSkeleton()
                .padding(.top, topInset)
                .frame(maxHeight: .infinity, alignment: .top)
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
            if player.accessProblem != nil {
                Button {
                    showSetupGuide = true
                } label: {
                    Label("Подключить свой Client ID", systemImage: "key.horizontal")
                        .font(.headline)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Color(red: 0.12, green: 0.84, blue: 0.38), in: Capsule())
                        .foregroundStyle(.black)
                }
            } else {
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
        }
        .foregroundStyle(.white)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
