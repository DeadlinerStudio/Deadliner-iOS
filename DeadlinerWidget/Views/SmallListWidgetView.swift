import SwiftUI
import WidgetKit

struct SmallListWidgetView: View {
    let entry: DeadlinerEntry

    private var accent: Color {
        Color.accentColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Deadliner")
                        .font(.system(size: 12, weight: .bold))
                    Text(entry.topTasks.isEmpty ? "今天很干净" : "最近截止")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(entry.remainingCount)")
                        .font(.system(size: 18, weight: .heavy, design: .monospaced))
                    Text("active")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            if entry.topTasks.isEmpty {
                Spacer()
                VStack(alignment: .center, spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(accent.opacity(0.5))
                    Text("暂无待办任务")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                VStack(spacing: 6) {
                    ForEach(entry.topTasks.prefix(3)) { task in
                        CompactTaskRow(task: task)
                    }
                }
            }

            HStack {
                Label("\(entry.urgentCount)", systemImage: "flame.fill")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(entry.urgentCount > 0 ? .orange : .secondary)

                Spacer()

                Text("24h 内")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .containerBackground(for: .widget) {
            ZStack {
                Color("WidgetBackground")

                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(accent.opacity(0.08), lineWidth: 1)

                Circle()
                    .fill(accent.opacity(0.05))
                    .frame(width: 140, height: 140)
                    .offset(x: 60, y: -70)
            }
        }
    }
}
