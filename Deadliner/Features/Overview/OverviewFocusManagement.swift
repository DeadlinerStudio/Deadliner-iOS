import SwiftUI
import Shared

struct OverviewFocusManagement: View {
    @ObservedObject var model: OverviewViewModel
    @State private var editing: FocusSession?
    @State private var deleting: FocusSession?
    var body: some View {
        List {
            if model.managementLoading { ProgressView().frame(maxWidth: .infinity) }
            if let error = model.managementError { OverviewFailureView(message: error, retry: model.loadData) }
            Section("专注概况") {
                if let error = model.focusError { OverviewFailureView(message: error, retry: model.loadData) }
                else if let today = model.focus?.today {
                    summary("今天", seconds: today.totalDurationSeconds, count: Int(today.sessionCount))
                }
                if let stats = model.focusManagementStatistics {
                    summary("累计", seconds: stats.summary.totalDurationSeconds, count: Int(stats.summary.sessionCount))
                    if let split = stats.summary.durationByTarget {
                        LabeledContent("任务", value: FocusTimerFormatting.duration(split.taskDurationSeconds))
                        LabeledContent("习惯", value: FocusTimerFormatting.duration(split.habitDurationSeconds))
                    }
                }
            }
            if let stats = model.focusManagementStatistics {
                Section("目标分配") {
                    if stats.targets.isEmpty { Text("暂无目标分配").foregroundStyle(.secondary) }
                    ForEach(Array(stats.targets.enumerated()), id: \.offset) { _, target in
                        distribution(target.title, seconds: target.durationSeconds, total: stats.summary.totalDurationSeconds)
                    }
                }
                Section("分类分配") {
                    if stats.categories.isEmpty { Text("暂无分类分配").foregroundStyle(.secondary) }
                    ForEach(Array(stats.categories.enumerated()), id: \.offset) { _, category in
                        distribution(category.categoryTitle ?? "未分类", seconds: category.durationSeconds, total: stats.summary.totalDurationSeconds)
                    }
                }
            }
            Section("全部已保存记录 · \(model.focusSessions.count) 条") {
                if !model.managementLoading && model.managementError == nil && model.focusSessions.isEmpty {
                    ContentUnavailableView("暂无专注记录", systemImage: "timer", description: Text("结束并保存专注后，记录会显示在这里。"))
                }
                ForEach(model.focusSessions, id: \.uid) { session in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(session.taskTitleSnapshot).font(.headline)
                        Text(startLabel(session.startedAt)).font(.caption).foregroundStyle(.secondary)
                        Text(FocusTimerFormatting.duration(session.durationSeconds)).font(.subheadline).monospacedDigit()
                        if let day = session.habitOccurredOn { Text("习惯日期 · \(day)").font(.caption).foregroundStyle(.secondary) }
                        HStack {
                            Button("更正时长") { editing = session }.disabled(Self.maximum(session) < 1)
                            Spacer()
                            Button("删除", role: .destructive) { deleting = session }
                        }.font(.subheadline).buttonStyle(.borderless)
                    }.padding(.vertical, 6)
                    .swipeActions { Button("删除", role: .destructive) { deleting = session } }
                }
            }
        }
        .deadlinerScrollEdgeEffect()
        .navigationTitle("专注管理").navigationSubtitle("全部已保存记录")
        .sheet(isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            if let editing { FocusSessionMutationSheet(model: model, session: editing, deleting: false) }
        }
        .sheet(isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            if let deleting { FocusSessionMutationSheet(model: model, session: deleting, deleting: true) }
        }
    }
    static func maximum(_ session: FocusSession) -> Int64 {
        guard let start = DeadlineDateParser.safeParseOptional(session.startedAt), let end = DeadlineDateParser.safeParseOptional(session.endedAt) else { return 0 }
        return max(0, min(session.durationSeconds, Int64(end.timeIntervalSince(start)), 86_400))
    }
    private func summary(_ title: String, seconds: Int64, count: Int) -> some View {
        LabeledContent(title) { VStack(alignment: .trailing) { Text(FocusTimerFormatting.duration(seconds)); Text("\(count) 次").font(.caption).foregroundStyle(.secondary) } }
    }
    private func distribution(_ title: String, seconds: Int64, total: Int64) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent(title, value: FocusTimerFormatting.duration(seconds))
            ProgressView(value: Double(seconds), total: Double(max(total, 1))).tint(.blue)
        }.padding(.vertical, 4)
    }
    private func startLabel(_ value: String) -> String {
        DeadlineDateParser.safeParseOptional(value)?.formatted(date: .abbreviated, time: .shortened) ?? value
    }
}

private struct FocusSessionMutationSheet: View {
    @ObservedObject var model: OverviewViewModel
    let session: FocusSession
    let deleting: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var seconds = ""
    @State private var error: String?
    @State private var busy = false
    private var maximum: Int64 { OverviewFocusManagement.maximum(session) }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(session.taskTitleSnapshot)
                    Text("原时长 · " + FocusTimerFormatting.duration(session.durationSeconds)).foregroundStyle(.secondary)
                    if deleting { Text("删除后该记录会从统计中移除，不会撤销习惯打卡。") }
                    else {
                        TextField("时长（秒）", text: $seconds).keyboardType(.numberPad)
                        Text("只允许调低，可输入 1–\(maximum) 秒").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                Section {
                    Button(deleting ? "确认删除" : "保存更正", role: deleting ? .destructive : nil) { apply() }
                        .disabled(busy || !deleting && (Int64(seconds).map { $0 < 1 || $0 > maximum } ?? true))
                    if busy { ProgressView() }
                }
            }
            .navigationTitle(deleting ? "删除专注记录" : "更正专注时长").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(busy) } }
        }
        .interactiveDismissDisabled(busy)
        .onAppear { if seconds.isEmpty { seconds = "\(maximum)" } }
    }
    private func apply() {
        busy = true; error = nil
        model.mutateFocusSession(uid: session.uid, seconds: deleting ? nil : Int64(seconds)) { message in
            busy = false
            if let message { error = message } else { dismiss() }
        }
    }
}
