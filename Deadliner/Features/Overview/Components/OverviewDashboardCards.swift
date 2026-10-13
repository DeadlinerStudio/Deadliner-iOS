import SwiftUI
import Charts
import Shared

struct OverviewSurface<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 28))
    }
}

struct OverviewCardHeading: View {
    let title: String
    var disclosure = false
    var body: some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            if disclosure { Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary) }
        }
    }
}

struct OverviewFailureView: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message).font(.subheadline).foregroundStyle(.secondary)
            Button("重试", action: retry).buttonStyle(.bordered)
        }
    }
}

struct OverviewMonthCalendar: View {
    @ObservedObject var model: OverviewViewModel
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selectedDay: String?
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    private var leadingCells: Int { (OverviewPeriod.calendar.component(.weekday, from: model.selectedMonth) + 5) % 7 }
    private var dayCount: Int { OverviewPeriod.calendar.range(of: .day, in: .month, for: model.selectedMonth)!.count }
    var body: some View {
        OverviewSurface {
            OverviewCardHeading(title: "月度活动")
            if model.monthLoading { ProgressView().frame(maxWidth: .infinity) }
            else if let error = model.monthError { OverviewFailureView(message: error, retry: model.loadData) }
            else {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(Array(["一", "二", "三", "四", "五", "六", "日"].enumerated()), id: \.offset) { _, day in
                        Text(day).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    }
                    ForEach(0..<(leadingCells + dayCount), id: \.self) { cell in
                        if cell < leadingCells { Color.clear.frame(height: 36) }
                        else { dayCell(cell - leadingCells + 1) }
                    }
                }
                HStack(spacing: 5) {
                    Text("任务完成").font(.caption2).foregroundStyle(.secondary)
                    ForEach(0..<5) { level in RoundedRectangle(cornerRadius: 2).fill(heat(level * 2)).frame(width: 10, height: 10) }
                    Circle().fill(.blue).frame(width: 4, height: 4).padding(.leading, 6)
                    Text("有专注").font(.caption2).foregroundStyle(.secondary)
                }.accessibilityElement(children: .combine)
                if let error = model.managementError {
                    OverviewFailureView(message: "专注活动：" + error, retry: model.loadData)
                }
            }
        }
        .alert("当日活动", isPresented: Binding(get: { selectedDay != nil }, set: { if !$0 { selectedDay = nil } })) {
            Button("完成", role: .cancel) { selectedDay = nil }
        } message: {
            if let day = selectedDay {
                let count = model.monthState?.daily.first { $0.date == day }?.completedCount ?? 0
                Text("\(day)\n完成任务 \(count) 项\n" + (model.managementLoading ? "专注数据加载中" : model.managementError == nil ? "专注 " + FocusTimerFormatting.duration(model.focusSeconds(on: day)) : "专注数据暂不可用"))
            }
        }
        .onChange(of: model.selectedMonth) { selectedDay = nil }
    }
    private func dayCell(_ day: Int) -> some View {
        let date = OverviewPeriod.calendar.date(byAdding: .day, value: day - 1, to: model.selectedMonth)!
        let key = OverviewPeriod.key(date)
        let future = date > OverviewPeriod.calendar.startOfDay(for: Date())
        let count = Int(model.monthState?.daily.first { $0.date == key }?.completedCount ?? 0)
        return Button { selectedDay = key } label: {
            VStack(spacing: 2) {
                Text("\(day)").font(.caption.weight(.medium)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.35)
                Circle().fill(model.focusSeconds(on: key) > 0 ? Color.blue : .clear).frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity)
            .frame(height: typeSize.isAccessibilitySize ? 64 : 36)
            .background(heat(count), in: RoundedRectangle(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).stroke(OverviewPeriod.calendar.isDateInToday(date) ? Color.accentColor : .clear, lineWidth: 1) }
            .opacity(future ? 0.35 : 1)
        }
        .buttonStyle(.plain).disabled(future)
        .accessibilityLabel("\(key)，完成 \(count) 项，" + (future ? "未来日期" : "专注 " + FocusTimerFormatting.duration(model.focusSeconds(on: key))))
    }
    private func heat(_ count: Int) -> Color {
        count == 0 ? Color(uiColor: .tertiarySystemGroupedBackground) : .green.opacity(count < 2 ? 0.2 : count < 4 ? 0.35 : count < 6 ? 0.55 : 0.75)
    }
}

