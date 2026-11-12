#if DEBUG
import SwiftUI

private struct QuickAddPanelPreview: View {
    @State private var input = "明天下午3点交报告，附上实验数据"
    @FocusState private var focused: Bool

    var body: some View {
        GeometryReader { geometry in
            let placement = QuickAddPanelPlacement(
                size: geometry.size, bottomBoundary: nil,
                horizontalInset: FloatingComposerStyle.horizontalInset,
                dockClearance: FloatingComposerStyle.dockClearance)
            QuickAddGlassPanel(
                input: $input,
                draft: QuickAddDraft(kind: "TASK", title: "交报告", dueAt: "2026-10-18 15:00:00",
                                     note: "附上实验数据", ready: true, source: "MODEL"),
                modelStatus: QuickAddModelDownloadStatus(phase: "READY"),
                loading: false, saving: false, recognizingAI: false, message: "", canSave: true,
                categoryName: "学习", availableHeight: placement.region.height,
                inputFocused: $focused, onClose: {}, onExpand: {}, onCategory: {},
                onAttribute: { _ in }, onAI: {}, onSave: {}, onRetry: {})
                .frame(maxWidth: min(520, placement.region.width))
                .frame(width: placement.region.width, height: placement.region.height, alignment: .bottomTrailing)
                .offset(x: placement.region.minX, y: placement.region.minY)
        }
        .background {
            LinearGradient(colors: [.blue.opacity(0.18), .purple.opacity(0.12), .orange.opacity(0.12)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

#Preview("窄屏 · 键盘上方", traits: .fixedLayout(width: 320, height: 300)) {
    QuickAddPanelPreview()
}

#Preview("横屏 · 极短窗口", traits: .fixedLayout(width: 700, height: 180)) {
    QuickAddPanelPreview()
}

#Preview("iPad · 大字号", traits: .fixedLayout(width: 1024, height: 700)) {
    QuickAddPanelPreview().environment(\.dynamicTypeSize, .accessibility3)
}
#endif
