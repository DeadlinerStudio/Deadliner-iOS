//
//  DeadlinerApp.swift
//  Deadliner
//
//  Created by Aritx 音唯 on 2026/2/13.
//

import SwiftUI
import SwiftData

@main
struct DeadlinerApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("selectedAppIcon") private var selectedAppIconRaw: String = DeadlinerIcon.deadlinerDefault.rawValue
    @AppStorage("userTier") private var userTier: UserTier = .free
    
    let sharedModelContainer: ModelContainer = SharedModelContainer.shared

    var body: some Scene {
        WindowGroup {
            MainView()
                .task {
                    #if DEBUG
                    userTier = .geek
                    #endif

                    // 请求通知权限
                    NotificationManager.shared.requestAuthorization()
                    
                    // 刷新习惯提醒
                    HabitRepository.shared.scheduleReminderRefresh()
                    
                    do {
                        try await TaskRepository.shared.initializeIfNeeded(container: sharedModelContainer)
                        await DeadlinerCoreBridge.shared.initializeIfNeeded()
                    } catch {
                        assertionFailure("DB init failed: \(error)")
                    }
                }
                .onAppear {
                    // 启动时也跑一次（有时不会立刻触发 scenePhase 变化）
                    applyAutoSeasonIconIfNeeded()
                    HabitRepository.shared.scheduleReminderRefresh()
                }
                .onChange(of: scenePhase) { phase in
                    // 回到前台时刷新一次即可
                    guard phase == .active else { return }
                    applyAutoSeasonIconIfNeeded()
                    HabitRepository.shared.scheduleReminderRefresh()
                }

            
        }
        .modelContainer(sharedModelContainer)
    }
    
    private func applyAutoSeasonIconIfNeeded() {
        guard UIApplication.shared.supportsAlternateIcons else { return }

        let selected = DeadlinerIcon(rawValue: selectedAppIconRaw) ?? .deadlinerDefault
        guard selected == .autoSeason else { return }

        // 目标：当前季节对应的图标
        let s = SeasonUtils.season(for: Date())
        let target = {
            switch s {
            case .spring: return DeadlinerIcon.spring
            case .summer: return DeadlinerIcon.summer
            case .autumn: return DeadlinerIcon.autumn
            case .winter: return DeadlinerIcon.winter
            }
        }()
        let targetName = target.alternateIconName

        // 当前系统图标
        let currentName = UIApplication.shared.alternateIconName
        let currentIcon: DeadlinerIcon = {
            if currentName == nil { return .deadlinerDefault }
            return DeadlinerIcon(rawValue: currentName!) ?? .deadlinerDefault
        }()

        // 已经是目标则不重复调用
        guard currentIcon != target else { return }

        UIApplication.shared.setAlternateIconName(targetName, completionHandler: nil)
    }

}
