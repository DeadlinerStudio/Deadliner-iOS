//
//  AppNotifications.swift
//  Deadliner
//
//  Created by Aritx 音唯 on 2026/2/16.
//

import Foundation

extension Notification.Name {
    static let ddlDataChanged = Notification.Name("ddl_data_changed")
    static let ddlDeleteAllArchived = Notification.Name("ddl_delete_all_archived")
    static let ddlRequestMonthlyAnalysis = Notification.Name("ddl_request_monthly_analysis")
    static let captureInboxChanged = Notification.Name("capture_inbox_changed")
    static let ddlOpenTaskDetail = Notification.Name("ddl_open_task_detail")
}
