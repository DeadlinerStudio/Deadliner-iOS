//
//  DashboardSection.swift
//  Deadliner
//
//  Created by Aritx 音唯 on 2026/3/8.
//

import SwiftUI
import Charts

struct DashboardSection: View {
    let metrics: [Metric]
    let dailyStats: [DailyStat]
    let lastMonthName: String
    let analysis: MonthlyAnalysisResult?
    let isAnalyzing: Bool
    
    let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]
    
    var body: some View {
        VStack(spacing: 12) {
            FloatUpRow(index: 0) {
                DashboardHeader(monthName: lastMonthName)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
            }
            
            if isAnalyzing {
                FloatUpRow(index: 1) {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("AI 正在深度分析上月数据...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(22)
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .cornerRadius(28)
                    .padding(.horizontal, 16)
                }
            } else if let analysis = analysis {
                FloatUpRow(index: 1) {
                    AIAnalysisCard(analysis: analysis)
                        .padding(.horizontal, 16)
                }
            }
            
            LazyVGrid(columns: columns, spacing: 12) {
                let baseIndex = (analysis != nil || isAnalyzing) ? 2 : 1
                ForEach(Array(metrics.enumerated()), id: \.element.id) { index, metric in
                    FloatUpRow(index: index + baseIndex) {
                        MetricCard(metric: metric)
                    }
                }
            }
            .padding(.horizontal, 16)
            
            if !dailyStats.isEmpty {
                let baseIndex = metrics.count + ((analysis != nil || isAnalyzing) ? 2 : 1)
                FloatUpRow(index: baseIndex) {
                    LastMonthActivityMap(monthName: lastMonthName, dailyStats: dailyStats)
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                }
            }
            
            Spacer(minLength: 30)
        }
    }
}

private struct AIAnalysisCard: View {
    let analysis: MonthlyAnalysisResult
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.purple)
                Text("AI 月度洞察")
                    .font(.headline)
                Spacer()
            }
            
            Text(analysis.summary)
                .font(.subheadline)
                .foregroundColor(.primary.opacity(0.8))
                .lineSpacing(4)
            
            // "Word Cloud" tags
            FlowLayout(tags: analysis.keywords, spacing: 8)
        }
        .padding(22)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(28)
        .shadow(color: Color.black.opacity(0.02), radius: 5, x: 0, y: 2)
    }
}

// A simple FlowLayout for tags
struct FlowLayout: View {
    let tags: [String]
    let spacing: CGFloat
    
    @State private var totalHeight = CGFloat.zero

    var body: some View {
        VStack {
            GeometryReader { geometry in
                self.generateContent(in: geometry)
            }
        }
        .frame(height: totalHeight)
    }

    private func generateContent(in g: GeometryProxy) -> some View {
        var width = CGFloat.zero
        var height = CGFloat.zero

        return ZStack(alignment: .topLeading) {
            ForEach(self.tags, id: \.self) { tag in
                self.item(for: tag)
                    .padding([.horizontal, .vertical], spacing / 2)
                    .alignmentGuide(.leading, computeValue: { d in
                        if (abs(width - d.width) > g.size.width) {
                            width = 0
                            height -= d.height
                        }
                        let result = width
                        if tag == self.tags.last! {
                            width = 0 // last item
                        } else {
                            width -= d.width
                        }
                        return result
                    })
                    .alignmentGuide(.top, computeValue: { d in
                        let result = height
                        if tag == self.tags.last! {
                            height = 0 // last item
                        }
                        return result
                    })
            }
        }
        .background(viewHeightReader($totalHeight))
    }

    private func item(for text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.purple.opacity(0.1))
            )
            .foregroundColor(.purple)
    }

    private func viewHeightReader(_ binding: Binding<CGFloat>) -> some View {
        return GeometryReader { geometry -> Color in
            let rect = geometry.frame(in: .local)
            DispatchQueue.main.async {
                binding.wrappedValue = rect.size.height
            }
            return .clear
        }
    }
}

private struct LastMonthActivityMap: View {
    let monthName: String
    let dailyStats: [DailyStat]
    
    // Grid layout for roughly 5 weeks x 7 days
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("\(monthName)活动分布")
                    .font(.headline)
                Spacer()
                Text("每日完成频率")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(dailyStats) { day in
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(color(for: day.completedCount))
                            .aspectRatio(1, contentMode: .fit)
                        
                        Text(day.date)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(day.completedCount > 0 ? .white : .secondary.opacity(0.5))
                    }
                }
            }
            
            HStack(spacing: 4) {
                Text("低频率")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                ForEach(0..<5) { level in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color(for: level * 2))
                        .frame(width: 12, height: 12)
                }
                
                Text("高频率")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 4)
        }
        .padding(22)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(28)
        .shadow(color: Color.black.opacity(0.02), radius: 5, x: 0, y: 2)
    }
    
    private func color(for count: Int) -> Color {
        if count == 0 { return Color(UIColor.systemGray6) }
        if count < 2 { return Color.blue.opacity(0.3) }
        if count < 4 { return Color.blue.opacity(0.5) }
        if count < 6 { return Color.blue.opacity(0.7) }
        return Color.blue
    }
}

private struct DashboardHeader: View {
    let monthName: String
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [Color(hex: "#4A90E2"), Color(hex: "#9013FE")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay(
                Image(systemName: "chart.bar.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .foregroundColor(.white.opacity(0.15))
                    .scaleEffect(1.1)
                    .offset(x: 40, y: 20)
            )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(monthName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                Text("数据汇总")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
            }
            .padding(24)
        }
        .frame(height: 145)
        .frame(maxWidth: .infinity)
        .cornerRadius(28)
        .clipped()
        .shadow(color: Color.blue.opacity(0.15), radius: 10, x: 0, y: 5)
    }
}

private struct MetricCard: View {
    let metric: Metric
    
    private var trendColor: Color {
        guard let isDown = metric.isDown else { return .blue }
        let isNegativeMetric = metric.label.contains("逾期")
        if isNegativeMetric {
            return isDown ? .green : .red
        } else {
            return isDown ? .red : .green
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) { // 恢复合理的垂直间距
            Text(metric.label)
                .font(.system(size: 13, weight: .medium)) // 恢复字号
                .foregroundColor(.secondary)
            
            Text(metric.value)
                .font(.system(size: 26, weight: .bold)) // 恢复视觉冲击力
                .foregroundColor(.primary)
                .minimumScaleFactor(0.8)
            
            if let change = metric.change {
                HStack(spacing: 3) {
                    if let isDown = metric.isDown {
                        Image(systemName: isDown ? "arrow.down" : "arrow.up")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(trendColor)
                    }
                    
                    Text(change)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(trendColor)
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 95, alignment: .topLeading) // 恢复高度
        .padding(18) // 恢复到舒适的内边距
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(28)
        .shadow(color: Color.black.opacity(0.02), radius: 5, x: 0, y: 2)
    }
}
