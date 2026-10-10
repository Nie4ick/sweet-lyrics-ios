import QuartzCore
import SwiftUI

/// The scrolling, animated lyrics. One `TimelineView` drives the animator once per frame.
struct LyricsView: View {
    let lyrics: PreparedLyrics
    let player: PlayerModel
    let settings: AppSettings

    @State private var animator: LyricsAnimator
    @State private var userScrolling = false
    @State private var resumeAutoScrollAt: Date = .distantPast

    init(lyrics: PreparedLyrics, player: PlayerModel, settings: AppSettings) {
        self.lyrics = lyrics
        self.player = player
        self.settings = settings
        _animator = State(initialValue: LyricsAnimator(lyrics: lyrics))
    }

    /// Always the animator's copy, so line indices and visuals can never disagree.
    private var shown: PreparedLyrics { animator.lyrics }

    private var typography: LyricsTypography { LyricsTypography(fontSize: CGFloat(settings.fontSize)) }

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    TimelineView(.animation(minimumInterval: player.isPlaying ? 1.0 / 60 : 1.0 / 20)) { _ in
                        let now = CACurrentMediaTime()
                        let _ = animator.step(position: player.position(at: now), now: now,
                                              blurEnabled: settings.blurInactiveLines && !userScrolling)
                        let focus = animator.focusIndex
                        let visuals = animator.visuals

                        LazyVStack(alignment: .leading, spacing: typography.fontSize * 0.55) {
                            ForEach(shown.lines) { line in
                                LyricLineView(line: line, visual: visuals[line.id], typography: typography)
                                    .equatable()
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        guard shown.kind != .static else { return }
                                        resumeAutoScrollAt = .distantPast
                                        player.seek(to: max(0, line.start - settings.timingOffsetMs / 1000))
                                    }
                                    .id(line.id)
                            }
                            LyricsCreditsView(lyrics: shown)
                                .padding(.top, typography.fontSize)
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, geometry.size.height * 0.3)
                        .padding(.bottom, geometry.size.height * 0.6)
                        .onChange(of: focus) { _, newFocus in
                            guard shown.kind != .static, !userScrolling, Date() >= resumeAutoScrollAt else { return }
                            withAnimation(.spring(response: 0.6, dampingFraction: 0.88)) {
                                proxy.scrollTo(newFocus, anchor: UnitPoint(x: 0.5, y: 0.3))
                            }
                        }
                        .task {
                            guard shown.kind != .static else { return }
                            try? await Task.sleep(for: .milliseconds(80))
                            proxy.scrollTo(animator.focusIndex, anchor: UnitPoint(x: 0.5, y: 0.3))
                        }
                    }
                }
                .modifier(ScrollInteractionObserver { interacting in
                    userScrolling = interacting
                    if !interacting { resumeAutoScrollAt = Date().addingTimeInterval(2.5) }
                })
                .mask(EdgeFade())
            }
        }
    }
}

/// Pauses auto-scroll while the user drags the lyrics (iOS 18+; on iOS 17 it simply keeps following).
private struct ScrollInteractionObserver: ViewModifier {
    let onChange: (Bool) -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollPhaseChange { oldPhase, newPhase in
                switch newPhase {
                case .interacting, .tracking:
                    onChange(true)
                case .idle:
                    // Only a user scroll coming to rest counts, not our own scrollTo animation.
                    switch oldPhase {
                    case .interacting, .tracking, .decelerating:
                        onChange(false)
                    default:
                        break
                    }
                default:
                    break
                }
            }
        } else {
            content
        }
    }
}

/// Soft fade at the top and bottom like the extension's `--ImageMask`.
private struct EdgeFade: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.12),
                .init(color: .black, location: 0.82),
                .init(color: .clear, location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

private struct LyricsCreditsView: View {
    let lyrics: PreparedLyrics

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !lyrics.songwriters.isEmpty {
                Text("Авторы: " + lyrics.songwriters.joined(separator: ", "))
            }
            Text("Источник: " + lyrics.sourceName)
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.white.opacity(0.55))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
