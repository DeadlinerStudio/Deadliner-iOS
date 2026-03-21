import SwiftUI
import WidgetKit

struct MediumHomeWidgetView: View {
    let entry: DeadlinerEntry

    var body: some View {
        if let task = entry.task {
            VStack(alignment: .leading, spacing: 6) {
                Text(task.name)
                    .font(.title3.bold())
                    .lineLimit(1)
                Text(remainingTimeStr(task: task))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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
