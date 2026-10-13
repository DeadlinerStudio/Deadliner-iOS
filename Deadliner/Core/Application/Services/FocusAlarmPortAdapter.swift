#if canImport(Shared)
import Foundation
import Shared
import UserNotifications

extension Notification.Name {
    static let focusNotificationOpened = Notification.Name("deadliner.focus.notification-opened")
}

@MainActor
final class FocusNotificationRoute {
    static let shared = FocusNotificationRoute()
    private var pendingSessionUID: String?
    func open(_ uid: String) {
        pendingSessionUID = uid
        NotificationCenter.default.post(name: .focusNotificationOpened, object: nil)
    }
    func consume() -> String? {
        defer { pendingSessionUID = nil }
        return pendingSessionUID
    }
}

/// Called by the KMP worker, never by the SwiftUI actor. Reports permission/add failures.
nonisolated final class FocusAlarmPortAdapter: NSObject, FocusAlarmPort, UNUserNotificationCenterDelegate {
    static let shared = FocusAlarmPortAdapter()
    private let center = UNUserNotificationCenter.current()
    override init() {
        super.init()
        center.delegate = self
    }

    func scheduleCountdown(sessionUid: String, fireAt: String, taskTitle: String) -> FocusAlarmResult {
        guard !Thread.isMainThread else { return failure("Reminder scheduling must run off the main thread") }
        guard let fireDate = Self.parseDate(fireAt) else { return failure("Invalid countdown date") }
        let permission = DispatchSemaphore(value: 0)
        let result = FocusNotificationResultBox()
        center.getNotificationSettings { settings in
            result.allowed = [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus)
            permission.signal()
        }
        guard permission.wait(timeout: .now() + 3) == .success, result.allowed else {
            return failure("Notification permission is unavailable")
        }
        let content = UNMutableNotificationContent()
        content.title = taskTitle
        content.body = "倒计时已结束，打开 Deadliner 查看结果。"
        content.sound = .default
        content.categoryIdentifier = "DEADLINER_FOCUS_COUNTDOWN"
        content.userInfo = ["focusSessionUID": sessionUid]
        let request = UNNotificationRequest(identifier: Self.identifier(sessionUid), content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, fireDate.timeIntervalSinceNow), repeats: false))
        let scheduled = DispatchSemaphore(value: 0)
        center.add(request) { error in result.error = error; scheduled.signal() }
        guard scheduled.wait(timeout: .now() + 3) == .success else { return failure("Notification scheduling timed out") }
        if let error = result.error { return failure(error.localizedDescription) }
        return FocusAlarmResult(succeeded: true, failureMessage: nil)
    }

    func cancelCountdown(sessionUid: String) -> FocusAlarmResult {
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier(sessionUid)])
        center.removeDeliveredNotifications(withIdentifiers: [Self.identifier(sessionUid)])
        return FocusAlarmResult(succeeded: true, failureMessage: nil)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler(notification.request.content.userInfo["focusSessionUID"] != nil ? [.banner, .sound] : [])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let uid = response.notification.request.content.userInfo["focusSessionUID"] as? String {
            DispatchQueue.main.async {
                FocusNotificationRoute.shared.open(uid)
            }
        }
        completionHandler()
    }

    static func parseDate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
    private func failure(_ message: String) -> FocusAlarmResult {
        FocusAlarmResult(succeeded: false, failureMessage: message)
    }
    private static func identifier(_ uid: String) -> String { "deadliner.focus.\(uid)" }
}

/// Notification completions are synchronized by semaphores before values are read.
private nonisolated final class FocusNotificationResultBox: @unchecked Sendable {
    var allowed = false
    var error: Error?
}
#endif
