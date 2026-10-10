import QuartzCore
import SwiftUI

/// The scrolling, animated lyrics. One `TimelineView` drives the animator once per frame.
struct LyricsView: View {
    let lyrics: PreparedLyrics
    let player: PlayerModel
    let settings: AppSettings
    /// Height (points) hidden under the header / controls; lyrics fade out before reaching them.
    var topInset: CGFloat = 0
    var bottomInset: CGFloat = 0
    var horizontalPadding: CGFloat = 24
    /// Where the active line settles, as a fraction of the view height.
    var focusAnchor: CGFloat = 0.3
    /// Any touch or scroll on the lyrics (shows the controls again).
    var onInteraction: () -> Void = {}
    /// A tap on empty space between lines (toggles the controls).
    var onBackgroundTap: () -> Void = {}

    @State private var animator: LyricsAnimator
    @State private var userScrolling = false
    @State private var resumeAutoScrollAt: Date = .distantPast

    init(lyrics: PreparedLyrics, player: PlayerModel, settings: AppSettings,
         topInset: CGFloat = 0, bottomInset: CGFloat = 0, horizontalPadding: CGFloat = 24,
         focusAnchor: CGFloat = 0.3,
         onInteraction: @escaping () -> Void = {}, onBackgroundTap: @escaping () -> Void = {}) {
        self.lyrics = lyrics
        self.player = player
        self.settings = settings
        self.topInset = topInset
        self.bottomInset = bottomInset
        self.horizontalPadding = horizontalPadding
        self.focusAnchor = focusAnchor
        self.onInteraction = onInteraction
        self.onBackgroundTap = onBackgroundTap
        _animator = State(initialValue: LyricsAnimator(lyrics: lyrics))
    }

    private var anchor: UnitPoint { UnitPoint(x: 0.5, y: focusAnchor) }

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
                                        onInteraction()
                                        guard shown.kind != .static else { return }
                                        resumeAutoScrollAt = .distantPast
                                        player.seek(to: max(0, line.start - settings.timingOffsetMs / 1000))
                                    }
                                    .id(line.id)
                            }
                            LyricsCreditsView(lyrics: shown, lyricSize: typography.fontSize)
                                .padding(.top, typography.fontSize * 0.45)
                        }
                        .padding(.horizontal, horizontalPadding)
                        .padding(.top, geometry.size.height * focusAnchor)
                        .padding(.bottom, geometry.size.height * (1 - focusAnchor))
                        .contentShape(Rectangle())
                        .onTapGesture { onBackgroundTap() }
                        .onChange(of: focus) { _, newFocus in
                            guard shown.kind != .static, !userScrolling, Date() >= resumeAutoScrollAt else { return }
                            withAnimation(.spring(response: 0.6, dampingFraction: 0.88)) {
                                proxy.scrollTo(newFocus, anchor: anchor)
                            }
                        }
                        .task {
                            guard shown.kind != .static else { return }
                            try? await Task.sleep(for: .milliseconds(80))
                            proxy.scrollTo(animator.focusIndex, anchor: anchor)
                        }
                    }
                }
                .modifier(ScrollInteractionObserver { interacting in
                    userScrolling = interacting
                    if interacting {
                        onInteraction()
                    } else {
                        resumeAutoScrollAt = Date().addingTimeInterval(2.5)
                    }
                })
                .mask(EdgeFade(top: topInset, bottom: bottomInset))
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

/// Soft fade at the top and bottom like the extension's `--ImageMask`. The clear bands follow the
/// header and controls, so lyrics never run underneath them (and animate with them).
private struct EdgeFade: View {
    var top: CGFloat
    var bottom: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: max(0, top))
            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                .frame(height: 56)
            Color.black
            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 72)
            Color.clear.frame(height: max(0, bottom))
        }
    }
}

/// The block after the last line, in Spicy Lyrics' order and wording (`ApplyLyricsCredits.ts`,
/// `ApplyProvider.ts`, `ApplyIsByCommunity.tsx`): writers, provider, then the community sync's
/// maker and uploader. Sizes follow Mixed.css relative to the lyric size.
private struct LyricsCreditsView: View {
    let lyrics: PreparedLyrics
    let lyricSize: CGFloat

    private var credits: LyricsCredits { lyrics.credits }
    /// A little larger than on desktop, for a phone screen (as the Android port does).
    private var small: CGFloat { max(12, lyricSize * 0.34 * 1.2) }

    var body: some View {
        VStack(alignment: .leading, spacing: lyricSize * 0.25) {
            if !lyrics.songwriters.isEmpty {
                Text("Written by: " + lyrics.songwriters.joined(separator: ", "))
                    .font(.system(size: max(14, lyricSize * 0.47), weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            if let provider = credits.providedBy {
                Text("Provided by: " + provider)
                    .font(.system(size: small, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
            }
            if credits.isCommunity == true, credits.maker != nil || credits.uploader != nil {
                Text("These lyrics have been provided by our community")
                    .font(.system(size: small, weight: .bold))
                    .foregroundStyle(.white.opacity(0.65))
            }
            if let maker = credits.maker {
                ContributorRow(role: "Made by", contributor: maker, size: small)
            }
            if let uploader = credits.uploader {
                ContributorRow(
                    role: credits.maker != nil ? "Uploaded by" : (credits.isCommunity == true ? "Made by" : "Submitted by"),
                    contributor: uploader,
                    size: small
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// "Made by @name" with the avatar after it; tapping opens the Spicy Lyrics profile.
private struct ContributorRow: View {
    let role: String
    let contributor: LyricsContributor
    let size: CGFloat
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 4) {
            (Text(role + " ").foregroundStyle(.white.opacity(0.6))
                + Text("@" + contributor.name).bold().underline().foregroundStyle(.white.opacity(0.75)))
                .font(.system(size: size, weight: .semibold))
            if let avatar = contributor.avatarURL {
                AsyncImage(url: avatar) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.white.opacity(0.1)
                }
                .frame(width: size * 1.4, height: size * 1.4)
                .clipShape(Circle())
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if let url = contributor.profileURL { openURL(url) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(contributor.profileURL != nil ? .isLink : [])
    }
}
