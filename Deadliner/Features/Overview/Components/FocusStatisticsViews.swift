#if canImport(Shared)
import SwiftUI
import Charts
import Shared

struct FocusStatisticsSummaryView: View {
    let title: String
    let summary: FocusStatisticsSummary?
    var body: some View {
        if let summary {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(title).font(.subheadline.weight(.medium))
                    Spacer()
                    Text(FocusTimerFormatting.duration(summary.totalDurationSeconds))
                        .font(.headline).monospacedDigit()
                }
                if let split = summary.durationByTarget, split.habitDurationSeconds > 0 {
                    Text("任务 \(FocusTimerFormatting.duration(split.taskDurationSeconds)) · 习惯 \(FocusTimerFormatting.duration(split.habitDurationSeconds))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.top, 16)
        }
    }
}

struct FocusDurationChart: View {
    let title: String
    let points: [FocusDurationPoint]
    let summary: FocusStatisticsSummary?
    @State private var selectedDate: String?
    var body: some View {
        if !points.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Divider().padding(.top, 16)
                FocusStatisticsSummaryView(title: title, summary: summary)
                if points.allSatisfy({ $0.durationSeconds == 0 }) {
                    Text("暂无专注记录").font(.caption).foregroundStyle(.secondary)
                } else {
                Chart(points, id: \.startDate) { point in
                    BarMark(x: .value("日期", label(point.startDate)),
                            y: .value("分钟", Double(point.durationSeconds) / 60))
                        .foregroundStyle(Color.indigo.gradient).cornerRadius(3)
                        .accessibilityLabel(point.startDate)
                        .accessibilityValue(FocusTimerFormatting.duration(point.durationSeconds) + brief(point.durationByTarget))
                }
                .chartYAxisLabel("分钟")
                .chartXSelection(value: $selectedDate)
                .frame(height: 160)
                }
                if let selectedDate, let point = points.first(where: { label($0.startDate) == selectedDate }) {
                    Text("\(point.startDate) · \(FocusTimerFormatting.duration(point.durationSeconds))" + brief(point.durationByTarget))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
    private func brief(_ split: FocusDurationBreakdown?) -> String {
        guard let split, split.habitDurationSeconds > 0 else { return "" }
        return " · 任务 "+FocusTimerFormatting.duration(split.taskDurationSeconds)+" · 习惯 "+FocusTimerFormatting.duration(split.habitDurationSeconds)
    }
    private func label(_ date: String) -> String { String(date.dropFirst(5)) }
}

struct FocusDistributionView: View {
    let statistics: FocusStatisticsSnapshot?
    var body: some View {
        if let statistics, statistics.summary.totalDurationSeconds > 0 {
            VStack(alignment: .leading, spacing: 8) {
                Divider().padding(.top, 16)
                Text("本月专注分布").font(.subheadline.weight(.medium)).padding(.top, 8)
                ForEach(Array(statistics.targets.prefix(3).enumerated()), id: \.offset) { _, item in
                    HStack {
                        Label(item.title, systemImage: item.target.kind == .habit ? "leaf" : "checklist")
                            .lineLimit(1)
                        Spacer()
                        Text(FocusTimerFormatting.duration(item.durationSeconds)).monospacedDigit()
                    }.font(.caption)
                }
            }
        }
    }
}
#endif
