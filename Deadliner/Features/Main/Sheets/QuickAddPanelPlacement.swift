import Foundation
import CoreGraphics

/// The bottom boundary is measured inside the page, above native bars/accessories and the keyboard.
struct QuickAddPanelPlacement {
    let region: CGRect

    init(size: CGSize, bottomBoundary: CGFloat?, horizontalInset: CGFloat = 16, dockClearance: CGFloat = 26) {
        let horizontalInset = min(horizontalInset, max(0, size.width / 2))
        let bottom = min(size.height, max(0, bottomBoundary ?? size.height))
        let top: CGFloat = min(8, max(0, bottom - dockClearance))
        region = CGRect(x: horizontalInset, y: top,
                        width: max(0, size.width - horizontalInset * 2),
                        height: max(0, bottom - dockClearance - top))
    }
}
