import SwiftUI
import Shared

struct OverviewFocusManagement: View {
    @ObservedObject var model: OverviewViewModel
    private let timer = FocusTimerPresentationModel.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var phase
    @State private var route: FocusManagementRoute?
    @State private var expanded = false
    @State private var category = false
    @State private var showAll = false
    @State private var limit: Int32 = 50

    var body: some View {
        List {
            if model.managementLoading && model.focusManagement == nil { ProgressView().frame(maxWidth: .infinity) }
            if let error = model.managementError {
                OverviewFailureView(message: model.focusManagement == nil ? error : "更新失败，显示上次结果", retry: model.reloadFocusManagement)
            }
            if let data = model.focusManagement {
                Section("专注概况") {
                    FocusManagementDashboard(data: data)
                }
                Section("近 7 天") {
                    FocusDurationChart(title: "近 7 天专注", points: data.recentSevenDays.daily, summary: data.recentSevenDays.summary)
                }
                Section {
                    FocusManagementAllocationPreview(statistics: data.allTime)
                    DisclosureGroup("时间投入", isExpanded: $expanded) {
                        Picker("分配方式", selection: $category) { Text("按目标").tag(false); Text("按分类").tag(true) }
                            .pickerStyle(.segmented)
                        FocusManagementDistribution(statistics: data.allTime, category: category, showAll: showAll) { route = .history($0) }
                        if (category ? data.allTime.categories.count : data.allTime.targets.count) > 5 {
                            Button(showAll ? "收起" : "查看全部") { showAll.toggle() }
                        }
                    }
                }
                FocusManagementHistory(data: data, target: nil, limit: $limit) { route = .record($0) }
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: expanded)
        .deadlinerScrollEdgeEffect()
        .navigationTitle("专注管理")
        .navigationSubtitle("开始专注 · 看板 · 历史")
        .refreshable { model.reloadFocusManagement() }
        .safeAreaInset(edge: .bottom) {
            FocusManagementActionBar { route = timer.state?.timer == nil ? .choose : .timer(nil) }
        }
        .sheet(item: $route, onDismiss: { model.reloadFocusManagement() }) { destination in
            switch destination {
            case .choose:
                FocusTimerView(startNew: true)
            case .timer(let option):
                FocusTimerView(taskUID: option?.target.kind == .task ? option?.target.uid ?? "" : "",
                    taskTitle: option?.title ?? "", habitUID: option?.target.kind == .habit ? option?.target.uid ?? "" : "")
            case .record(let uid): FocusManagementDetailSheet(model: model, uid: uid)
            case .history(let target): FocusManagementTargetHistory(model: model, target: target)
            }
        }
        .task { await timer.connect(); model.reloadFocusManagement() }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in model.reloadFocusManagement() }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.NSSystemTimeZoneDidChange)) { _ in model.reloadFocusManagement() }
        .onChange(of: phase) { _, next in if next == .active { model.reloadFocusManagement() } }
    }
}

private enum FocusManagementRoute: Identifiable {
    case choose, timer(FocusStartTargetOption?), record(String), history(FocusTargetRef)
    var id: String {
        switch self {
        case .choose: "choose"
        case .timer(let target): "timer-" + (target?.target.uid ?? "active")
        case .record(let uid): "record-" + uid
        case .history(let target): "history-\(target.kind)-\(target.uid)"
        }
    }
}
