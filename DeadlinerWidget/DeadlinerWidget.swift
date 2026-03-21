//
//  DeadlinerWidget.swift
//  Deadliner
//

import SwiftUI
import WidgetKit

struct DeadlinerWidget: Widget {
    let kind: String = "DeadlinerWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DeadlinerWidgetProvider()) { entry in
            DeadlinerWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("焦点卡片")
        .description("像首页一样，聚焦当前最重要的一项截止任务。")
        .contentMarginsDisabled()
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .systemSmall, .systemMedium])
    }
}
