import SwiftUI
import WidgetKit

struct SmallListWidgetView: View {
    @Environment(\.colorScheme) private var colorScheme

    let entry: DeadlinerEntry

    private var style: SmallListWidgetStyle {
        SmallListWidgetStyle.from(entry: entry, colorScheme: colorScheme)
    }

    private var totalCountText: String {
        "\(entry.remainingCount)"
    }

    private var displayedTasks: ArraySlice<DDLItem> {
        relevantTasks.prefix(3)
    }

    private var displayedTasksArray: [DDLItem] {
        Array(displayedTasks)
    }

    private var badgeTextColor: Color {
        if hasOverdueTasks {
            return .red.opacity(0.84)
        }

        if hasNearTasks {
            return .orange.opacity(0.86)
        }

        return style.brand
    }

    private var hasOverdueTasks: Bool {
        relevantTasks.contains { task in
            guard !task.isCompleted,
                  let endDate = DeadlineDateParser.safeParseOptional(task.endTime) else {
                return false
            }
            return endDate.timeIntervalSinceNow <= 0
        }
    }

    private var hasNearTasks: Bool {
        relevantTasks.contains { task in
            guard !task.isCompleted,
                  let endDate = DeadlineDateParser.safeParseOptional(task.endTime) else {
                return false
            }
            let remaining = endDate.timeIntervalSinceNow
            return remaining > 0 && remaining < 24 * 3600
        }
    }

