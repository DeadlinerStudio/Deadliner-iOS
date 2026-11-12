import SwiftUI
import Shared

struct FocusManagementSummary: View {
    let title: String
    let summary: FocusStatisticsSummary
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Text(FocusTimerFormatting.duration(summary.totalDurationSeconds)).font(.title2.weight(.semibold)).monospacedDigit().lineLimit(2).minimumScaleFactor(0.8)
            Text("\(summary.sessionCount) 次").font(.caption).foregroundStyle(.secondary)
            if let split = summary.durationByTarget {
                Text("任务 \(FocusTimerFormatting.duration(split.taskDurationSeconds)) · 习惯 \(FocusTimerFormatting.duration(split.habitDurationSeconds))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 6)
    }
}

struct FocusManagementDistribution: View {
    let statistics: FocusStatisticsSnapshot
    let category: Bool
    let showAll: Bool
    let onTarget: (FocusTargetRef) -> Void
    var body: some View {
        if category {
            ForEach(Array(statistics.categories.prefix(showAll ? statistics.categories.count : 5)), id: \.categoryUid) { item in
                entry(item.categoryTitle ?? "未分类", seconds: item.durationSeconds, count: item.sessionCount)
            }
        } else {
            ForEach(Array(statistics.targets.prefix(showAll ? statistics.targets.count : 5)), id: \.target) { item in
                Button { onTarget(item.target) } label: {
                    entry((item.target.kind == .habit ? "习惯 · " : "任务 · ") + item.title, seconds: item.durationSeconds, count: item.sessionCount)
                }.buttonStyle(.plain)
            }
        }
        if statistics.summary.sessionCount == 0 { Text("暂无分配数据").foregroundStyle(.secondary) }
    }
    private func entry(_ title: String, seconds: Int64, count: Int32) -> some View {
        let ratio = Double(seconds) / Double(max(1, statistics.summary.totalDurationSeconds))
        return VStack(alignment: .leading, spacing: 6) {
            LabeledContent(title, value: FocusTimerFormatting.duration(seconds))
            Text(String(format: "%.1f%% · %d 次", ratio * 100, count)).font(.caption).foregroundStyle(.secondary)
            ProgressView(value: ratio).tint(.accentColor)
        }.padding(.vertical, 6)
    }
}

struct FocusManagementHistory: View {
    let data: FocusManagementSnapshot
    let target: FocusTargetRef?
    @Binding var limit: Int32
    let onRecord: (String) -> Void
    @State private var width: CGFloat = 350
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        let page = data.historyPage(limit: limit, target: target)
        Section(target == nil ? "全部已保存记录 · \(page.totalCount) 条" : "目标记录 · \(page.totalCount) 条") {
            if page.totalCount == 0 {
                ContentUnavailableView("暂无专注记录", systemImage: "timer", description: Text("从底部开始专注，结束保存后会出现在这里。"))
            }
        }
        ForEach(page.days, id: \.date) { day in
            Section {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .topLeading), count: width >= 700 && typeSize < .xxxLarge ? 2 : 1), alignment: .leading, spacing: 12) {
                    ForEach(day.records, id: \.session.uid) { record in
                        Button { onRecord(record.session.uid) } label: { FocusManagementRecordLabel(record: record) }.buttonStyle(.plain)
                    }
                }.onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            } header: {
                HStack { Text(day.date); Spacer(); Text("\(FocusTimerFormatting.duration(day.durationSeconds)) · \(day.sessionCount) 次") }
            }
        }
        if page.hasMore {
            Section { Button("加载更多") { limit = min(Int32.max - 50, limit) + 50 }.onAppear { limit = min(Int32.max - 50, limit) + 50 } }
        }
    }
}

struct FocusManagementRecordLabel: View {
    let record: FocusManagementRecord
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text(record.title).font(.headline).lineLimit(2)
                Text((record.session.boundTarget.kind == .habit ? "习惯" : "任务") + " · " + FocusTimerFormatting.historyDate(record.session.startedAt))
                    .font(.caption).foregroundStyle(.secondary)
                Text((record.session.mode == .countdown ? "倒计时" : "正计时") + " · " + focusManagementStatus(record.targetStatus))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(FocusTimerFormatting.duration(record.session.durationSeconds)).monospacedDigit()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }.padding(.vertical, 6).contentShape(Rectangle())
    }
}

func focusManagementStatus(_ status: FocusManagedTargetStatus) -> String {
    switch status {
    case .active: "进行中"
    case .completed: "已完成"
    case .archived: "已归档"
    case .abandoned: "已放弃"
    default: "目标已删除"
    }
}


/// Timer ticks redraw only the action region, never the complete management history.
struct FocusManagementActionBar: View {
    @ObservedObject private var timer = FocusTimerPresentationModel.shared
    let onOpen: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            Spacer()
            if let current = timer.state?.timer {
                Button(action: onOpen) {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(current.taskTitle).font(.subheadline.weight(.medium)).lineLimit(1)
                        Text((current.state == .paused ? "已暂停" : "专注中") + " · " + FocusTimerFormatting.clock(current.elapsedSeconds))
                            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    }.frame(maxWidth: 210)
                }.buttonStyle(.plain)
            }
            Button(action: onOpen) {
                ZStack {
                    Image(systemName: "timer").font(.system(size: 24, weight: .semibold))
                    if let current = timer.state?.timer {
                        Image(systemName: current.state == .paused ? "pause.fill" : "play.fill")
                            .font(.system(size: 9, weight: .bold)).padding(3)
                            .background(Color.accentColor, in: Circle()).offset(x: 11, y: 10)
                    }
                }.frame(width: 48, height: 48)
            }.buttonStyle(.glassProminent).buttonBorderShape(.circle).tint(.accentColor)
                .disabled(timer.state == nil || timer.state?.isBusy == true || timer.state?.isLoading == true)
                .accessibilityLabel(timer.state?.timer == nil ? "开始专注" : "返回当前计时")
                .accessibilityIdentifier("focus.management.action")
        }.padding(.horizontal, 20).padding(.bottom, 12)
    }
}


struct FocusManagementDashboard: View {
    let data: FocusManagementSnapshot
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .topLeading), count: typeSize >= .xxxLarge ? 1 : 2), alignment: .leading, spacing: 12) {
            FocusManagementSummary(title: "今天", summary: data.today).frame(maxWidth: .infinity, alignment: .leading)
            FocusManagementSummary(title: "累计", summary: data.allTime.summary).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct FocusManagementAllocationPreview: View {
    let statistics: FocusStatisticsSnapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("累计投入 · " + FocusTimerFormatting.duration(statistics.summary.totalDurationSeconds)).font(.subheadline)
            if let split = statistics.summary.durationByTarget {
                ProgressView(value: Double(split.taskDurationSeconds), total: Double(max(1, statistics.summary.totalDurationSeconds)))
                Text("任务 " + FocusTimerFormatting.duration(split.taskDurationSeconds) + " · 习惯 " + FocusTimerFormatting.duration(split.habitDurationSeconds))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 6)
    }
}
