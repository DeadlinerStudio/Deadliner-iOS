import SwiftUI

struct CompactTaskRow: View {
    let task: DDLItem

    private var brandColor: Color {
        Color(red: 1.0, green: 0.427, blue: 0.427)
    }

    var body: some View {
        HStack(spacing: 6) {
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
