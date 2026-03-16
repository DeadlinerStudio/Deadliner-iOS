//
//  MainModule.swift
//  Deadliner
//
//  Created by Aritx 音唯 on 2026/2/16.
//

import SwiftUI

enum MainModule: String, CaseIterable, Identifiable {
    case taskManagement = "清单"
    case insights = "概览"
    case archive = "归档"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .taskManagement: return "checklist"
        case .insights: return "chart.bar.xaxis"
        case .archive: return "archivebox"
        }
    }

    var title: String { rawValue }
}

enum TaskSegment: String, CaseIterable, Identifiable {
    case tasks = "任务"
    case habits = "习惯"

    var id: String { rawValue }
}
