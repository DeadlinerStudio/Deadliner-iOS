//
//  DeadlinerWidget.swift
//  Deadliner
//

import WidgetKit
import SwiftUI
import SwiftData
import os

// MARK: - Timeline Provider

struct DeadlinerEntry: TimelineEntry {
    let date: Date
    let task: DDLItem?
    let topTasks: [DDLItem]
    let remainingCount: Int
    let totalActiveCount: Int
    let urgentCount: Int
}

struct DeadlinerWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> DeadlinerEntry {
        DeadlinerEntry(date: Date(), task: DDLItem.mock(), topTasks: [DDLItem.mock()], remainingCount: 5, totalActiveCount: 7, urgentCount: 2)
    }

    func getSnapshot(in context: Context, completion: @escaping (DeadlinerEntry) -> ()) {
        let entry = DeadlinerEntry(date: Date(), task: DDLItem.mock(), topTasks: [DDLItem.mock()], remainingCount: 5, totalActiveCount: 7, urgentCount: 2)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DeadlinerEntry>) -> ()) {
        Task {
            let stats = await fetchWidgetData()
            let entry = DeadlinerEntry(
                date: Date(),
                task: stats.task,
                topTasks: stats.topTasks,
                remainingCount: stats.remaining,
                totalActiveCount: stats.active,
                urgentCount: stats.urgent
            )
            let nextUpdate = Date().addingTimeInterval(15 * 60)
            let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
            completion(timeline)
        }
    }

    @MainActor
    private func fetchWidgetData() async -> (task: DDLItem?, topTasks: [DDLItem], remaining: Int, active: Int, urgent: Int) {
        let container = SharedModelContainer.shared
        let context = ModelContext(container)
        
        let fd = FetchDescriptor<DDLItemEntity>()
        let allEntities = (try? context.fetch(fd)) ?? []
        
        let taskTypeRaw = "task"
        let validTasks = allEntities.filter { entity in
            return entity.isTombstoned == false && entity.typeRaw == taskTypeRaw
        }
        
        let activeTasks = validTasks.filter { !$0.isArchived }
        let remainingTasks = activeTasks.filter { !$0.isCompleted }
        let sortedRemaining = remainingTasks.sorted { $0.endTime < $1.endTime }
        
        let topTasks = sortedRemaining.prefix(3).map { $0.toDomain() }
        let nearestTask = topTasks.first
        
        let remaining = remainingTasks.count
        let active = activeTasks.count
        
        let now = Date()
        let tomorrow = now.addingTimeInterval(24 * 3600)
        let urgent = remainingTasks.filter { item in
            guard let date = DeadlineDateParser.safeParseOptional(item.endTime) else { return false }
            return date > now && date <= tomorrow
        }.count
        
        return (nearestTask, topTasks, remaining, active, urgent)
    }
}

// MARK: - Mock Data

extension DDLItem {
    static func mock() -> DDLItem {
        let now = Date()
        let end = now.addingTimeInterval(3600 * 24 * 3)
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return DDLItem(id: -1, name: "完成项目演示文档", startTime: "", endTime: fmt.string(from: end), isCompleted: false, completeTime: "", note: "", isArchived: false, isStared: true, type: .task, habitCount: 0, habitTotalCount: 0, calendarEvent: -1, timestamp: "")
    }
}

// MARK: - Widget Views

struct DeadlinerWidgetEntryView : View {
    var entry: DeadlinerWidgetProvider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            CircularWidgetView(entry: entry)
                .containerBackground(.clear, for: .widget)
        case .accessoryRectangular:
            if let _ = entry.task {
                RectangularWidgetView(entry: entry)
                    .containerBackground(.clear, for: .widget)
            } else {
                Text("所有任务已完成")
                    .font(.system(size: 14, weight: .medium).monospaced())
                    .foregroundStyle(.secondary)
                    .containerBackground(.clear, for: .widget)
            }
        case .systemSmall:
            SmallHomeWidgetView(entry: entry)
        case .systemMedium:
            MediumHomeWidgetView(entry: entry)
        default:
            EmptyView()
        }
    }
}

// 2x1 锁屏小组件 (使用自定义 LinearProgressView 和等宽字体)
struct RectangularWidgetView: View {
    let entry: DeadlinerEntry
    
    var body: some View {
        if let task = entry.task {
            let isClose = isWithin12Hours(task: task)
            
            VStack(alignment: .leading, spacing: 0) {
                // 顶部：任务名称
                Text(task.name)
                    .font(.system(size: isClose ? 15 : 13, weight: .medium))
                    .lineLimit(1)
                
                Spacer(minLength: 2)
                
                if isClose {
                    // 临近模式：大字倒计时
                    Text(remainingTimeStr(task: task) + " rem.")
                        .font(.system(size: 22, weight: .heavy).monospaced())
                        .padding(.bottom, 4)
                } else {
                    // 概览模式
                    HStack(alignment: .firstTextBaseline) {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text("\(entry.remainingCount)")
                                .font(.system(size: 20, weight: .heavy).monospaced())
                            Text("/\(entry.totalActiveCount)")
                                .font(.system(size: 10, weight: .bold).monospaced())
                                .foregroundStyle(.secondary)
                            Text("任务")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Text(remainingTimeStr(task: task))
                            .font(.system(size: 13, weight: .bold).monospaced())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 6)
                }
                
                LinearProgressView(value: calculateProgress(task: task), shape: Capsule())
                    .frame(height: 7)
                    .tint(.primary)
            }
        }
    }
}

// 1x1 锁屏小组件 (等宽字体)
struct CircularWidgetView: View {
    let entry: DeadlinerEntry
    
