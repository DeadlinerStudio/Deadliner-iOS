//
//  DeadlinerWidgetBundle.swift
//  DeadlinerWidget
//
//  Created by Aritx 音唯 on 2026/3/6.
//
import SwiftUI
import WidgetKit

@main
struct DeadlinerWidgetBundle: WidgetBundle {
    var body: some Widget {
        DeadlinerWidget()
        DeadlinerListWidget()
        DeadlinerWidgetControl()
        DeadlinerLifiAIControl()
        DeadlinerInspirationControl()
        DeadlinerTaskStatusControl()
        DeadlinerWidgetLiveActivity()
    }
}
