import SwiftUI
import WidgetKit

struct MediumHomeWidgetView: View {
    let entry: DeadlinerEntry

    private var heroTask: DDLItem? { entry.task }
    private var style: MediumWidgetStatusStyle { .from(entry.task) }
    private var trailingTasks: [DDLItem] { Array(entry.topTasks.dropFirst().prefix(3)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            topSection
            Divider().overlay(.white.opacity(0.14))
            bottomSection
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 32)
        .containerBackground(for: .widget) {
            ZStack {
                Color("WidgetBackground")

                LinearGradient(
                    colors: [style.indicator.opacity(0.10), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Circle()
                    .fill(style.indicator.opacity(0.06))
                    .frame(width: 190, height: 190)
                    .offset(x: 112, y: -76)

                Circle()
                    .fill(.white.opacity(0.07))
                    .frame(width: 150, height: 150)
                    .offset(x: 132, y: 70)
            }
        }
    }

    private var topSection: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 8) {
                    Text(headerLabel)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(style.indicator)

                    Spacer(minLength: 8)

                    Text(headerBadge)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.22), in: Capsule())
                }

                Spacer(minLength: 10)

                Text(heroTask?.name ?? "全部搞定")
                    .font(.system(size: 23, weight: .black))
                    .tracking(-0.35)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 8)

                Text(heroSubtext)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.56))
                    .lineLimit(1)

                Spacer(minLength: 12)

                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(.black.opacity(0.08))
                        .frame(height: 8)

                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [style.indicator.opacity(0.45), style.indicator],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(32, 168 * style.progress), height: 8)
                }
            }

            VStack(spacing: 10) {
                metricCard(title: "剩余时间", value: heroTimeText, accent: style.indicator)
                HStack(spacing: 8) {
                    metricCard(title: "进行中", value: "\(entry.remainingCount)", accent: .primary, compact: true)
                    metricCard(title: "紧急", value: "\(entry.urgentCount)", accent: style.indicator, compact: true)
                }
            }
            .frame(width: 112)
        }
    }

    private var bottomSection: some View {
        HStack(alignment: .top, spacing: 8) {
            if trailingTasks.isEmpty {
                emptyBottomCard
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(Array(trailingTasks.prefix(2).enumerated()), id: \.element.id) { index, task in
                    MediumDeadlineCard(task: task, emphasized: index == 0)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func metricCard(title: String, value: String, accent: Color, compact: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: compact ? 8 : 9, weight: .bold))
                .foregroundStyle(.primary.opacity(0.44))
                .lineLimit(1)

            Spacer(minLength: compact ? 6 : 8)

            Text(value)
                .font(.system(size: compact ? 15 : 16, weight: .black, design: .monospaced))
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, compact ? 9 : 10)
        .padding(.vertical, compact ? 9 : 10)
        .frame(maxWidth: .infinity, minHeight: compact ? 46 : 58, alignment: .topLeading)
        .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var headerLabel: String {
        guard heroTask != nil else { return "今日清空" }
        switch style.status {
        case .passed: return "已逾期"
        case .near: return "即将截止"
        case .completed: return "已完成"
        case .undergo: return "最近截止"
        }
    }

    private var headerBadge: String {
        if entry.remainingCount <= 0 { return "0" }
        if entry.urgentCount > 0 { return "\(entry.urgentCount)/\(entry.remainingCount)" }
        return "\(entry.remainingCount)"
    }

    private var heroSubtext: String {
        guard let heroTask else { return "今天可以安心休息一下" }
        let note = heroTask.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty { return note }
        return footerStatusText
    }

    private var heroTimeText: String {
        guard let heroTask else { return "已清空" }
        return approximateRemainingTimeText(task: heroTask)
    }

    private var footerStatusText: String {
        switch style.status {
        case .passed: return "已逾期"
        case .near: return "紧急"
        case .completed: return "完成"
        case .undergo: return "进行中"
        }
    }

    private var emptyBottomCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("接下来")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)

            Text("没有后续任务")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.primary.opacity(0.72))

            Text("今天可以轻松一点")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.primary.opacity(0.46))
        }
        .padding(12)
        .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct MediumDeadlineCard: View {
    let task: DDLItem
    var emphasized: Bool = false

    private var style: MediumWidgetStatusStyle { .from(task) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text(emphasized ? "临近任务" : "接续任务")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                Text(approximateRemainingTimeText(task: task))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(style.indicator)
            }

            Spacer(minLength: 8)

            Text(task.name)
                .font(.system(size: 12, weight: .bold))
                .lineLimit(2)

            Spacer(minLength: 10)

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(.black.opacity(0.08))
                    .frame(height: 6)

                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [style.indicator.opacity(0.42), style.indicator],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(20, 110 * style.progress), height: 6)
            }
        }
        .padding(12)
        .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private func approximateRemainingTimeText(task: DDLItem) -> String {
    guard let endDate = DeadlineDateParser.safeParseOptional(task.endTime) else { return "时间未知" }

    let diff = endDate.timeIntervalSinceNow
    if diff <= 0 { return "约 0 分" }

    let minutes = Int(diff / 60)
    let hours = Int(diff / 3600)
    let days = Int(diff / 86400)

    if days >= 1 {
        return "约 \(days) 天"
    } else if hours >= 1 {
        return "约 \(hours) 时"
    } else {
        return "约 \(max(1, minutes)) 分"
    }
}

private enum MediumWidgetStatus {
    case undergo
    case near
    case passed
    case completed
}

private struct MediumWidgetStatusStyle {
    let status: MediumWidgetStatus
    let indicator: Color
    let background: Color
    let progress: CGFloat

    static func from(_ task: DDLItem?) -> MediumWidgetStatusStyle {
        guard let task else {
            return .init(
                status: .completed,
                indicator: .green.opacity(0.72),
                background: .green.opacity(0.14),
                progress: 1
            )
        }

        let progress = CGFloat(calculateProgress(task: task))

        guard let endDate = DeadlineDateParser.safeParseOptional(task.endTime) else {
            return .init(
                status: .undergo,
                indicator: .accentColor.opacity(0.78),
                background: Color.accentColor.opacity(0.16),
                progress: progress
            )
        }

        if task.isCompleted {
            return .init(
                status: .completed,
                indicator: .green.opacity(0.72),
                background: .green.opacity(0.14),
                progress: 1
            )
        } else if endDate.timeIntervalSinceNow <= 0 {
            return .init(
                status: .passed,
                indicator: .red.opacity(0.84),
                background: .red.opacity(0.16),
                progress: 1
            )
        } else if endDate.timeIntervalSinceNow < 24 * 3600 {
            return .init(
                status: .near,
                indicator: .orange.opacity(0.86),
                background: .orange.opacity(0.16),
                progress: progress
            )
        } else {
            return .init(
                status: .undergo,
                indicator: .accentColor.opacity(0.78),
                background: Color.accentColor.opacity(0.16),
                progress: progress
            )
        }
    }
}
