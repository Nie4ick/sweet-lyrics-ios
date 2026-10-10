import SwiftUI

/// Typography and spacing shared by all lines, from Spicy Lyrics' Mixed.css. `cqw` is 1% of the
/// lyrics container's width, the unit the stylesheet sizes spacing in.
struct LyricsTypography: Equatable {
    var fontSize: CGFloat
    var cqw: CGFloat = 3.9
    /// The song has duet (opposite-aligned) lines.
    var hasDuets = false

    var leadFont: Font { .system(size: fontSize, weight: .bold) }
    /// `.line.bg-line { --font-size: calc(var(--DefaultLyricsSize) * 0.75) }`
    var backgroundFontSize: CGFloat { fontSize * 0.75 }
    var backgroundFont: Font { .system(size: backgroundFontSize, weight: .bold) }
    /// `.word::after { margin-right: 0.32ch }` (a "0" in the bold face is ~0.6em wide).
    func wordGap(_ size: CGFloat) -> CGFloat { size * 0.6 * 0.32 }
    /// `.line { margin: 1cqw 0 }`, collapsing between neighbours.
    var lineSpacing: CGFloat { cqw }
    /// Static lyrics: `--DefaultLyricsSize: 5cqw` against the synced 7cqw, weight 500.
    var staticFont: Font { .system(size: fontSize * 5 / 7, weight: .medium) }
    /// `.line { padding-right: 5cqw }`, or the 15cqw duet inset on the side a line leans away from.
    func insets(opposite: Bool) -> EdgeInsets {
        if hasDuets {
            return opposite ? EdgeInsets(top: 0, leading: cqw * 15, bottom: 0, trailing: 0)
                            : EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: cqw * 15)
        }
        return EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: cqw * 5)
    }

    static func == (lhs: LyricsTypography, rhs: LyricsTypography) -> Bool {
        lhs.fontSize == rhs.fontSize && lhs.cqw == rhs.cqw && lhs.hasDuets == rhs.hasDuets
    }
}

/// How bright the lit / unlit parts of the fill gradient are (Mixed.css `--gradient-alpha*`).
struct GradientAlpha: Equatable {
    var lit: Double
    var unlit: Double

    static let lead = GradientAlpha(lit: 0.85, unlit: 0.5)
    static let background = GradientAlpha(lit: 0.6, unlit: 0.3)
}

/// The glow shadows of Spicy Lyrics, per element kind (`--text-shadow-*` in LyricsAnimator.ts).
enum GlowKind {
    case syllable, letter, dot, line

    /// CSS blur radius is ~2σ; SwiftUI's shadow radius is closer to σ.
    func radius(_ glow: Double) -> CGFloat {
        switch self {
        case .syllable: return (4 + 2 * glow) / 2
        case .letter: return (4 + 12 * glow) / 2
        case .dot: return (4 + 6 * glow) / 2
        case .line: return (4 + 8 * glow) / 2
        }
    }

    func opacity(_ glow: Double) -> Double {
        let value: Double
        switch self {
        case .syllable: value = glow * 0.35
        case .letter: value = glow * 1.85
        case .dot: value = glow * 0.9
        case .line: value = glow * 0.5
        }
        return clamp(value, 0, 1)
    }
}

extension View {
    /// Left-to-right fill: fully lit before `position`, unlit from `position + 0.2` on.
    func lyricFill(_ position: Double, alpha: GradientAlpha) -> some View {
        foregroundStyle(
            LinearGradient(
                colors: [.white.opacity(alpha.lit), .white.opacity(alpha.unlit)],
                startPoint: UnitPoint(x: position, y: 0.5),
                endPoint: UnitPoint(x: position + 0.2, y: 0.5)
            )
        )
    }

    @ViewBuilder
    func lyricGlow(_ glow: Double, kind: GlowKind) -> some View {
        let opacity = kind.opacity(glow)
        if opacity > 0.004 {
            shadow(color: .white.opacity(opacity), radius: kind.radius(glow))
        } else {
            self
        }
    }
}

// MARK: - Line

struct LyricLineView: View, Equatable {
    let line: PreparedLine
    let visual: LineVisual
    let typography: LyricsTypography

    static func == (lhs: LyricLineView, rhs: LyricLineView) -> Bool {
        lhs.line.id == rhs.line.id && lhs.visual == rhs.visual && lhs.typography == rhs.typography
    }

    private var horizontalAlignment: HorizontalAlignment { line.oppositeAligned ? .trailing : .leading }
    private var frameAlignment: Alignment { line.oppositeAligned ? .trailing : .leading }
    private var textAlignment: TextAlignment { line.oppositeAligned ? .trailing : .leading }

    var body: some View {
        content
            .padding(typography.insets(opposite: line.oppositeAligned))
            .frame(maxWidth: .infinity, alignment: frameAlignment)
            .opacity(visual.opacity)
            .blur(radius: visual.blur > 0.05 ? visual.blur / 2 : 0)
    }

    @ViewBuilder
    private var content: some View {
        switch line.kind {
        case .syllable(let lead, let background):
            // `.bg-line { margin: -1cqw 0 1cqw }` cancels the gap under the lead line.
            VStack(alignment: horizontalAlignment, spacing: 0) {
                if !lead.isEmpty {
                    WordFlowView(words: lead, visuals: visual.lead, fontSize: typography.fontSize,
                                 font: typography.leadFont, alpha: .lead, typography: typography,
                                 alignment: horizontalAlignment)
                }
                if !background.isEmpty {
                    WordFlowView(words: background, visuals: visual.background, fontSize: typography.backgroundFontSize,
                                 font: typography.backgroundFont, alpha: .background, typography: typography,
                                 alignment: horizontalAlignment)
                }
            }

        case .line(let text):
            Text(text)
                .font(typography.leadFont)
                .multilineTextAlignment(textAlignment)
                .lyricFill(visual.line.gradient, alpha: .lead)
                .lyricGlow(visual.state == .active ? visual.line.glow : 0, kind: .line)
                // Active line-synced lines grow to 1.05 from their aligned edge.
                .scaleEffect(visual.scale, anchor: line.oppositeAligned ? .trailing : .leading)

        case .static(let text):
            Text(text)
                .font(typography.staticFont)
                .multilineTextAlignment(textAlignment)
                .foregroundStyle(.white)

        case .interlude:
            InterludeDotsView(dots: visual.dots, presence: visual.presence, groupScale: visual.dotGroupScale,
                              typography: typography)
        }
    }
}

