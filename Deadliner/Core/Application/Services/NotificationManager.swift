//
//  NotificationManager.swift
//  Deadliner
//
//  Created by Gemini CLI on 2026/3/8.
//

import Foundation
import UserNotifications

#if canImport(Shared)
import Shared
#endif

class NotificationManager {
    static let shared = NotificationManager()
    
    private init() {}
    
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("✅ 通知权限已获取")
            } else if let error = error {
                print("❌ 通知权限获取失败: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Task Notifications
    
    func scheduleTaskNotification(for item: DDLItem) {
        // 先移除旧的通知
        cancelTaskNotification(for: item.id)
        
        // 只有未完成的任务才需要通知
        guard !item.isCompleted, !item.isArchived else { return }
        
        // 解析截止时间
        guard let endTime = DeadlineDateParser.safeParseOptional(item.endTime) else { return }
        
        // 计算触发时间 (截止前 12 小时)
        let triggerDate = endTime.addingTimeInterval(-12 * 3600)
        
        // 如果触发时间已经过了，就不发了
        guard triggerDate > Date() else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "任务即将到期"
        content.body = "任务「\(item.name)」还有 12 小时截止，请抓紧完成！"
        content.sound = .default
        
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        
        let request = UNNotificationRequest(
            identifier: taskIdentifier(for: item.id),
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ 无法添加任务通知: \(error.localizedDescription)")
            }
        }
    }
    
    func cancelTaskNotification(for itemId: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [taskIdentifier(for: itemId)])
    }
    
    private func taskIdentifier(for id: String) -> String {
        return "TASK_\(id)"
    }

    #if canImport(Shared)
    func scheduleKMPTaskNotification(for task: Task_) {
        cancelKMPTaskNotification(uid: task.uid)

        guard task.state == .active,
              let dueAt = task.dueAt,
              let dueDate = DeadlineDateParser.safeParseOptional(dueAt)
        else { return }

        let triggerDate = dueDate.addingTimeInterval(-12 * 3600)
        guard triggerDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "任务即将到期"
        content.body = "任务「\(task.title)」还有 12 小时截止，请抓紧完成！"
        content.sound = .default

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: kmpTaskIdentifier(for: task.uid),
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("❌ 无法添加 KMP 任务通知: \(error.localizedDescription)")
            }
        }
    }

    func cancelKMPTaskNotification(uid: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [kmpTaskIdentifier(for: uid)]
        )
    }

    func cancelAllKMPTaskNotifications() {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let identifiers = requests
                .filter { $0.identifier.hasPrefix("KMP_TASK_") }
                .map(\.identifier)
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
        }
    }

    func cancelAllLegacyTaskNotifications() {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let identifiers = requests
                .filter { $0.identifier.hasPrefix("TASK_") }
                .map(\.identifier)
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
        }
    }

    private func kmpTaskIdentifier(for uid: String) -> String {
        "KMP_TASK_\(uid)"
    }
    #endif
    
    // MARK: - Habit Notifications
    
    func scheduleHabitInstance(id: Int64, name: String, date: Date) {
        // 如果时间已经过了，直接跳过
        guard date > Date() else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "习惯打卡提醒"
        content.body = "是时候完成「\(name)」啦！"
        content.sound = .default
        
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        
        // 标识符包含日期，以便为同一个习惯调度多天的通知
        let dateKey = String(format: "%04d%02d%02d", components.year!, components.month!, components.day!)
        let identifier = "HABIT_\(id)_\(dateKey)"
        
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request)
    }

    func scheduleKMPHabitInstance(uid: String, name: String, date: Date) {
        guard date > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "习惯打卡提醒"
        content.body = "是时候完成「\(name)」啦！"
        content.sound = .default

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let dateKey = String(format: "%04d%02d%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
        let request = UNNotificationRequest(
            identifier: "KMP_HABIT_\(uid)_\(dateKey)",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }
    
    func cancelAllHabitNotifications() {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let habitIds = requests
                .filter { $0.identifier.hasPrefix("HABIT_") }
                .map { $0.identifier }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: habitIds)
        }
    }

    func cancelAllKMPHabitNotifications() async {
        let center = UNUserNotificationCenter.current()
        let requests = await center.pendingNotificationRequests()
        let identifiers = requests
            .filter { $0.identifier.hasPrefix("KMP_HABIT_") }
            .map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
    
    func cancelHabitNotifications(for habitId: Int64) {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let ids = requests
                .filter { $0.identifier.hasPrefix("HABIT_\(habitId)_") }
                .map { $0.identifier }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        }
    }
    
    private func habitIdentifier(for id: Int64) -> String {
        return "HABIT_\(id)"
    }
    
    // MARK: - Utility
    
    func cancelAllNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
    
    func refreshAllTaskNotifications(tasks: [DDLItem]) {
        // 取消所有任务通知并重新添加
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let taskIds = requests
                .filter { $0.identifier.hasPrefix("TASK_") }
                .map { $0.identifier }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: taskIds)
            
            for task in tasks {
                self.scheduleTaskNotification(for: task)
            }
        }
    }
}
