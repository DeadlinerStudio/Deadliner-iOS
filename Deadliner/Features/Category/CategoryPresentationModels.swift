//
//  CategoryPresentationModels.swift
//  Deadliner
//
//  Created by Codex on 2026/7/17.
//

import SwiftUI

struct CategoryFilter: Hashable, Equatable {
    var includesUncategorized: Bool = false
    var categoryUIDs: Set<String> = []

    static let all = CategoryFilter()

    var isAll: Bool {
        !includesUncategorized && categoryUIDs.isEmpty
    }

    var title: String {
        if isAll {
            return "全部分类"
        }
        let count = (includesUncategorized ? 1 : 0) + categoryUIDs.count
        if count == 1 {
            return includesUncategorized ? "未分类" : "1 个分类"
        }
        return "\(count) 个分类"
    }

    func matches(_ categoryUID: String?) -> Bool {
        if isAll {
            return true
        }
        guard let categoryUID else {
            return includesUncategorized
        }
        return categoryUIDs.contains(categoryUID)
    }

    mutating func toggleUncategorized() {
        includesUncategorized.toggle()
    }

    mutating func toggleCategory(_ uid: String) {
        if categoryUIDs.contains(uid) {
            categoryUIDs.remove(uid)
        } else {
            categoryUIDs.insert(uid)
        }
    }

    mutating func reset() {
        includesUncategorized = false
        categoryUIDs = []
    }
}

enum BrowseCategoryLayout: String, CaseIterable, Identifiable {
    case list
    case cards

    var id: String { rawValue }

    var title: String {
        switch self {
        case .list:
            return "列表"
        case .cards:
            return "卡片"
        }
    }

    var systemImage: String {
        switch self {
        case .list:
            return "list.bullet"
        case .cards:
            return "square.grid.2x2"
        }
    }
}

struct CategoryBadgeModel: Equatable, Sendable {
    let uid: String
    let name: String
    let iconKey: String
    let colorHex: String

    init(category: TaskCategory) {
        self.uid = category.uid
        self.name = category.name
        self.iconKey = category.iconKey
        self.colorHex = category.colorHex
    }
}

extension CategoryBadgeModel {
    var color: Color {
        Color(hex: colorHex)
    }

    var safeIconKey: String {
        CategoryPresentationSupport.safeIconKey(iconKey)
    }
}

enum CategoryPresentationSupport {
    static let iconOptions = [
        "tag",
        "folder",
        "inbox_tray",
        "briefcase",
        "office_building",
        "book",
        "education",
        "edit",
        "home",
        "shopping",
        "dining",
        "coffee",
        "health",
        "medical",
        "running",
        "fitness",
        "payment_card",
        "cash",
        "analytics",
        "group",
        "family",
        "creativity",
        "camera",
        "music",
        "reading",
        "inspiration",
        "calendar",
        "time",
        "flag",
        "idea",
        "travel",
        "flight",
        "gaming",
        "tools",
        "construction",
        "nature"
    ]

    static let colorOptions = [
        "#3B82F6",
        "#2563EB",
        "#6366F1",
        "#8B5CF6",
        "#A855F7",
        "#EC4899",
        "#F43F5E",
        "#EF4444",
        "#F97316",
        "#F59E0B",
        "#EAB308",
        "#84CC16",
        "#22C55E",
        "#10B981",
        "#14B8A6",
        "#06B6D4",
        "#0EA5E9",
        "#64748B",
        "#8E8E93",
        "#111827"
    ]

