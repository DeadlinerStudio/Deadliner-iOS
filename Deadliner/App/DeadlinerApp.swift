//
//  DeadlinerApp.swift
//  Deadliner
//
//  Created by Aritx 音唯 on 2026/2/13.
//

import SwiftUI
import WidgetKit

private enum AppReleaseGate {
    static let unlockGeekForCurrentRelease = false
}

@MainActor
private final class DeadlinerWidgetRefreshCoordinator {
    static let shared = DeadlinerWidgetRefreshCoordinator()

    private var pendingRefresh: _Concurrency.Task<Void, Never>?

    func requestUpdate() {
        pendingRefresh?.cancel()
        pendingRefresh = _Concurrency.Task { @MainActor in
            do {
                try await _Concurrency.Task.sleep(nanoseconds: 150_000_000)
            } catch {
                return
            }
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}

private extension Notification.Name {
    static let deadlinerWidgetUpdateRequested = Notification.Name(
        "com.aritxonly.deadliner.widget-update-requested"
    )
}

@main
struct DeadlinerApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("selectedAppIcon") private var selectedAppIconRaw: String = DeadlinerIcon.deadlinerDefault.rawValue
    @AppStorage("userTier") private var userTier: UserTier = .free
    @StateObject private var themeStore = ThemeStore()
    
    init() {
        // Persist structured diagnostic records across launches in the shared
        // App Group, with bounded 14-day / 8 MiB retention.
        AppLog.beginSession()
        #if canImport(Shared)
        // Install the notification delegate before asynchronous Core initialization.
        _ = FocusAlarmPortAdapter.shared
        _ = FocusTimerPresentationModel.shared
        #endif

        // Capture process stdout/stderr and mirror it to the unified log file.
        AppStdStreamCapture.shared.startIfNeeded()
        AppLog.event("app.launch", domain: .lifecycle)
        do {
            try KMPSharedDatabaseBootstrap.prepareIfNeeded()
        } catch {
            SyncDebugLog.log("[KMP] Shared database bootstrap failed: \(error.localizedDescription)")
        }
        PhoneWatchSyncBridge.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(themeStore)
                .task {
                    do {
                        try await KMPLifiCoreBridge.shared.initializeIfNeeded()
                        await CaptureStore.shared.ensureKMPMigration()
                    } catch {
                        AILog.log("Core init failed on launch task: \(error.localizedDescription)")
                        SyncDebugLog.log("Core init failed on launch task: \(error.localizedDescription)")
                        assertionFailure("DB init failed: \(error)")
                    }

                    if AppReleaseGate.unlockGeekForCurrentRelease {
                        userTier = .geek
                    } else if userTier == .pro {
                        userTier = .geek
                    }

                    // 请求通知权限
                    NotificationManager.shared.requestAuthorization()

                    // 启动时自动校验一次会员权益（先本地，后限时网络），弱网不阻塞体验
                    await StoreManager.shared.refreshEntitlementsOnLaunch()
                    
                    await KMPTaskReminderScheduler.shared.scheduleRefresh()
                    await KMPHabitReminderScheduler.shared.scheduleRefresh()
                    await PhoneWatchSyncBridge.shared.pushLatestSnapshot(reason: "launchTask")
                    await SyncCoordinator.shared.configureAutomaticSync()
                }
                .onAppear {
                    // 启动时也跑一次（有时不会立刻触发 scenePhase 变化）
                    DeadlinerWidgetRefreshCoordinator.shared.requestUpdate()
                    applyAutoSeasonIconIfNeeded()
                    Task {
                        do {
                            try await KMPLifiCoreBridge.shared.initializeIfNeeded()
                            await KMPTaskReminderScheduler.shared.scheduleRefresh()
                            await KMPHabitReminderScheduler.shared.scheduleRefresh()
                            await PhoneWatchSyncBridge.shared.pushLatestSnapshot(reason: "onAppear")
                        } catch {
                            AILog.log("Core init failed on appear: \(error.localizedDescription)")
                            SyncDebugLog.log("Core init failed on appear: \(error.localizedDescription)")
                            assertionFailure("DB init failed on appear: \(error)")
                        }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .deadlinerWidgetUpdateRequested)) { _ in
                    DeadlinerWidgetRefreshCoordinator.shared.requestUpdate()
                }
                .onChange(of: scenePhase) { phase in
                    // 回到前台时刷新一次即可
                    guard phase == .active else { return }
                    DeadlinerWidgetRefreshCoordinator.shared.requestUpdate()
                    applyAutoSeasonIconIfNeeded()
                    Task { await StoreManager.shared.refreshEntitlementsOnLaunch() }
                    Task {
                        do {
                            try await KMPLifiCoreBridge.shared.initializeIfNeeded()
                            await KMPTaskReminderScheduler.shared.scheduleRefresh()
                            await KMPHabitReminderScheduler.shared.scheduleRefresh()
                            await PhoneWatchSyncBridge.shared.pushLatestSnapshot(reason: "sceneActive")
                            await SyncCoordinator.shared.configureAutomaticSync()
                        } catch {
                            AILog.log("Core init failed on active: \(error.localizedDescription)")
                            SyncDebugLog.log("Core init failed on active: \(error.localizedDescription)")
                            assertionFailure("DB init failed on active: \(error)")
                        }
                    }
                }

            
        }
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
