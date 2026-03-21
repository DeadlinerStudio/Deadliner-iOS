import SwiftUI
import WidgetKit

struct DeadlinerListWidget: Widget {
    let kind: String = "DeadlinerListWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DeadlinerWidgetProvider()) { entry in
            SmallListWidgetView(entry: entry)
        }
        .configurationDisplayName("任务列表")
        .description("用紧凑列表查看最近几项截止任务。")
        .contentMarginsDisabled()
        .supportedFamilies([.systemSmall])
    }
}