    private var urgentProportion: Double {
        guard entry.remainingCount > 0 else { return 0 }
        return Double(entry.urgentCount) / Double(entry.remainingCount)
    }
    
    var body: some View {
        Gauge(value: urgentProportion) {
            Circle().frame(width: 2, height: 2)
        } currentValueLabel: {
            VStack(spacing: -1) {
                Text("\(entry.remainingCount)")
                    .font(.system(size: 22, weight: .bold).monospaced())
                Text("\(entry.totalActiveCount)")
                    .font(.system(size: 11, weight: .bold).monospaced())
                    .foregroundStyle(.secondary.opacity(0.8))
            }
        }
        .gaugeStyle(.accessoryCircular)
    }
}

// 主屏幕占位组件 (同样同步等宽字体和自定义进度条)
struct SmallHomeWidgetView: View {
    let entry: DeadlinerEntry
    
    private var brandColor: Color {
        Color(red: 1.0, green: 0.427, blue: 0.427) // #FF6D6D
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Top Bar - Better spacing and alignment
            HStack(spacing: 6) {
                Image("AppIcon")
                    .resizable()
                    .frame(width: 16, height: 16)
                    .cornerRadius(4)
                
                Text("Deadliner")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.primary.opacity(0.9))
                
                Spacer()
                
                if entry.remainingCount > 0 {
                    Text("\(entry.remainingCount)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(brandColor.opacity(0.12))
                        .cornerRadius(4)
                        .foregroundColor(brandColor)
                }
            }
            .padding(.horizontal, 2)
            
            // Task List
            if entry.topTasks.isEmpty {
                Spacer()
                VStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(brandColor.opacity(0.4))
                    Text("全部搞定")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                VStack(spacing: 4) {
                    ForEach(entry.topTasks.prefix(3)) { task in
                        CompactTaskRow(task: task)
                    }
                }
            }
            
            Spacer(minLength: 0)
        }
        .padding(8)
        .containerBackground(for: .widget) {
            ZStack {
                Color("WidgetBackground")
                
                // Subtle Decorative Blobs
                Circle()
                    .fill(brandColor.opacity(0.04))
                    .frame(width: 160, height: 160)
                    .offset(x: 50, y: -60)
                
                Circle()
                    .fill(brandColor.opacity(0.06))
                    .frame(width: 100, height: 100)
                    .offset(x: 70, y: 10)
            }
        }
    }
}

struct CompactTaskRow: View {
    let task: DDLItem
    
    private var brandColor: Color {
        Color(red: 1.0, green: 0.427, blue: 0.427) // #FF6D6D
    }
    
    var body: some View {
        HStack(spacing: 6) {
            // Priority Indicator
            RoundedRectangle(cornerRadius: 1.5)
                .fill(isUrgent(task) ? brandColor : Color.primary.opacity(0.15))
                .frame(width: 2.5, height: 12)
            
            Text(task.name)
                .font(.system(size: 11, weight: isUrgent(task) ? .semibold : .medium))
                .lineLimit(1)
            
            Spacer()
            
            Text(remainingTimeStr(task: task))
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(isUrgent(task) ? brandColor : .secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isUrgent(task) ? brandColor.opacity(0.05) : Color.primary.opacity(0.03))
        )
    }
    
    private func isUrgent(_ task: DDLItem) -> Bool {
        guard let endDate = DeadlineDateParser.safeParseOptional(task.endTime) else { return false }
        return endDate.timeIntervalSinceNow < 24 * 3600
    }
}

struct MediumHomeWidgetView: View {
    let entry: DeadlinerEntry
    var body: some View {
        if let task = entry.task {
            VStack(alignment: .leading, spacing: 6) {
                Text(task.name).font(.title3.bold()).lineLimit(1)
                Text(remainingTimeStr(task: task)).font(.subheadline).foregroundStyle(.secondary)
                LinearProgressView(value: calculateProgress(task: task), shape: Capsule())
                    .frame(height: 8)
                    .tint(.primary)
            }
            .containerBackground(.fill.tertiary, for: .widget)
        } else {
            Text("暂无任务")
                .containerBackground(.fill.tertiary, for: .widget)
        }
    }
}

// MARK: - Helper Functions

private func isWithin12Hours(task: DDLItem) -> Bool {
    guard let endDate = DeadlineDateParser.safeParseOptional(task.endTime) else { return false }
    return endDate.timeIntervalSinceNow < 12 * 3600
}

private func remainingTimeStr(task: DDLItem) -> String {
    guard let endDate = DeadlineDateParser.safeParseOptional(task.endTime) else { return "" }
    let diff = endDate.timeIntervalSinceNow
    if diff < 0 { return "0m" }
    let hours = Int(diff / 3600)
    if hours >= 24 { return "\(hours / 24)d" }
    else if hours >= 1 { return "\(hours)h" }
    else { return "\(max(0, Int(diff/60)))m" }
}

private func calculateProgress(task: DDLItem) -> Double {
    if task.type == .habit { return task.progress }
    guard let start = DeadlineDateParser.safeParseOptional(task.startTime),
          let end = DeadlineDateParser.safeParseOptional(task.endTime) else { return 0 }
    let total = end.timeIntervalSince(start)
    guard total > 0 else { return 1.0 }
    return max(0, min(Date().timeIntervalSince(start) / total, 1.0))
}

// MARK: - Widget Configuration

@main
struct DeadlinerWidget: Widget {
    let kind: String = "DeadlinerWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DeadlinerWidgetProvider()) { entry in
            DeadlinerWidgetEntryView(entry: entry)
        }
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .systemSmall, .systemMedium])
    }
}
