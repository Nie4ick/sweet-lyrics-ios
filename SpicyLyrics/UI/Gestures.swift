import SwiftUI
import UIKit

/// UIKit swipe and pinch recognizers that run alongside the lyrics' scroll view: SwiftUI drag
/// gestures attached to a ScrollView fight its scrolling, recognizers don't. iOS 18+.
@available(iOS 18.0, *)
private struct SwipeRecognizer: UIGestureRecognizerRepresentable {
    let direction: UISwipeGestureRecognizer.Direction
    let action: () -> Void

    func makeUIGestureRecognizer(context: Context) -> UISwipeGestureRecognizer {
        let recognizer = UISwipeGestureRecognizer()
        recognizer.direction = direction
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UISwipeGestureRecognizer, context: Context) {
        if recognizer.state == .ended { action() }
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> SimultaneousDelegate { SimultaneousDelegate() }
}

@available(iOS 18.0, *)
private struct PinchRecognizer: UIGestureRecognizerRepresentable {
    let onChange: (CGFloat) -> Void
    let onEnd: (CGFloat) -> Void

    func makeUIGestureRecognizer(context: Context) -> UIPinchGestureRecognizer {
        let recognizer = UIPinchGestureRecognizer()
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPinchGestureRecognizer, context: Context) {
        switch recognizer.state {
        case .changed: onChange(recognizer.scale)
        case .ended: onEnd(recognizer.scale)
        case .cancelled, .failed: onEnd(1)
        default: break
        }
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> SimultaneousDelegate { SimultaneousDelegate() }
}

final class SimultaneousDelegate: NSObject, UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}

extension View {
    /// Horizontal swipes: left = next, right = previous.
    @ViewBuilder
    func trackSwipes(enabled: Bool, onNext: @escaping () -> Void, onPrevious: @escaping () -> Void) -> some View {
        if #available(iOS 18.0, *), enabled {
            self
                .gesture(SwipeRecognizer(direction: .left, action: onNext))
                .gesture(SwipeRecognizer(direction: .right, action: onPrevious))
        } else {
            self
        }
    }

    /// Vertical swipe (no-op before iOS 18).
    @ViewBuilder
    func verticalSwipe(_ direction: UISwipeGestureRecognizer.Direction, action: @escaping () -> Void) -> some View {
        if #available(iOS 18.0, *) {
            self.gesture(SwipeRecognizer(direction: direction, action: action))
        } else {
            self
        }
    }

    /// Two-finger pinch reporting the live scale and the final one.
    @ViewBuilder
    func pinch(enabled: Bool, onChange: @escaping (CGFloat) -> Void, onEnd: @escaping (CGFloat) -> Void) -> some View {
        if #available(iOS 18.0, *), enabled {
            self.gesture(PinchRecognizer(onChange: onChange, onEnd: onEnd))
        } else {
            self
        }
    }
}
