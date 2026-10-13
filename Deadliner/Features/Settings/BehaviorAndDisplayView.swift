//
//  BehaviorAndDisplayView.swift
//  Deadliner
//
//  Created by Aritx 音唯 on 2026/2/21.
//

import SwiftUI

struct BehaviorAndDisplayView: View {
    @EnvironmentObject private var themeStore: ThemeStore
    @AppStorage(ScrollEdgeEffectPreference.useSystemImmersiveKey)
    private var useSystemImmersive: Bool = ScrollEdgeEffectPreference.defaultUseSystemImmersive

    @AppStorage("quick_add_enabled") private var quickAddEnabled = false
    @State private var autoArchiveDays = 7
    @State private var tombstoneRetentionDays = 30
    
    @State private var progressDir = false
    // 未来可以加的占位变量：
    // @State private var defaultHomePage = 0
    // @State private var showCompletedTasks = true

    var body: some View {
        Form {
            Section("添加") {
                Toggle("启用快速添加", isOn: $quickAddEnabled)
                Text("输入一句话，实时预览任务或习惯；随时展开完整表单。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("界面显示") {
                Toggle("主界面正向进度条", isOn: $progressDir)
                Toggle("使用系统沉浸", isOn: $useSystemImmersive)

                Text("打开后，未强制沉浸的页面会改用系统推荐的 automatic 滚动边缘效果。当前先用于灵感页。")
                    .font(.footnote)
                    .foregroundColor(.secondary)
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

                Stepper(value: $tombstoneRetentionDays, in: 0...365) {
                    HStack {
                        Text("已删除记录保留天数")
                        Spacer()
                        Text(tombstoneRetentionDays == 0 ? "不自动清理" : "\(tombstoneRetentionDays) 天")
                            .foregroundStyle(.secondary)
                    }
                }

                Text(tombstoneRetentionDays == 0
                     ? "删除墓碑将持续保留，适合极端保守的多设备同步。"
                     : "删除后的同步墓碑保留 \(tombstoneRetentionDays) 天，之后会自动回收，减少 snapshot 体积和垃圾数据堆积。")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .deadlinerScrollEdgeEffect(forceImmersive: false)
        .deadlinerContainerSystemBackground()
        .navigationTitle("行为与交互")
        .navigationBarTitleDisplayMode(.inline)
        .optionalTint(themeStore.switchTint)
        .task {
            autoArchiveDays = await LocalValues.shared.getAutoArchiveDays()
            tombstoneRetentionDays = await LocalValues.shared.getTombstoneRetentionDays()
            progressDir = await LocalValues.shared.getProgressDir()
        }
        .onChange(of: autoArchiveDays) { newValue in
            Task { await LocalValues.shared.setAutoArchiveDays(newValue) }
        }
        .onChange(of: tombstoneRetentionDays) { newValue in
            Task { await LocalValues.shared.setTombstoneRetentionDays(newValue) }
        }
        .onChange(of: progressDir) { newValue in
            Task { await LocalValues.shared.setProgressDir(newValue) }
        }
    }

    private func settingsLabel(_ title: String, systemImage: String, palette: SettingsIconPalette) -> some View {
        SettingsListLabel(title: title, systemImage: systemImage, palette: palette, style: .detail)
    }
}