// MARK: - Words

/// Lays the words of a syllable-synced line out like text, never breaking inside a word.
private struct WordFlowView: View {
    let words: [PreparedWord]
    let visuals: [[SyllableVisual]]
    let fontSize: CGFloat
    let font: Font
    let alpha: GradientAlpha
    let typography: LyricsTypography
    let alignment: HorizontalAlignment

    var body: some View {
        FlowLayout(alignment: alignment, spacing: typography.wordGap(fontSize), rowSpacing: 0) {
            ForEach(words.indices, id: \.self) { w in
                HStack(spacing: 0) {
                    ForEach(words[w].syllables.indices, id: \.self) { s in
                        SyllableView(
                            syllable: words[w].syllables[s],
                            visual: visuals.indices.contains(w) && visuals[w].indices.contains(s) ? visuals[w][s] : SyllableVisual(),
                            fontSize: fontSize,
                            font: font,
                            alpha: alpha
                        )
                    }
                }
            }
        }
    }
}

private struct SyllableView: View {
    let syllable: PreparedSyllable
    let visual: SyllableVisual
    let fontSize: CGFloat
    let font: Font
    let alpha: GradientAlpha

    var body: some View {
        if let letters = syllable.letters, visual.letters.count == letters.count {
            HStack(spacing: 0) {
                ForEach(letters.indices, id: \.self) { i in
                    GlyphView(text: letters[i].text, visual: visual.letters[i], fontSize: fontSize,
                              font: font, alpha: alpha, glowKind: .letter)
                }
            }
        } else {
            GlyphView(text: syllable.text, visual: visual.glyph, fontSize: fontSize,
                      font: font, alpha: alpha, glowKind: .syllable)
        }
    }
}

private struct GlyphView: View {
    let text: String
    let visual: GlyphVisual
    let fontSize: CGFloat
    let font: Font
    let alpha: GradientAlpha
    let glowKind: GlowKind

    var body: some View {
        Text(text)
            .font(font)
            .fixedSize()
            .lyricFill(visual.gradient, alpha: alpha)
            .lyricGlow(visual.glow, kind: glowKind)
            .scaleEffect(visual.scale)
            .offset(y: visual.yOffset * fontSize)
    }
}

// MARK: - Interlude

/// The "•••" row of an instrumental gap (`.musical-line .dotGroup`): three "•" glyphs at 1.3× the
/// lyric size, packed tight, each with its own springs; the whole group pops in and out.
private struct InterludeDotsView: View {
    let dots: [GlyphVisual]
    let presence: Double
    let groupScale: Double
    let typography: LyricsTypography

    var body: some View {
        let dotSize = typography.fontSize * 1.3
        // `--dot-gap: clamp(0.005rem, 1.7cqw, 0.18rem)`
        let gap = min(max(0.08, typography.cqw * 1.7), 2.88)
        if presence > 0 {
            HStack(spacing: gap) {
                ForEach(dots.indices, id: \.self) { i in
                    let dot = dots[i]
                    Text("•")
                        .font(.system(size: dotSize, weight: .bold))
                        .foregroundStyle(.white.opacity(GradientAlpha.lead.lit))
                        .fixedSize()
                        .opacity(dot.opacity)
                        .lyricGlow(dot.glow, kind: .dot)
                        .scaleEffect(dot.scale)
                        .offset(y: dot.yOffset * typography.fontSize)
                }
            }
            // `line-height: 0.65` on the dots; the row itself keeps the lyric line height.
            .frame(height: typography.fontSize * 1.18)
            .scaleEffect(max(groupScale, 0.0001), anchor: .center)
        }
    }
}

// MARK: - Flow layout

/// Wrapping row layout: places subviews left to right and starts a new row when out of width.
struct FlowLayout: Layout {
    var alignment: HorizontalAlignment = .leading
    var spacing: CGFloat
    var rowSpacing: CGFloat

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrangeRows(for subviews: Subviews, maxWidth: CGFloat) -> ([Row], [CGSize]) {
        let sizes = subviews.map { subview -> CGSize in
            let ideal = subview.sizeThatFits(.unspecified)
            if ideal.width > maxWidth {
                return subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            }
            return ideal
        }
        var rows: [Row] = []
        var current = Row()
        for (index, size) in sizes.enumerated() {
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > maxWidth, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return (rows, sizes)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let (rows, _) = arrangeRows(for: subviews, maxWidth: maxWidth)
        let height = rows.reduce(0) { $0 + $1.height } + rowSpacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width.map { min($0, width) } ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (rows, sizes) = arrangeRows(for: subviews, maxWidth: bounds.width)
        var y = bounds.minY
        for row in rows {
            var x: CGFloat
            switch alignment {
            case .trailing: x = bounds.maxX - row.width
            case .center: x = bounds.minX + (bounds.width - row.width) / 2
            default: x = bounds.minX
            }
            for index in row.indices {
                let size = sizes[index]
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height)),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + rowSpacing
        }
    }
}
