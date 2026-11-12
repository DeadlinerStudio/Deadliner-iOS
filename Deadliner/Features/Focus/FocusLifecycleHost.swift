#if canImport(Shared)
import SwiftUI

private struct FocusLifecycleHost: ViewModifier {
    @ObservedObject private var model = FocusTimerPresentationModel.shared
    func body(content: Content) -> some View {
        content
            .task { await model.connect() }
            .sheet(isPresented: $model.openRequested, onDismiss: { model.clearNotificationRoute() }) { FocusTimerView() }
            .confirmationDialog("结束计时并" + (model.pendingChange?.operation ?? "处理目标") + "？",
                isPresented: Binding(get: { model.pendingChange != nil }, set: { if !$0 { model.cancelTargetChange() } }), titleVisibility: .visible) {
                    Button("结束计时并" + (model.pendingChange?.operation ?? "确认"), role: model.pendingChange?.delete == true ? .destructive : nil) { model.applyTargetChange() }
                    Button("取消", role: .cancel) { model.cancelTargetChange() }
                } message: { Text("将保存本轮有效专注时间，再执行原操作。不会自动为习惯打卡；不足一秒不生成记录。") }
    }
}
extension View {
    func focusLifecycleHost() -> some View { modifier(FocusLifecycleHost()) }
}
#endif
