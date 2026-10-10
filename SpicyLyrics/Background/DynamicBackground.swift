import SwiftUI
import UIKit

/// Animated, blurred cover art behind the lyrics.
struct DynamicBackground: View {
    let image: UIImage?
    let imageID: String
    let animated: Bool

    var body: some View {
        ZStack {
            Color(red: 0.07, green: 0.07, blue: 0.08)
            if let image {
                CoverLayers(image: image, animated: animated)
                    .id(imageID)
                    .transition(.opacity)
            }
            // Keeps white lyrics readable on bright covers.
            Color.black.opacity(0.28)
        }
        .animation(.easeInOut(duration: 1.0), value: imageID)
        .ignoresSafeArea()
    }
}

private struct CoverLayers: View {
    let image: UIImage
    let animated: Bool

    var body: some View {
        GeometryReader { geometry in
            if animated {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600)
                    layers(size: geometry.size, time: t)
                        .distortionEffect(
                            ShaderLibrary.kawarpWarp(.float2(geometry.size), .float(Float(t * 0.25)), .float(1)),
                            maxSampleOffset: CGSize(width: 90, height: 90)
                        )
                        .blur(radius: 45, opaque: true)
                        .saturation(1.5)
                        .brightness(-0.12)
                }
            } else {
                layers(size: geometry.size, time: 0)
                    .blur(radius: 55, opaque: true)
                    .saturation(1.4)
                    .brightness(-0.12)
            }
        }
    }

    private func layers(size: CGSize, time t: Double) -> some View {
        let side = max(size.width, size.height) * 1.25
        return ZStack {
            Image(uiImage: image)
                .resizable()
                .frame(width: side * 1.4, height: side * 1.4)
                .rotationEffect(.radians(t * 0.045))
                .position(x: size.width * 0.5, y: size.height * 0.5)
            Image(uiImage: image)
                .resizable()
                .frame(width: side * 0.85, height: side * 0.85)
                .rotationEffect(.radians(-t * 0.07 + 1.3))
                .position(x: size.width * (0.25 + 0.08 * sin(t * 0.11)), y: size.height * (0.25 + 0.06 * cos(t * 0.09)))
            Image(uiImage: image)
                .resizable()
                .frame(width: side * 0.7, height: side * 0.7)
                .rotationEffect(.radians(t * 0.09 + 2.6))
                .position(x: size.width * (0.78 + 0.07 * cos(t * 0.13)), y: size.height * (0.72 + 0.07 * sin(t * 0.1)))
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }
}

extension UIImage {
    /// A small copy for the background: blurring 160 px is far cheaper than blurring 640 px.
    func downscaled(to maxSide: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxSide else { return self }
        let scale = maxSide / longest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
