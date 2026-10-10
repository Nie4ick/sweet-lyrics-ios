import AVFoundation
import AVKit
import CoreMedia
import Observation
import QuartzCore
import SwiftUI
import UIKit

/// Floating lyrics over other apps: the lyrics are drawn into video frames and shown in the
/// system's Picture in Picture window, which keeps the app running in the background (the
/// Android port's `PictureInPicture.kt` does the same with Android's PiP).
///
/// Not main-actor isolated because AVKit's delegate protocols aren't; every entry point runs on
/// the main thread and reaches the main-actor player through `MainActor.assumeIsolated`.
@Observable
final class LyricsPictureInPicture: NSObject {
    /// Frame size: 2:1 suits one or two lines of lyrics.
    static let frameSize = CGSize(width: 800, height: 400)

    private(set) var isActive = false
    private(set) var isPossible = false
    private(set) var lastError: String?

    @ObservationIgnored let displayLayer = AVSampleBufferDisplayLayer()
    @ObservationIgnored private var controller: AVPictureInPictureController?
    @ObservationIgnored private var possibleObservation: NSKeyValueObservation?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private weak var player: PlayerModel?
    @ObservationIgnored private var settings: AppSettings?
    @ObservationIgnored private let renderer = PiPFrameRenderer(size: LyricsPictureInPicture.frameSize)
    @ObservationIgnored private var lastPlaying: Bool?

    static var isSupported: Bool { AVPictureInPictureController.isPictureInPictureSupported() }

    override init() {
        super.init()
        displayLayer.videoGravity = .resizeAspect
    }

    /// Connects the player and creates the controller (once the layer is in a window).
    func configure(player: PlayerModel, settings: AppSettings) {
        self.player = player
        self.settings = settings
        guard controller == nil, Self.isSupported else { return }
        let source = AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: displayLayer, playbackDelegate: self)
        let controller = AVPictureInPictureController(contentSource: source)
        controller.delegate = self
        controller.requiresLinearPlayback = false
        controller.canStartPictureInPictureAutomaticallyFromInline = settings.autoPictureInPicture
        possibleObservation = controller.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] controller, _ in
            DispatchQueue.main.async { self?.isPossible = controller.isPictureInPicturePossible }
        }
        self.controller = controller
        // A frame must be on the layer before PiP can start; keep a slow trickle while inactive.
        scheduleFrames(fps: 2)
    }

    func setAutomaticStart(_ enabled: Bool) {
        controller?.canStartPictureInPictureAutomaticallyFromInline = enabled
    }

    func start() {
        lastError = nil
        guard let controller else {
            lastError = "Картинка в картинке не поддерживается на этом устройстве."
            return
        }
        renderFrame()
        if controller.isPictureInPicturePossible {
            controller.startPictureInPicture()
        } else {
            // The first frame may still be on its way; try again a moment later.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                guard let self, let controller = self.controller else { return }
                if controller.isPictureInPicturePossible {
                    controller.startPictureInPicture()
                } else {
                    self.lastError = "Окно «картинка в картинке» сейчас недоступно. Попробуйте ещё раз."
                }
            }
        }
    }

    func stop() {
        controller?.stopPictureInPicture()
    }

    // MARK: Frames

    private func scheduleFrames(fps: Double) {
        timer?.invalidate()
        let timer = Timer(timeInterval: 1 / fps, repeats: true) { [weak self] _ in self?.renderFrame() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func renderFrame() {
        guard let player else { return }
        let output = displayLayer.sampleBufferRenderer
        if output.status == .failed { output.flush() }
        guard output.isReadyForMoreMediaData else { return }
        let snapshot = MainActor.assumeIsolated { PiPSnapshot(player: player, settings: settings) }
        guard let sample = renderer.sampleBuffer(for: snapshot) else { return }
        output.enqueue(sample)

        // Keep the PiP play/pause button in step with Spotify.
        if lastPlaying != snapshot.isPlaying {
            lastPlaying = snapshot.isPlaying
            controller?.invalidatePlaybackState()
        }
    }
}

// MARK: - AVKit delegates

extension LyricsPictureInPicture: AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
        isActive = true
        scheduleFrames(fps: 30)
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        isActive = false
        scheduleFrames(fps: 2)
    }

    func pictureInPictureController(_ controller: AVPictureInPictureController,
                                    failedToStartPictureInPictureWithError error: Error) {
        isActive = false
        lastError = "Не удалось открыть окно: \(error.localizedDescription)"
    }

    func pictureInPictureController(_ controller: AVPictureInPictureController,
                                    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        completionHandler(true)
    }
}

