import SwiftUI
import WidgetKit

struct DeadlinerWidgetEntryView: View {
    var entry: DeadlinerWidgetProvider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            CircularWidgetView(entry: entry)
                .containerBackground(.clear, for: .widget)
        case .accessoryRectangular:
            if entry.task != nil {
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
