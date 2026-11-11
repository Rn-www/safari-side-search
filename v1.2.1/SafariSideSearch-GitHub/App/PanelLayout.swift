import Foundation
import CoreGraphics

enum PanelLayout {
    static let defaultWidth: CGFloat = 430
    static let minimumWidth: CGFloat = 340
    static let maximumWidth: CGFloat = 720

    /// All inputs and output use AppKit's bottom-left screen coordinates.
    static func frame(safari: CGRect, visibleScreen: CGRect, width: CGFloat) -> CGRect {
        let available = safari.intersection(visibleScreen)
        guard !available.isNull, available.width > 80, available.height > 100 else {
            return fallback(screen: visibleScreen, width: width)
        }
        let gap: CGFloat = 8
        let panelWidth = min(max(width, minimumWidth), maximumWidth, max(80, available.width - 16))
        let topInset: CGFloat = min(88, max(16, available.height * 0.14))
        let height = max(80, available.height - topInset - gap)
        return CGRect(x: available.maxX - panelWidth - gap, y: available.minY + gap,
                      width: panelWidth, height: height)
    }

    static func fallback(screen: CGRect, width: CGFloat) -> CGRect {
        let actualWidth = min(max(width, minimumWidth), maximumWidth, max(80, screen.width - 24))
        return CGRect(x: screen.maxX - actualWidth - 12, y: screen.minY + 12,
                      width: actualWidth, height: max(80, screen.height - 24))
    }
}