    private var relevantTasks: [DDLItem] {
        var tasks = entry.topTasks
        if let task = entry.task, tasks.contains(where: { $0.id == task.id }) == false {
            tasks.insert(task, at: 0)
        }
        return tasks
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if displayedTasks.isEmpty {
                emptyState
            } else {
                taskList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 0)
        .padding(.vertical, 0)
        .containerBackground(for: .widget) {
            ZStack {
                style.baseBackground

                style.tintBackground

                LinearGradient(
                    colors: [
                        style.backgroundGlow,
                        .clear,
                        .clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                RadialGradient(
                    colors: [
                        style.backgroundHighlight,
                        .clear,
                        .clear
                    ],
                    center: .topTrailing,
                    startRadius: 10,
                    endRadius: 124
                )
                .offset(x: 20, y: -18)

                SmallListWidgetRippleDecor(style: style)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("Deadliner")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(style.primaryText)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            if entry.remainingCount > 0 {
                Text(totalCountText)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(badgeTextColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(style.badgeFill, in: Capsule(style: .continuous))
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(style.badgeStroke, lineWidth: 1)
                    }
            }
        }
        .padding(.bottom, 8)
    }

    private var taskList: some View {
        GeometryReader { proxy in
            let slotHeight = proxy.size.height / 3

            VStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { index in
                    taskSlot(at: index)
                        .frame(
                            maxWidth: .infinity,
                            minHeight: slotHeight,
                            maxHeight: slotHeight,
                            alignment: .top
                        )
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func taskSlot(at index: Int) -> some View {
        if index < displayedTasksArray.count {
            HarmonyCompactTaskRow(task: displayedTasksArray[index], style: style)
        } else {
            Color.clear
        }
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Text("🎉")
                .font(.system(size: 28))

            Text("全部搞定")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(style.primaryText.opacity(0.82))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SmallListWidgetRippleDecor: View {
    let style: SmallListWidgetStyle

    var body: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(style.isDark ? 0.016 : 0.10))
                .frame(width: 126, height: 126)
                .offset(x: 72, y: -58)

            Circle()
                .fill(style.decor.opacity(style.isDark ? 0.024 : 0.08))
                .frame(width: 166, height: 166)
                .offset(x: 88, y: 78)
        }
        .compositingGroup()
    }
}

private struct HarmonyCompactTaskRow: View {
    @Environment(\.widgetRenderingMode) private var renderingMode

    let task: DDLItem
    let style: SmallListWidgetStyle

    private enum RowStatus {
        case normal
        case near
        case overdue
    }

    private var rowStatus: RowStatus {
        guard !task.isCompleted,
              let endDate = DeadlineDateParser.safeParseOptional(task.endTime) else {
            return .normal
        }

        let remaining = endDate.timeIntervalSinceNow
        if remaining <= 0 {
            return .overdue
        }

        if remaining < 24 * 3600 {
            return .near
        }

        return .normal
    }

    private var emphasisColor: Color {
        switch rowStatus {
        case .overdue:
            return .red.opacity(0.84)
        case .near:
            return .orange.opacity(0.86)
        case .normal:
            return style.normalIndicator
        }
    }

    private var rowTint: Color {
        switch rowStatus {
        case .overdue:
            return .red.opacity(0.08)
        case .near:
            return .orange.opacity(0.08)
        case .normal:
            return style.rowFill
        }
    }

    private var rowBaseColor: Color {
        // Clear/tinted appearances map colors to system materials using alpha.
        // An opaque dark semantic fill becomes an opaque white tile in that mode.
        // Keep this independent of colorScheme (Clear can be light or dark).
        if renderingMode == .accented {
            return .white.opacity(0.07)
        }

        switch rowStatus {
        case .overdue:
            return style.isDark
                ? Color(red: 0.11, green: 0.035, blue: 0.045)
                : Color.white.opacity(0.72)
        case .near:
            return style.isDark
                ? Color(red: 0.115, green: 0.07, blue: 0.03)
                : Color.white.opacity(0.72)
        case .normal:
            return style.rowBaseFill
        }
    }

    private var rowHighlightColor: Color {
        switch rowStatus {
        case .overdue:
            return style.isDark ? .red.opacity(0.14) : .white.opacity(0.24)
        case .near:
            return style.isDark ? .orange.opacity(0.15) : .white.opacity(0.24)
        case .normal:
            return style.rowHighlight
        }
    }

    private var rowBorderColor: Color {
        switch rowStatus {
        case .normal:
            return style.rowStroke
        case .overdue, .near:
            return emphasisColor.opacity(style.isDark ? 0.28 : 0.20)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(emphasisColor)
                .frame(width: 3, height: 12)
                .padding(.trailing, 5)

            Text(task.name)
                .font(.system(size: 11.5, weight: rowStatus == .normal ? .medium : .semibold))
                .foregroundStyle(style.primaryText)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(remainingTimeStr(task: task, overdueText: "逾期"))
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .foregroundStyle(rowStatus == .normal ? style.secondaryText : emphasisColor)
                .lineLimit(1)
                .padding(.leading, 4)
        }
        .frame(height: 30)
        .padding(.leading, 4)
        .padding(.trailing, 5)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(rowBaseColor)
                .overlay {
                    LinearGradient(
                        colors: [
                            rowHighlightColor,
                            style.isDark ? .white.opacity(0.008) : .white.opacity(0.10),
                            .clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(rowTint)
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(rowBorderColor, lineWidth: 1)
        }
    }
}

private struct SmallListWidgetStyle {
    let isDark: Bool
    let baseBackground: Color
    let tintBackground: Color
    let backgroundGlow: Color
    let backgroundHighlight: Color
    let decor: Color
    let brand: Color
    let badgeFill: Color
    let badgeStroke: Color
    let normalIndicator: Color
    let rowBaseFill: Color
    let rowFill: Color
    let rowHighlight: Color
    let rowStroke: Color
    let primaryText: Color
    let secondaryText: Color

    static func from(entry: DeadlinerEntry, colorScheme: ColorScheme) -> SmallListWidgetStyle {
        let isDark = colorScheme == .dark
        let relevantTasks: [DDLItem] = {
            var tasks = entry.topTasks
            if let task = entry.task, tasks.contains(where: { $0.id == task.id }) == false {
                tasks.insert(task, at: 0)
            }
            return tasks
        }()

        let hasOverdueTasks = relevantTasks.contains { task in
            guard !task.isCompleted,
                  let endDate = DeadlineDateParser.safeParseOptional(task.endTime) else {
                return false
            }
            return endDate.timeIntervalSinceNow <= 0
        }

        let primaryText = isDark ? Color.white.opacity(0.95) : Color.primary.opacity(0.92)
        let secondaryText = isDark ? Color.white.opacity(0.68) : Color.primary.opacity(0.52)
        let badgeFill = isDark ? Color.white.opacity(0.042) : .black.opacity(0.06)
        let badgeStroke = isDark ? Color.white.opacity(0.09) : Color.white.opacity(0.16)
        let normalIndicator = isDark ? Color.accentColor.opacity(0.88) : Color.accentColor.opacity(0.90)
        let rowBaseFill = isDark ? Color.white.opacity(0.07) : Color.white.opacity(0.84)
        let rowStroke = isDark ? Color.white.opacity(0.08) : Color.white.opacity(0.74)
        let backgroundHighlight = isDark ? Color.white.opacity(0.026) : Color.white.opacity(0.32)
        let backgroundGlow = isDark ? Color.white.opacity(0.007) : Color.white.opacity(0.12)
        let baseBackground = isDark ? Color(red: 0.006, green: 0.008, blue: 0.012) : Color.white
        let normalRowHighlight = isDark
            ? .white.opacity(0.03)
            : Color.white.opacity(0.42)

        if entry.remainingCount == 0 {
            return .init(
                isDark: isDark,
                baseBackground: baseBackground,
                tintBackground: isDark ? .green.opacity(0.035) : .green.opacity(0.07),
                backgroundGlow: backgroundGlow,
                backgroundHighlight: backgroundHighlight,
                decor: .green,
                brand: isDark ? .green.opacity(0.92) : .green.opacity(0.82),
                badgeFill: badgeFill,
                badgeStroke: badgeStroke,
                normalIndicator: normalIndicator,
                rowBaseFill: rowBaseFill,
                rowFill: isDark ? .white.opacity(0.015) : .green.opacity(0.03),
                rowHighlight: normalRowHighlight,
                rowStroke: rowStroke,
                primaryText: primaryText,
                secondaryText: secondaryText
            )
        }

        if hasOverdueTasks {
            return .init(
                isDark: isDark,
                baseBackground: baseBackground,
                tintBackground: isDark ? .red.opacity(0.04) : .red.opacity(0.09),
                backgroundGlow: backgroundGlow,
                backgroundHighlight: backgroundHighlight,
                decor: .red,
                brand: isDark ? Color.white.opacity(0.94) : Color.accentColor.opacity(0.84),
                badgeFill: badgeFill,
                badgeStroke: badgeStroke,
                normalIndicator: normalIndicator,
                rowBaseFill: rowBaseFill,
                rowFill: isDark ? .red.opacity(0.03) : .red.opacity(0.03),
                rowHighlight: normalRowHighlight,
                rowStroke: rowStroke,
                primaryText: primaryText,
                secondaryText: secondaryText
            )
        }

        if entry.urgentCount > 0 {
            return .init(
                isDark: isDark,
                baseBackground: baseBackground,
                tintBackground: isDark ? .orange.opacity(0.04) : .orange.opacity(0.09),
                backgroundGlow: backgroundGlow,
                backgroundHighlight: backgroundHighlight,
                decor: .orange,
                brand: isDark ? Color.white.opacity(0.94) : Color.accentColor.opacity(0.84),
                badgeFill: badgeFill,
                badgeStroke: badgeStroke,
                normalIndicator: normalIndicator,
                rowBaseFill: rowBaseFill,
                rowFill: isDark ? .orange.opacity(0.03) : .orange.opacity(0.03),
                rowHighlight: normalRowHighlight,
                rowStroke: rowStroke,
                primaryText: primaryText,
                secondaryText: secondaryText
            )
        }

        let accent = Color.accentColor
        return .init(
            isDark: isDark,
            baseBackground: baseBackground,
            tintBackground: isDark ? accent.opacity(0.032) : accent.opacity(0.085),
            backgroundGlow: backgroundGlow,
            backgroundHighlight: backgroundHighlight,
            decor: accent,
            brand: isDark ? Color.white.opacity(0.94) : accent.opacity(0.90),
            badgeFill: badgeFill,
            badgeStroke: badgeStroke,
            normalIndicator: normalIndicator,
            rowBaseFill: rowBaseFill,
            rowFill: isDark ? .white.opacity(0.015) : accent.opacity(0.028),
            rowHighlight: normalRowHighlight,
            rowStroke: rowStroke,
            primaryText: primaryText,
            secondaryText: secondaryText
        )
    }
}
