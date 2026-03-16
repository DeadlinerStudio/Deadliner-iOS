//
//  TrendAnalysisSection.swift
//  Deadliner
//
//  Created by Aritx 音唯 on 2026/3/8.
//

import SwiftUI
import Charts

struct TrendAnalysisCard: View {
    @ObservedObject var viewModel: OverviewViewModel
    let cardId: TrendCard
    
    var body: some View {
        switch cardId {
        case .dailyTrend:
            DailyCompletedCard(dailyStats: viewModel.dailyStats)
        case .monthlyTrend:
            MonthlyTrendCard(monthlyStats: viewModel.monthlyStats)
        case .weeklyTrend:
            PrevWeeksCard(weeklyStats: viewModel.weeklyStats)
        case .contributionHeatmap:
            ContributionHeatmapCard(stats: viewModel.contributionStats)
        }
    }
}

private struct ContributionHeatmapCard: View {
    let stats: [ContributionDay]
    
    // 7 rows for 7 days of the week
    private let rows = Array(repeating: GridItem(.fixed(12), spacing: 3), count: 7)
    
    var body: some View {
        StatsCardContainer {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("活跃热力图")
                        .font(.headline)
                    Spacer()
                    Text("\(stats.count)天内")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHGrid(rows: rows, spacing: 3) {
                        ForEach(stats) { day in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(color(for: day.count))
                                .frame(width: 12, height: 12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 2)
                                        .stroke(Color.primary.opacity(0.05), lineWidth: 0.5)
                                )
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                HStack(spacing: 4) {
                    Text("少")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    ForEach(0..<5) { level in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(color(for: level))
                            .frame(width: 8, height: 8)
                    }
                    
                    Text("多")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private func color(for count: Int) -> Color {
        if count == 0 { return Color(UIColor.systemGray6) }
        if count < 2 { return Color.green.opacity(0.3) }
        if count < 4 { return Color.green.opacity(0.5) }
        if count < 6 { return Color.green.opacity(0.7) }
        return Color.green
    }
}

private struct StatsCardContainer<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(22)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(28)
        .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 4)
    }
}

private struct DailyCompletedCard: View {
    let dailyStats: [DailyStat]
    @State private var isOverdueShow: Bool = true
    
