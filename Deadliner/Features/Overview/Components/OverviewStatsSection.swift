//
//  OverviewStatsSection.swift
//  Deadliner
//
//  Created by Aritx 音唯 on 2026/3/8.
//

import SwiftUI
import Charts

struct OverviewStatsCard: View {
    @ObservedObject var viewModel: OverviewViewModel
    let cardId: OverviewCard
    
    var body: some View {
        switch cardId {
        case .activeStats:
            ActiveStatsCard(
                completed: viewModel.todayCompleted,
                todo: viewModel.todayTodo,
                overdue: viewModel.todayOverdue
            )
        case .completionTime:
            CompletionTimeCard(completionTimeStats: viewModel.completionTimeStats)
        case .historyStats:
            HistoryStatsCard(historyStats: viewModel.historyStats)
        }
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
        .padding(22) // 增大内部边距
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(28)
        .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 4)

    }
}

private struct ActiveStatsCard: View {
    let completed: Int
    let todo: Int
    let overdue: Int
    
    var body: some View {
        StatsCardContainer {
            Text("今日概况")
                .font(.headline)
                .padding(.bottom, 20)
            
            HStack {
                statItem(label: "今日完成", value: completed, color: .green)
                Spacer()
                statItem(label: "待办任务", value: todo, color: .orange)
                Spacer()
                statItem(label: "今日逾期", value: overdue, color: .red)
            }
            .padding(.horizontal, 10)
        }
    }
    
    private func statItem(label: String, value: Int, color: Color) -> some View {
        VStack {
            Text("\(value)")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(color)
                .padding(.bottom, 4)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

private struct CompletionTimeCard: View {
    let completionTimeStats: [(String, Int)]
    
    var body: some View {
        StatsCardContainer {
            Text("完成时间分布")
                .font(.headline)
                .padding(.bottom, 10)
            
            if !completionTimeStats.isEmpty {
                Chart {
                    ForEach(completionTimeStats, id: \.0) { item in
                        BarMark(
                            x: .value("完成数", item.1),
                            y: .value("时段", item.0)
                        )
                        .foregroundStyle(.blue.gradient)
                        .cornerRadius(4)
                    }
                }
                .frame(height: 280)
            } else {
                VStack {
                    Text("暂无已完成数据")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(height: 100)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct HistoryStatsCard: View {
    let historyStats: [String: Int]
    
    @State private var selectedLabel: String?
    
    var body: some View {
        StatsCardContainer {
            Text("历史统计")
                .font(.headline)
                .padding(.bottom, 10)
            
            let total = historyStats.values.reduce(0, +)
            
            if total > 0 {
                ZStack {
                    Chart {
                        ForEach(historyStats.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                            SectorMark(
                                angle: .value("数值", value),
                                innerRadius: .ratio(0.65),
                                angularInset: 2
                            )
                            .foregroundStyle(by: .value("类型", key))
                            .cornerRadius(4)
                        }
                    }
                    .chartLegend(position: .bottom, alignment: .center, spacing: 16)
                    .frame(height: 260)
                    
                    VStack {
                        if let selected = selectedLabel, let value = historyStats[selected] {
                            Text(selected)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(value)")
                                .font(.system(size: 24, weight: .bold))
                        } else {
                            Text("总计")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(total)")
                                .font(.system(size: 24, weight: .bold))
                        }
                    }
                    .offset(y: -16)
                }
            } else {
                VStack {
                    Text("暂无数据")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(height: 100)
                .frame(maxWidth: .infinity)
            }
        }
    }
}