extension LyricsPictureInPicture: AVPictureInPictureSampleBufferPlaybackDelegate {
    func pictureInPictureController(_ controller: AVPictureInPictureController, setPlaying playing: Bool) {
        guard let player else { return }
        MainActor.assumeIsolated {
            if player.isPlaying != playing { player.togglePlay() }
        }
    }

    /// A live stream as far as AVKit is concerned: no scrubber in the window.
    func pictureInPictureControllerTimeRangeForPlayback(_ controller: AVPictureInPictureController) -> CMTimeRange {
        CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
    }

    func pictureInPictureControllerIsPlaybackPaused(_ controller: AVPictureInPictureController) -> Bool {
        guard let player else { return true }
        return MainActor.assumeIsolated { !player.isPlaying }
    }

    func pictureInPictureController(_ controller: AVPictureInPictureController,
                                    didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}

    func pictureInPictureController(_ controller: AVPictureInPictureController, skipByInterval skipInterval: CMTime,
                                    completion completionHandler: @escaping () -> Void) {
        if let player {
            MainActor.assumeIsolated {
                player.seek(to: max(0, player.playbackPosition() + skipInterval.seconds))
            }
        }
        completionHandler()
    }
}

// MARK: - What a frame shows

/// Everything a frame needs, read from the player on the main thread.
struct PiPSnapshot: @unchecked Sendable {
    var title: String
    var artist: String
    var isPlaying: Bool
    var artworkID: String
    var artwork: UIImage?
    /// The current line as (text, brightness 0…1) runs, already timed.
    var current: [(text: String, lit: Double)] = []
    var next: String?
    struct Neighbor {
        var id: String
        var text: String
        var offset: Int
    }
    var neighbors: [Neighbor] = []
    var simple = false
    var interlude = false
    var message: String?
    var fontDesign: UIFontDescriptor.SystemDesign = .default
    /// Includes timing so consecutive identical lines still animate independently.
    var lineID = ""