    var body: some View {
        StatsCardContainer {
            HStack {
                Text("本周完成情况")
                    .font(.headline)
                
                Spacer()
                
                Toggle(isOn: $isOverdueShow) {
                    Text("显示逾期")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .toggleStyle(CheckboxToggleStyle(color: .red))
            }
            .padding(.bottom, 10)
            
            if !dailyStats.isEmpty {
                Chart {
                    ForEach(dailyStats) { item in
                        BarMark(
                            x: .value("日期", item.date),
                            y: .value("完成", item.completedCount),
                            stacking: .standard
                        )
                        .foregroundStyle(by: .value("类型", "完成"))
                        
                        if isOverdueShow {
                            BarMark(
                                x: .value("日期", item.date),
                                y: .value("逾期", item.overdueCount),
                                stacking: .standard
                            )
                            .foregroundStyle(by: .value("类型", "逾期"))
                        }
                    }
                }
                .chartForegroundStyleScale([
                    "完成": Color.green,
                    "逾期": Color.red
                ])
                .chartXAxis {
                    AxisMarks(values: .automatic) { _ in
                        AxisValueLabel()
                    }
                }
                .chartYAxis {
                    AxisMarks(values: .automatic) { _ in
                        AxisGridLine() 
                        AxisValueLabel()
                    }
                }
                .chartLegend(position: .bottom, alignment: .center)
                .frame(height: 220)
            } else {
                emptyView
            }
        }
    }
    
    private var emptyView: some View {
        VStack {
            Text("暂无数据")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(height: 100)
        .frame(maxWidth: .infinity)
    }
}

private struct MonthlyTrendCard: View {
    let monthlyStats: [MonthlyStat]
    
    private let colors: [String: Color] = [
        "总任务": .blue,
        "已完成": .green,
        "逾期完成": .orange
    ]
    
    var body: some View {
        StatsCardContainer {
            Text("每月趋势")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 16)
            
            if !monthlyStats.isEmpty {
                Chart {
                    // --- 1. 总任务 ---
                    ForEach(monthlyStats) { item in
                        AreaMark(
                            x: .value("月份", item.month),
                            y: .value("数值", item.totalCount),
                            stacking: .unstacked
                        )
                        .foregroundStyle(by: .value("类型", "总任务"))
                        .opacity(0.1)
                        .interpolationMethod(.catmullRom)
                        
                        LineMark(
                            x: .value("月份", item.month),
                            y: .value("数值", item.totalCount)
                        )
                        .foregroundStyle(by: .value("类型", "总任务"))
                        .symbol { chartSymbol(for: "总任务") }
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    }
                    
                    // --- 2. 已完成 ---
                    ForEach(monthlyStats) { item in
                        AreaMark(
                            x: .value("月份", item.month),
                            y: .value("数值", item.completedCount),
                            stacking: .unstacked
                        )
                        .foregroundStyle(by: .value("类型", "已完成"))
                        .opacity(0.1)
                        .interpolationMethod(.catmullRom)
                        
                        LineMark(
                            x: .value("月份", item.month),
                            y: .value("数值", item.completedCount)
                        )
                        .foregroundStyle(by: .value("类型", "已完成"))
                        .symbol { chartSymbol(for: "已完成") }
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    }
                    
                    // --- 3. 逾期完成 ---
                    ForEach(monthlyStats) { item in
                        AreaMark(
                            x: .value("月份", item.month),
                            y: .value("数值", item.overdueCompletedCount),
                            stacking: .unstacked
                        )
                        .foregroundStyle(by: .value("类型", "逾期完成"))
                        .opacity(0.1)
                        .interpolationMethod(.catmullRom)
                        
                        LineMark(
                            x: .value("月份", item.month),
                            y: .value("数值", item.overdueCompletedCount)
                        )
                        .foregroundStyle(by: .value("类型", "逾期完成"))
                        .symbol { chartSymbol(for: "逾期完成") }
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    }
                }
                .chartForegroundStyleScale([
                    "总任务": .blue,
                    "已完成": .green,
                    "逾期完成": .orange
                ])
                .chartXAxis {
                    AxisMarks(values: .automatic) { _ in
                        AxisValueLabel()
                    }
                }
                .chartYAxis {
                    AxisMarks(values: .automatic) { _ in
                        AxisGridLine() 
                        AxisValueLabel()
                    }
                }
                .chartLegend(position: .bottom, alignment: .center, spacing: 16)
                .frame(height: 240)
            } else {
                emptyView
            }
        }
    }
    
    @ViewBuilder
    private func chartSymbol(for type: String) -> some View {
        let color = colors[type] ?? .blue
        Circle()
            .strokeBorder(color, lineWidth: 2)
            .background(Circle().fill(.white))
            .frame(width: 8, height: 8)
    }
    
    private var emptyView: some View {
        VStack {
            Text("暂无数据")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(height: 100)
        .frame(maxWidth: .infinity)
    }
}

private struct PrevWeeksCard: View {
    let weeklyStats: [WeeklyStat]
    
    var body: some View {
        StatsCardContainer {
            Text("近4周完成")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 10)
            
            if !weeklyStats.isEmpty {
                Chart {
                    ForEach(weeklyStats) { item in
                        BarMark(
                            x: .value("周", item.weekLabel),
                            y: .value("完成", item.completedCount)
                        )
                        .foregroundStyle(Color.orange.gradient)
                        .cornerRadius(4)
                    }
                }
                .chartYAxis {
                    AxisMarks(values: .automatic) { _ in
                        AxisGridLine() 
                        AxisValueLabel()
                    }
                }
                .frame(height: 200)
            } else {
                emptyView
            }
        }
    }
    
    private var emptyView: some View {
        VStack {
            Text("暂无数据")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(height: 100)
        .frame(maxWidth: .infinity)
    }
}

struct CheckboxToggleStyle: ToggleStyle {
    let color: Color
    
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            Image(systemName: configuration.isOn ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20))
                .foregroundColor(configuration.isOn ? color : .secondary)
                .onTapGesture {
                    configuration.isOn.toggle()
                }
            configuration.label
        }
    }
}
