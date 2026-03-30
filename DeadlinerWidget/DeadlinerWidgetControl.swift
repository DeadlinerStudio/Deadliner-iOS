//
//  DeadlinerWidgetControl.swift
//  DeadlinerWidget
//
//  Created by Aritx 音唯 on 2026/3/6.
//

import AppIntents
import SwiftUI
import WidgetKit

struct DeadlinerWidgetControl: ControlWidget {
    static let kind: String = "com.aritxonly.Deadliner.DeadlinerWidget"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenAddEntryIntent()) {
                Label("快速添加", systemImage: "plus.circle")
            }
        }
        .displayName("快速添加")
        .description("点击后直接打开 Deadliner 的添加页。")
    }
}
