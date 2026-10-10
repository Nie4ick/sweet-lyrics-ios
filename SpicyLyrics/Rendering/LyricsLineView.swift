import SwiftUI

/// Typography shared by all lines.
struct LyricsTypography: Equatable {
    var fontSize: CGFloat

    var leadFont: Font { .system(size: fontSize, weight: .bold) }
    var backgroundFontSize: CGFloat { fontSize * 0.62 }
    var backgroundFont: Font { .system(size: backgroundFontSize, weight: .bold) }
    var wordGap: CGFloat { fontSize * 0.26 }
    var rowSpacing: CGFloat { fontSize * 0.06 }
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
            .frame(maxWidth: .infinity, alignment: frameAlignment)
            .opacity(visual.opacity)
            .blur(radius: visual.blur / 2)
    }

    @ViewBuilder
    private var content: some View {
        switch line.kind {
        case .syllable(let lead, let background):
            VStack(alignment: horizontalAlignment, spacing: typography.fontSize * 0.12) {
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

        case .static(let text):
            Text(text)
                .font(typography.leadFont)
                .multilineTextAlignment(textAlignment)
                .foregroundStyle(.white.opacity(0.85))

        case .interlude:
            InterludeDotsView(dots: visual.dots, presence: visual.presence, fontSize: typography.fontSize)
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
        FlowLayout(alignment: alignment, spacing: fontSize * 0.26, rowSpacing: typography.rowSpacing) {
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

private struct InterludeDotsView: View {
    let dots: [GlyphVisual]
    let presence: Double
    let fontSize: CGFloat

    var body: some View {
        let shown = clamp(presence, 0, 1)
        HStack(spacing: fontSize * 0.28) {
            ForEach(dots.indices, id: \.self) { i in
                let dot = dots[i]
                Circle()
                    .fill(.white)
                    .frame(width: fontSize * 0.3, height: fontSize * 0.3)
                    .opacity(dot.opacity)
                    .lyricGlow(dot.glow, kind: .dot)
                    .scaleEffect(dot.scale)
                    .offset(y: dot.yOffset * fontSize)
            }
        }
        .scaleEffect(max(presence, 0.001), anchor: .leading)
        .opacity(shown)
        .frame(height: fontSize * 1.1 * shown, alignment: .center)
        .padding(.vertical, -fontSize * 0.2 * (1 - shown))
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