    @MainActor
    init(player: PlayerModel, settings: AppSettings?) {
        title = player.track?.title ?? "Spicy Lyrics"
        artist = player.track?.artistLine ?? ""
        isPlaying = player.isPlaying
        artworkID = player.artworkID
        artwork = player.backgroundArtwork
        simple = settings?.simpleLyricsMode ?? false
        switch LyricsFont(rawValue: settings?.lyricsFont ?? "") ?? .standard {
        case .standard: fontDesign = .default
        case .rounded: fontDesign = .rounded
        case .serif: fontDesign = .serif
        }

        switch player.lyricsState {
        case .loaded(let lyrics):
            guard lyrics.kind != .static else {
                current = [(lyrics.lines.first?.plainText ?? "", 1)]
                next = lyrics.lines.dropFirst().first?.plainText
                neighbors = lyrics.lines.dropFirst().prefix(2).enumerated().map {
                    Neighbor(id: "static:\($0.offset + 1)", text: $0.element.plainText, offset: $0.offset + 1)
                }
                lineID = "static:0"
                message = "Текст без синхронизации"
                return
            }
            let time = player.position()
            let rows = lyrics.lines.filter { !$0.isBackground }
            guard let index = rows.lastIndex(where: { $0.start <= time }) else {
                interlude = true
                next = rows.first(where: { !$0.isInterlude })?.plainText
                neighbors = rows.enumerated().filter { !$0.element.isInterlude }.prefix(2).enumerated().map {
                    Neighbor(id: "\($0.element.offset):\($0.element.element.start)",
                             text: $0.element.element.plainText, offset: $0.offset + 1)
                }
                return
            }
            let row = rows[index]
            lineID = "\(index):\(row.start)"
            if let previous = rows[..<index].lastIndex(where: { !$0.isInterlude }) {
                neighbors.append(Neighbor(id: "\(previous):\(rows[previous].start)",
                                          text: rows[previous].plainText, offset: -1))
            }
            for (offset, entry) in rows.enumerated().dropFirst(index + 1)
                .filter({ !$0.element.isInterlude }).prefix(2).enumerated() {
                neighbors.append(Neighbor(id: "\(entry.offset):\(entry.element.start)",
                                          text: entry.element.plainText, offset: offset + 1))
            }
            next = rows[(index + 1)...].first(where: { !$0.isInterlude })?.plainText
            switch row.kind {
            case .interlude:
                interlude = time < row.end
                if !interlude { current = [(row.plainText, 1)] }
            case .syllable(let lead, _):
                current = lead.enumerated().flatMap { w, word -> [(text: String, lit: Double)] in
                    let syllables = word.syllables.map { syllable -> (text: String, lit: Double) in
                        let lit: Double
                        if time >= syllable.end { lit = 1 }
                        else if time <= syllable.start { lit = 0 }
                        else { lit = (time - syllable.start) / max(syllable.end - syllable.start, 0.01) }
                        return (syllable.text, lit)
                    }
                    let gap: [(text: String, lit: Double)] = w == 0 ? [] : [(text: " ", lit: 1)]
                    return gap + syllables
                }
            case .line(let text):
                let lit = time >= row.end ? 1 : min(1, max(0, (time - row.start) / max(row.end - row.start, 0.01)))
                current = [(text, 0.3 + 0.7 * lit)]
            case .static(let text):
                current = [(text, 1)]
            }
        case .loading:
            message = "Загрузка текста…"
        case .notFound:
            message = "Текст не найден"
        case .failed, .unavailable:
            message = "Текст недоступен"
        case .idle:
            message = player.statusMessage ?? "Включите музыку в Spotify"
        }
    }
}

// MARK: - Drawing frames

/// Draws snapshots into pixel buffers and wraps them as sample buffers for the PiP layer.
final class PiPFrameRenderer {
    private let size: CGSize
    private var pool: CVPixelBufferPool?
    private var format: CMVideoFormatDescription?
    private var blurredArtwork: (id: String, image: CGImage)?
    private var currentSnapshot: PiPSnapshot?
    private var outgoingSnapshot: PiPSnapshot?
    private var transitionStart: CFTimeInterval = 0

