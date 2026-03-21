import SwiftUI
import WidgetKit

struct SmallHomeWidgetView: View {
    let entry: DeadlinerEntry

    private var statusStyle: SmallWidgetStatusStyle {
        SmallWidgetStatusStyle.from(entry.task)
    }

    private var titleText: String {
        entry.task?.name ?? "全部搞定"
    }

    private var timeValueText: String {
        entry.task.map(approximateRemainingTimeText(task:)) ?? "已清空"
    }

    private var countBadgeText: String {
        if entry.remainingCount <= 0 {
            return "0"
        }

        if entry.urgentCount > 0 {
            return "\(entry.urgentCount)/\(entry.remainingCount)"
        }

        return "\(entry.remainingCount)"
    }

    private var bottomStatusText: String {
        guard entry.task != nil else { return "今日清空" }

        switch statusStyle.status {
        case .passed:
            return "已逾期"
        case .near:
            return "紧急"
        case .completed:
            return "完成"
        case .undergo:
            return "进行中"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                Text(titleText)
                    .font(.system(size: 24, weight: .black))
                    .tracking(-0.25)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(10)

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 3) {
                    Text(timeValueText)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(.primary)
                        .minimumScaleFactor(0.9)
                        .lineLimit(1)

                    Text(bottomStatusText)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(statusStyle.indicator.opacity(0.95))
                        .lineLimit(1)

                    Text(countBadgeText)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.12), in: Capsule())
                        .overlay {
                            Capsule()
                                .stroke(.white.opacity(0.18), lineWidth: 1)
                        }
                        .foregroundStyle(.primary.opacity(0.92))
                        .padding(.top, 4)
                }
            }
            .padding(.top, 8)

            ZStack {
                Capsule(style: .continuous)
                    .fill(.black.opacity(0.10))
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(.white.opacity(0.32), lineWidth: 1)
                    }

                GeometryReader { geo in
                    ZStack(alignment: .bottom) {
                        Capsule(style: .continuous)
                            .fill(.clear)

                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        statusStyle.indicator.opacity(0.52),
                                        statusStyle.indicator
                                    ],
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                            )
                            .frame(height: max(geo.size.height * 0.18, geo.size.height * statusStyle.progress))
                            .shadow(color: statusStyle.indicator.opacity(0.18), radius: 10, y: 2)
                    }
                }
                .padding(4)

                Circle()
                    .fill(.white.opacity(0.72))
                    .frame(width: 7, height: 7)
                    .offset(y: -54)
                    .opacity(statusStyle.progress > 0.2 ? 1 : 0)
            }
            .padding(.top, 4)
            .frame(width: 30, height: 140)
        }
        .padding(16)
        .containerBackground(for: .widget) {
            ZStack {
                statusStyle.background

                LinearGradient(
                    colors: [
                        .white.opacity(0.10),
                        .clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Circle()
                    .fill(.white.opacity(0.08))
                    .frame(width: 126, height: 126)
                    .offset(x: 72, y: -58)

                Circle()
                    .fill(statusStyle.indicator.opacity(0.08))
                    .frame(width: 166, height: 166)
                    .offset(x: 88, y: 78)
            }
        }
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

private enum SmallWidgetStatus {
    case undergo
    case near
    case passed
    case completed
}

private struct SmallWidgetStatusStyle {
    let status: SmallWidgetStatus
    let indicator: Color
    let background: Color
    let progress: CGFloat

    static func from(_ task: DDLItem?) -> SmallWidgetStatusStyle {
        guard let task else {
            return .init(
                status: .completed,
                indicator: .green.opacity(0.72),
                background: .green.opacity(0.16),
                progress: 1
            )
        }

        let progress = CGFloat(calculateProgress(task: task))

        guard let endDate = DeadlineDateParser.safeParseOptional(task.endTime) else {
            return .init(
                status: .undergo,
                indicator: .accentColor.opacity(0.74),
                background: Color.accentColor.opacity(0.20),
                progress: progress
            )
        }

        if task.isCompleted {
            return .init(
                status: .completed,
                indicator: .green.opacity(0.72),
                background: .green.opacity(0.16),
                progress: 1
            )
        } else if endDate.timeIntervalSinceNow <= 0 {
            return .init(
                status: .passed,
                indicator: .red.opacity(0.84),
                background: .red.opacity(0.20),
                progress: 1
            )
        } else if endDate.timeIntervalSinceNow < 24 * 3600 {
            return .init(
                status: .near,
                indicator: .orange.opacity(0.86),
                background: .orange.opacity(0.20),
                progress: progress
            )
        } else {
            return .init(
                status: .undergo,
                indicator: .accentColor.opacity(0.76),
                background: Color.accentColor.opacity(0.20),
                progress: progress
            )
        }
    }
}
