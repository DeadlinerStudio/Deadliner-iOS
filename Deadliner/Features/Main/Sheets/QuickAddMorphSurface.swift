import SwiftUI

struct QuickAddMorphSource {
    let frame: CGRect
    let tint: Color
}

/// One continuously sized glass surface. The destination layout stays fixed while
/// its shell grows from the measured native button, so text is never stretched.
struct QuickAddMorphSurface: ViewModifier {
    let source: QuickAddMorphSource?
    let progress: CGFloat

    func body(content: Content) -> some View {
        if let source {
            content.hidden().overlay {
                GeometryReader { geometry in
                    let destination = geometry.frame(in: .global)
                    let start = source.frame.offsetBy(dx: -destination.minX, dy: -destination.minY)
                    let width = start.width + (geometry.size.width - start.width) * progress
                    let height = start.height + (geometry.size.height - start.height) * progress
                    let radius = start.height / 2 + (FloatingComposerStyle.cornerRadius - start.height / 2) * progress
                    content
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .opacity(max(0, (progress - 0.55) / 0.45))
                        .frame(width: max(0, width), height: max(0, height))
                        .clipped()
                        .glassEffect(.regular.tint(source.tint.opacity(1 - progress)).interactive(),
                                     in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                        .overlay {
                            Image(systemName: "plus")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundStyle(.white)
                                .opacity(max(0, 1 - progress * 4))
                        }
                        .position(x: start.midX + (geometry.size.width / 2 - start.midX) * progress,
                                  y: start.midY + (geometry.size.height / 2 - start.midY) * progress)
                }
            }
        } else {
            content.floatingComposerGlass()
        }
    }
}
