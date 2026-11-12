import SwiftUI

/// Shared by the AI composer and quick capture so material and dock clearance stay identical.
enum FloatingComposerStyle {
    static let cornerRadius: CGFloat = 28
    static let horizontalInset: CGFloat = 16
    static let topInset: CGFloat = 8
    static let bottomInset: CGFloat = 10
    static let tabAccessoryInset: CGFloat = 16
    static let dockClearance = bottomInset + tabAccessoryInset
}

extension View {
    func floatingComposerGlass() -> some View {
        glassEffect(.regular.interactive(), in: RoundedRectangle(
            cornerRadius: FloatingComposerStyle.cornerRadius, style: .continuous))
    }
}

/// Install at the same safe-area inset used by the AI composer, inside the navigation/tab content.
struct ComposerBottomBoundary: View {
    let onChange: (CGFloat) -> Void

    var body: some View {
        Color.clear
            .frame(height: 0)
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { onChange($0) }
            .accessibilityHidden(true)
    }
}
