import SwiftUI

struct RectangularWidgetView: View {
    let entry: DeadlinerEntry

    var body: some View {
        if let task = entry.task {
            let isClose = isWithin12Hours(task: task)

            VStack(alignment: .leading, spacing: 0) {
                Text(task.name)
                    .font(.system(size: isClose ? 15 : 13, weight: .medium))
                    .lineLimit(1)

                Spacer(minLength: 2)

                if isClose {
                    Text(remainingTimeStr(task: task) + " rem.")
                        .font(.system(size: 22, weight: .heavy).monospaced())
                        .padding(.bottom, 4)
                } else {
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
