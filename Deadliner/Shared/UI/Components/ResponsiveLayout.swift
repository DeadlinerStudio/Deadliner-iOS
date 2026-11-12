import SwiftUI

/// Matches HarmonyOS AppBreakpoints, using the available window width in points.
enum AppLayoutBreakpoint: Equatable {
    case small, medium, large, extraLarge

    init(width: CGFloat) {
        switch width {
        case 1320...: self = .extraLarge
        case 840...: self = .large
        case 600...: self = .medium
        default: self = .small
        }
    }

    var isWide: Bool { self == .large || self == .extraLarge }
    var captureColumns: Int { self == .small ? 1 : (self == .extraLarge ? 3 : 2) }

    func captureComposerWidth(availableWidth: CGFloat) -> CGFloat {
        let isExtraLarge = self == .extraLarge
        return min(max(availableWidth * (isExtraLarge ? 0.28 : 0.34), isExtraLarge ? 340 : 320), isExtraLarge ? 460 : 420)
    }
}
