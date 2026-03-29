//
//  BehaviorAndDisplayView.swift
//  Deadliner
//
//  Created by Aritx 音唯 on 2026/2/21.
//

import SwiftUI

struct BehaviorAndDisplayView: View {
    @EnvironmentObject private var themeStore: ThemeStore

    @State private var autoArchiveDays = 7
    
    @State private var progressDir = false
    
    // 未来可以加的占位变量：
    // @State private var defaultHomePage = 0
    // @State private var showCompletedTasks = true

    var body: some View {
        Form {
            Section("界面显示") {
                Toggle("主界面正向进度条", isOn: $progressDir)
                    
            }
            
            Section("任务归档与清理") {
                Stepper(value: $autoArchiveDays, in: 0...365) {
                    HStack {
                        Text("完成任务归档天数")
                        Spacer()
                        Text(autoArchiveDays == 0 ? "已关闭" : "\(autoArchiveDays) 天")
                            .foregroundStyle(.secondary)
                    }
                }
                
                Text(autoArchiveDays == 0
                     ? "任务完成后将一直留在主列表中。"
                     : "任务完成后 \(autoArchiveDays) 天，将自动移入归档区。")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("行为与交互")
        .navigationBarTitleDisplayMode(.inline)
        .optionalTint(themeStore.switchTint)
        .task {
            autoArchiveDays = await LocalValues.shared.getAutoArchiveDays()
            progressDir = await LocalValues.shared.getProgressDir()
        }
        .onChange(of: autoArchiveDays) { newValue in
            Task { await LocalValues.shared.setAutoArchiveDays(newValue) }
        }
        .onChange(of: progressDir) { newValue in
            Task { await LocalValues.shared.setProgressDir(newValue) }
        }
    }

    private func settingsLabel(_ title: String, systemImage: String, palette: SettingsIconPalette) -> some View {
        SettingsListLabel(title: title, systemImage: systemImage, palette: palette, style: .detail)
    }
}
