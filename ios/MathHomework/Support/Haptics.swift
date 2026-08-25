import UIKit

/// Small haptic vocabulary: a tap when a page is captured, success when a page
/// finishes grading, and an error buzz when OCR fails.
enum Haptics {
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    static func tap() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}
