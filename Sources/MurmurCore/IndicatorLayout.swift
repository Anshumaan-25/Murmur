import Foundation
import CoreGraphics

public enum IndicatorLayout {
    /// Anchors are fractions of the available travel, independent of display origin/scale.
    public static func frame(in visible: CGRect, size: CGSize, anchor: CGPoint = CGPoint(x: 1, y: 1)) -> CGRect {
        let margin = min(12, max(0, min(visible.width, visible.height) / 8))
        let area = visible.insetBy(dx: margin, dy: margin)
        let width = min(size.width, max(0, area.width)), height = min(size.height, max(0, area.height))
        func fraction(_ value: CGFloat) -> CGFloat { value.isFinite ? min(1, max(0, value)) : 0.5 }
        return CGRect(x: area.minX + (area.width - width) * fraction(anchor.x),
                      y: area.minY + (area.height - height) * fraction(anchor.y), width: width, height: height)
    }
}