    init(size: CGSize) {
        self.size = size
        let attributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey: Int(size.width),
            kCVPixelBufferHeightKey: Int(size.height),
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ]
        CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool)
    }

    func sampleBuffer(for snapshot: PiPSnapshot) -> CMSampleBuffer? {
        guard let pool else { return nil }
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
        guard let pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        if let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) {
            // UIKit drawing expects a top-left origin.
            context.translateBy(x: 0, y: size.height)
            context.scaleBy(x: 1, y: -1)
            UIGraphicsPushContext(context)
            draw(snapshot, in: CGRect(origin: .zero, size: size), context: context)
            UIGraphicsPopContext()
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

        if format == nil {
            CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pixelBuffer, formatDescriptionOut: &format)
        }
        guard let format else { return nil }
        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
            decodeTimeStamp: .invalid
        )
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: pixelBuffer, formatDescription: format,
                                                 sampleTiming: &timing, sampleBufferOut: &sample)
        if let sample, let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let dictionary = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dictionary,
                                 Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        return sample
    }

    private func draw(_ snapshot: PiPSnapshot, in rect: CGRect, context: CGContext) {
        // Background: the blurred cover (made once per track), darkened for contrast.
        UIColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 1).setFill()
        context.fill(rect)
        if let artwork = snapshot.artwork {
            if blurredArtwork?.id != snapshot.artworkID, let blurred = CoverBlobsView.render(artwork)?.base {
                blurredArtwork = (snapshot.artworkID, blurred)
            }
            if let image = blurredArtwork?.image {
                let side = max(rect.width, rect.height) * 1.2
                UIImage(cgImage: image).draw(in: CGRect(x: (rect.width - side) / 2, y: (rect.height - side) / 2,
                                                        width: side, height: side))
            }
        }
        UIColor.black.withAlphaComponent(0.42).setFill()
        context.fill(rect)

        let inset: CGFloat = 40
        let textWidth = rect.width - inset * 2

        // Footer: track and artist.
        let footer = NSAttributedString(
            string: snapshot.artist.isEmpty ? snapshot.title : "\(snapshot.title) — \(snapshot.artist)",
            attributes: [.font: font(20, .semibold, snapshot.fontDesign), .foregroundColor: UIColor.white.withAlphaComponent(0.55)]
        )
        footer.draw(with: CGRect(x: inset, y: rect.height - 46, width: textWidth, height: 28),
                    options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)

        let now = CACurrentMediaTime()
        if let previous = currentSnapshot,
           previous.artworkID == snapshot.artworkID,
           (previous.lineID != snapshot.lineID || previous.message != snapshot.message ||
            previous.interlude != snapshot.interlude ||
            previous.current.map(\.text) != snapshot.current.map(\.text)) {
            outgoingSnapshot = previous
            transitionStart = now
        } else if currentSnapshot?.artworkID != snapshot.artworkID {
            outgoingSnapshot = nil
        }
        currentSnapshot = snapshot
        let progress = UIAccessibility.isReduceMotionEnabled ? 1 : min(1, max(0, (now - transitionStart) / 0.42))
        let eased = CGFloat(1 - pow(1 - progress, 3))
        context.saveGState()
        context.clip(to: CGRect(x: inset - 8, y: 24, width: textWidth + 16, height: rect.height - 88))
        drawLyrics(snapshot, from: outgoingSnapshot, progress: eased, in: rect, context: context)
        context.restoreGState()
        if progress >= 1 { outgoingSnapshot = nil }
    }

    private func drawLyrics(_ snapshot: PiPSnapshot, from previous: PiPSnapshot?, progress: CGFloat,
                            in rect: CGRect, context: CGContext) {
        let inset: CGFloat = 40
        let width = rect.width - inset * 2
        if let message = snapshot.message, snapshot.current.isEmpty, !snapshot.interlude {
            NSAttributedString(string: message, attributes: [
                .font: font(36, .bold, snapshot.fontDesign),
                .foregroundColor: UIColor.white.withAlphaComponent(0.85),
            ]).draw(with: CGRect(x: inset, y: 116, width: width, height: 110),
                    options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
            return
        }

        // Match rows by lyric identity: the upcoming row moves into the active slot,
        // and the active row moves above it instead of replacing the entire frame.
        struct Row {
            var id: String
            var text: String
            var offset: Int
        }
        func rows(_ value: PiPSnapshot) -> [Row] {
            [Row(id: value.lineID, text: value.interlude ? "•  •  •" : value.current.map(\.text).joined(), offset: 0)] +
                value.neighbors.map { Row(id: $0.id, text: $0.text, offset: $0.offset) }
        }
        func y(_ offset: Int) -> CGFloat {
            switch offset {
            case ..<0: return 34
            case 0: return 104
            case 1: return 232
            default: return 286
            }
        }
        func emphasis(_ offset: Int) -> CGFloat { offset == 0 ? 1 : 0 }
        let targetRows = rows(snapshot)
        let oldRows = previous.map(rows) ?? targetRows
        let oldByID = Dictionary(oldRows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let targetIDs = Set(targetRows.map(\.id))
        let allRows = targetRows + oldRows.filter { !targetIDs.contains($0.id) }
        for row in allRows where !row.text.isEmpty {
            let old = oldByID[row.id]
            let exists = targetIDs.contains(row.id)
            let startY = old.map { y($0.offset) } ?? (y(row.offset) + 44)
            let endY = exists ? y(row.offset) : -50
            let rowY = startY + (endY - startY) * progress
            let startEmphasis = old.map { emphasis($0.offset) } ?? 0
            let endEmphasis = exists ? emphasis(row.offset) : 0
            let active = startEmphasis + (endEmphasis - startEmphasis) * progress
            let alpha: CGFloat = exists ? (old == nil ? progress : 1) : 1 - progress
            context.saveGState()
            context.setAlpha(alpha)
            let textFont = font(32 + 12 * active, active > 0.5 ? .bold : .semibold, snapshot.fontDesign)
            let box = CGRect(x: inset, y: rowY, width: width, height: 48 + 68 * active)
            if row.offset == 0, exists, !snapshot.interlude {
                drawSyllables(snapshot, font: textFont, in: box, context: context)
            } else {
                let opacity: CGFloat = 0.28 + 0.65 * active
                NSAttributedString(string: row.text, attributes: [
                    .font: textFont, .foregroundColor: UIColor.white.withAlphaComponent(opacity),
                ]).draw(with: box, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
            }
            context.restoreGState()
        }
    }

    private func drawSyllables(_ snapshot: PiPSnapshot, font textFont: UIFont,
                               in box: CGRect, context: CGContext) {
        // TextKit keeps wrapping and glyph positions stable while each timed run lifts,
        // glows, and fills from left to right (rather than changing the whole word's alpha).
        let text = NSMutableAttributedString()
        var runs: [(range: NSRange, progress: Double)] = []
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        for run in snapshot.current {
            let pulse = reduceMotion ? 0 : sin(.pi * min(1, max(0, run.lit)))
            let range = NSRange(location: text.length, length: (run.text as NSString).length)
            text.append(NSAttributedString(string: run.text, attributes: [
                .font: textFont,
                .foregroundColor: UIColor.white.withAlphaComponent(0.32),
                .baselineOffset: pulse * (snapshot.simple ? 2 : 4),
            ]))
            runs.append((range, run.lit))
        }
        let storage = NSTextStorage(attributedString: text)
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: box.size)
        container.lineFragmentPadding = 0
        container.maximumNumberOfLines = 2
        container.lineBreakMode = .byTruncatingTail
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        let glyphs = layout.glyphRange(for: container)
        layout.drawGlyphs(forGlyphRange: glyphs, at: box.origin)
        for run in runs where run.progress > 0 && run.range.length > 0 {
            let range = layout.glyphRange(forCharacterRange: run.range, actualCharacterRange: nil)
            storage.addAttribute(.foregroundColor, value: UIColor.white, range: run.range)
            // A run may span a wrap: reveal its visible fragments in reading order.
            var fragments: [CGRect] = []
            layout.enumerateEnclosingRects(forGlyphRange: range, withinSelectedGlyphRange: range,
                                            in: container) { fragment, _ in fragments.append(fragment) }
            let totalWidth = fragments.reduce(CGFloat.zero) { $0 + $1.width }
            var remaining = totalWidth * CGFloat(min(1, run.progress))
            context.saveGState()
            context.beginPath()
            for fragment in fragments {
                let revealed = min(fragment.width, max(0, remaining))
                context.addRect(CGRect(x: box.minX + fragment.minX, y: box.minY + fragment.minY - 6,
                                       width: revealed, height: fragment.height + 12))
                remaining -= fragment.width
            }
            context.clip()
            if !reduceMotion && !snapshot.simple {
                let glow = sin(.pi * min(1, run.progress))
                context.setShadow(offset: .zero, blur: 7 * glow,
                                  color: UIColor.white.withAlphaComponent(0.45 * glow).cgColor)
            }
            layout.drawGlyphs(forGlyphRange: range, at: box.origin)
            context.restoreGState()
            storage.addAttribute(.foregroundColor, value: UIColor.white.withAlphaComponent(0.32), range: run.range)
        }
    }

    private func font(_ size: CGFloat, _ weight: UIFont.Weight, _ design: UIFontDescriptor.SystemDesign) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(design) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }
}

// MARK: - Hosting the layer

/// Puts the PiP layer into the window (AVKit needs it there); tucked behind the background.
struct PictureInPictureHost: UIViewRepresentable {
    let pip: LyricsPictureInPicture

    func makeUIView(context: Context) -> HostView {
        let view = HostView()
        view.isUserInteractionEnabled = false
        view.layer.addSublayer(pip.displayLayer)
        return view
    }

    func updateUIView(_ view: HostView, context: Context) {}

    final class HostView: UIView {
        override func layoutSubviews() {
            super.layoutSubviews()
            layer.sublayers?.forEach { $0.frame = bounds }
        }
    }
}