    /// Converts the historical iOS SF Symbol spelling into the portable icon ID stored by V3.
    static func semanticIconKey(_ iconKey: String) -> String {
        switch iconKey {
        case "tag.fill": return "tag"
        case "folder.fill": return "folder"
        case "tray.full.fill": return "inbox_tray"
        case "briefcase.fill": return "briefcase"
        case "building.2.fill": return "office_building"
        case "book.closed.fill": return "book"
        case "graduationcap.fill": return "education"
        case "pencil.and.outline", "pencil.line": return "edit"
        case "house.fill": return "home"
        case "cart.fill": return "shopping"
        case "fork.knife": return "dining"
        case "cup.and.saucer.fill": return "coffee"
        case "heart.fill": return "health"
        case "cross.case.fill": return "medical"
        case "figure.run": return "running"
        case "dumbbell.fill": return "fitness"
        case "creditcard.fill": return "payment_card"
        case "banknote.fill": return "cash"
        case "chart.line.uptrend.xyaxis": return "analytics"
        case "person.2.fill": return "group"
        case "figure.2.and.child.holdinghands": return "family"
        case "paintbrush.pointed.fill": return "creativity"
        case "camera.fill": return "camera"
        case "music.note": return "music"
        case "text.book.closed.fill": return "reading"
        case "sparkles": return "inspiration"
        case "clock.fill": return "time"
        case "flag.fill": return "flag"
        case "lightbulb.fill": return "idea"
        case "globe.asia.australia.fill": return "travel"
        case "airplane": return "flight"
        case "gamecontroller.fill": return "gaming"
        case "wrench.and.screwdriver.fill": return "tools"
        case "hammer.fill": return "construction"
        case "leaf.fill": return "nature"
        default: return iconOptions.contains(iconKey) ? iconKey : "tag"
        }
    }

    static func systemImageName(for iconKey: String) -> String {
        switch semanticIconKey(iconKey) {
        case "folder": return "folder.fill"
        case "inbox_tray": return "tray.full.fill"
        case "briefcase": return "briefcase.fill"
        case "office_building": return "building.2.fill"
        case "book": return "book.closed.fill"
        case "education": return "graduationcap.fill"
        case "edit": return "pencil.line"
        case "home": return "house.fill"
        case "shopping": return "cart.fill"
        case "dining": return "fork.knife"
        case "coffee": return "cup.and.saucer.fill"
        case "health": return "heart.fill"
        case "medical": return "cross.case.fill"
        case "running": return "figure.run"
        case "fitness": return "dumbbell.fill"
        case "payment_card": return "creditcard.fill"
        case "cash": return "banknote.fill"
        case "analytics": return "chart.line.uptrend.xyaxis"
        case "group": return "person.2.fill"
        case "family": return "figure.2.and.child.holdinghands"
        case "creativity": return "paintbrush.pointed.fill"
        case "camera": return "camera.fill"
        case "music": return "music.note"
        case "reading": return "text.book.closed.fill"
        case "inspiration": return "sparkles"
        case "calendar": return "calendar"
        case "time": return "clock.fill"
        case "flag": return "flag.fill"
        case "idea": return "lightbulb.fill"
        case "travel": return "globe.asia.australia.fill"
        case "flight": return "airplane"
        case "gaming": return "gamecontroller.fill"
        case "tools": return "wrench.and.screwdriver.fill"
        case "construction": return "hammer.fill"
        case "nature": return "leaf.fill"
        default: return "tag.fill"
        }
    }

    static func safeIconKey(_ iconKey: String) -> String {
        systemImageName(for: iconKey)
    }

    static func normalizedColorHex(_ colorHex: String) -> String {
        guard colorHex.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) != nil else {
            return "#3B82F6"
        }
        return colorHex.uppercased()
    }

    static func badge(for categoryUID: String?, categories: [String: TaskCategory]) -> CategoryBadgeModel? {
        guard let categoryUID, let category = categories[categoryUID] else {
            return nil
        }
        return CategoryBadgeModel(category: category)
    }

    static func title(for filter: CategoryFilter, categories: [TaskCategory]) -> String {
        if filter.isAll {
            return "全部分类"
        }

        var names: [String] = []
        if filter.includesUncategorized {
            names.append("未分类")
        }

        names.append(
            contentsOf: categories
                .filter { filter.categoryUIDs.contains($0.uid) }
                .map(\.name)
        )

        return names.isEmpty ? "全部分类" : names.joined(separator: "、")
    }
}
