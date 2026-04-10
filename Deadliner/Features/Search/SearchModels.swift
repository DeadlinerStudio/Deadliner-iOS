//
//  SearchModels.swift
//  Deadliner
//
//  Created by Codex on 2026/4/2.
//

import SwiftUI

enum SearchScope: String, CaseIterable, Identifiable {
    case all = "全部"
    case active = "清单"
    case archive = "归档"

    var id: String { rawValue }

    var allowsActive: Bool {
        self == .all || self == .active
    }

    var allowsArchive: Bool {
        self == .all || self == .archive
    }
}

enum SearchBrowseCategory: String, CaseIterable, Hashable, Identifiable {
    case today
    case upcoming
    case starred
    case archived
    case tasks
    case habits

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today:
            return "今日"
        case .upcoming:
            return "近期截止"
        case .starred:
            return "星标"
        case .archived:
            return "归档"
        case .tasks:
            return "任务"
        case .habits:
            return "习惯"
        }
    }

    var systemImage: String {
        switch self {
        case .today:
            return "sun.max.fill"
        case .upcoming:
            return "clock.badge.exclamationmark.fill"
        case .starred:
            return "star.fill"
        case .archived:
            return "archivebox.fill"
        case .tasks:
            return "checklist"
        case .habits:
            return "leaf.fill"
        }
    }

    var tint: Color {
        switch self {
        case .today:
            return .orange
        case .upcoming:
            return .red
        case .starred:
            return .yellow
        case .archived:
            return .gray
        case .tasks:
            return .blue
        case .habits:
            return .green
        }
    }
}

enum RichSearchDeleteTarget {
    case task(DDLItem)
    case habit(Habit)
    case inspiration(CaptureInboxItem)
}

protocol RichSearchSortable {
    var sortScore: Int { get }
    var sortTitle: String { get }
}

struct SearchTaskResult: Identifiable, RichSearchSortable {
    let task: DDLItem
    let sortScore: Int

    var id: Int64 { task.id }
    var sortTitle: String { task.name }
}

struct SearchHabitResult: Identifiable, RichSearchSortable {
    let habit: Habit
    let sortScore: Int

    var id: Int64 { habit.id }
    var sortTitle: String { habit.name }
}

struct SearchInspirationResult: Identifiable, RichSearchSortable {
    let item: CaptureInboxItem
    let sortScore: Int

    var id: UUID { item.id }
    var sortTitle: String { item.text }
}

struct SearchTaskActions {
    let onToggleCompletion: (DDLItem) async -> Void
    let onDelete: (DDLItem) -> Void
    let onGiveUp: (DDLItem) -> Void
    let onArchive: (DDLItem) async -> Void
    let onEdit: (DDLItem) -> Void
    let onUnarchive: (DDLItem) async -> Void
}

struct SearchHabitActions {
    let onToggle: (HabitWithDailyStatus) async -> Void
    let onDelete: (Habit) -> Void
    let onArchive: (Habit) async -> Void
    let onEdit: (Habit) -> Void
    let onUnarchive: (Habit) async -> Void
}

struct SearchInspirationActions {
    let onOpen: (CaptureInboxItem) -> Void
    let onDelete: (CaptureInboxItem) -> Void
    let onConvertToTask: (CaptureInboxItem) -> Void
    let onConvertToHabit: (CaptureInboxItem) -> Void
    let onAIConvertToTask: (CaptureInboxItem) -> Void
    let onAIConvertToHabit: (CaptureInboxItem) -> Void
}

struct SearchListStyleModifier: ViewModifier {
    let useInsetGrouped: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if useInsetGrouped {
            content.listStyle(.insetGrouped)
        } else {
            content.listStyle(.plain)
        }
    }
}