struct OverviewTaskResultCard: View {
    @ObservedObject var model: OverviewViewModel
    @Environment(\.dynamicTypeSize) private var typeSize
    private var statuses: [(String, Int, Color)] {
        let status = model.monthState?.statusDistribution
        return [("待办", Int(status?.pending ?? 0), .orange), ("完成", Int(status?.completed ?? 0), .green),
                ("逾期", Int(status?.overdue ?? 0), .red), ("放弃", Int(status?.abandoned ?? 0), .gray)]
    }
    var body: some View {
        OverviewSurface {
            OverviewCardHeading(title: "任务统计", disclosure: true)
            if model.monthLoading { ProgressView() }
            else if let error = model.monthError { Text(error).font(.subheadline).foregroundStyle(.secondary) }
            else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) { result; Spacer(minLength: 0); pie }
                    VStack(alignment: .leading, spacing: 12) { result; pie }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: typeSize.isAccessibilitySize ? 1 : 2), alignment: .leading, spacing: 10) {
                    ForEach(statuses, id: \.0) { label, count, color in
                        HStack(spacing: 6) {
                            Circle().fill(color).frame(width: 7, height: 7)
                            Text(label).foregroundStyle(.secondary)
                            Text("\(count)").monospacedDigit()
                        }.font(.subheadline).accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }
    private var result: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(model.monthState?.completedCount ?? 0) 项").font(.title2.bold()).monospacedDigit()
            if let change = model.comparison {
                Text(change.text).font(.caption).foregroundStyle(change.direction > 0 ? Color.green : change.direction < 0 ? .red : .secondary)
            } else { Text(model.comparisonLoading ? "同期数据加载中…" : "同期数据暂不可用").font(.caption).foregroundStyle(.secondary) }
        }
    }
    private var pie: some View {
        Group {
            if statuses.reduce(0, { $0 + $1.1 }) == 0 { Circle().fill(Color(uiColor: .systemGray5)) }
            else {
                Chart {
                    ForEach(statuses, id: \.0) { label, count, color in
                        SectorMark(angle: .value(label, count)).foregroundStyle(color)
                    }
                }.chartLegend(.hidden)
            }
        }.frame(width: 88, height: 88).accessibilityHidden(true)
    }
}

struct OverviewTrendPreview: View {
    @ObservedObject var model: OverviewViewModel
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        OverviewSurface {
            OverviewCardHeading(title: "趋势", disclosure: true)
            Text("年度贡献、每日、每周与每月趋势").font(.caption).foregroundStyle(.secondary)
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 20)) : AnyLayout(HStackLayout(spacing: 20))
            layout {
                preview(title: "任务 · 最近7天", values: model.dailyStats.suffix(7).map { Double($0.completedCount) }, focus: false, error: model.taskError, loading: model.isLoading)
                preview(title: "专注 · 最近7天", values: (model.focus?.daily ?? []).suffix(7).map { Double($0.durationSeconds) / 60 }, focus: true, error: model.focusError, loading: model.focusLoading)
            }
        }
    }
    private func preview(title: String, values: [Double], focus: Bool, error: String?, loading: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            if loading { ProgressView().frame(maxWidth: .infinity).frame(height: 72) }
            else if error != nil { Text("数据暂不可用").font(.caption).frame(height: 72) }
            else if values.isEmpty || values.allSatisfy({ $0 == 0 }) {
                VStack { Spacer(); Rectangle().fill(Color.secondary.opacity(0.2)).frame(height: 1); Text("暂无记录").font(.caption2).foregroundStyle(.secondary); Spacer() }.frame(height: 72)
            } else {
                Chart {
                    ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                        if focus {
                            AreaMark(x: .value("日期", index), y: .value("分钟", value)).foregroundStyle(Color.blue.opacity(0.12)).interpolationMethod(.monotone)
                            LineMark(x: .value("日期", index), y: .value("分钟", value)).foregroundStyle(.blue).lineStyle(StrokeStyle(lineWidth: 1.5)).interpolationMethod(.monotone)
                        } else {
                            BarMark(x: .value("日期", index), y: .value("任务", value), width: .ratio(0.45)).foregroundStyle(.green).cornerRadius(3)
                        }
                    }
                }.chartXAxis(.hidden).chartYAxis(.hidden).chartYScale(domain: 0...max(values.max() ?? 1, 1)).frame(height: 72)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct OverviewInsightContent: View {
    @ObservedObject var model: OverviewViewModel
    var body: some View {
        if model.isAnalyzing { HStack { ProgressView(); Text("正在分析上月数据…").font(.subheadline) } }
        else if let analysis = model.monthlyAnalysis {
            Text(analysis.summary).font(.subheadline).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            OverviewKeywordLayout {
                ForEach(Array(analysis.keywords.enumerated()), id: \.offset) { _, keyword in
                    Text(keyword).font(.caption).foregroundStyle(.purple)
                        .padding(.horizontal, 10).padding(.vertical, 6).background(Color.purple.opacity(0.09), in: Capsule())
                }
            }
        } else { OverviewFailureView(message: model.insightError ?? "正在加载月度复盘…", retry: model.retryInsight) }
    }
}

struct OverviewKeywordLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize { arrange(width: proposal.width ?? 320, subviews: subviews).size }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let placement = arrange(width: bounds.width, subviews: subviews)
        for (index, point) in placement.points.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: ProposedViewSize(width: min(subviews[index].sizeThatFits(.unspecified).width, bounds.width), height: nil))
        }
    }
    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        var x: CGFloat = 0; var y: CGFloat = 0; var row: CGFloat = 0; var points: [CGPoint] = []
        for view in subviews {
            let size = view.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if x > 0 && x + size.width > width { x = 0; y += row + 8; row = 0 }
            points.append(CGPoint(x: x, y: y)); x += size.width + 8; row = max(row, size.height)
        }
        return (CGSize(width: width, height: y + row), points)
    }
}
