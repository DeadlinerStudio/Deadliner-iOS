//
//  DDLCardModels.swift
//  Deadliner
//
//  Created by Aritx 音唯 on 2026/2/16.
//

import SwiftUI

enum DDLStatus {
    case undergo
    case near
    case passed
    case completed
    case abandoned
}

enum DDLCardSwipeAction {
    case complete
    case delete
}

struct DDLStatusStyle {
    let indicator: Color
    let background: Color

    static func from(_ status: DDLStatus, scheme: ColorScheme) -> DDLStatusStyle {
        switch status {
        case .undergo:
            return .init(
                indicator: .blue.opacity(0.55),
                background: Color.blue.opacity(0.18)
            )
        case .near:
            return .init(
                indicator: .orange.opacity(0.65),
                background: .orange.opacity(0.20)
            )
        case .passed:
            return .init(
                indicator: .red.opacity(0.65),
                background: .red.opacity(0.20)
            )
        case .completed:
            return .init(
                indicator: .green.opacity(0.65),
                background: .green.opacity(0.20)
            )
        case .abandoned:
            return .init(
                indicator: .gray.opacity(0.65),
                background: .gray.opacity(0.18)
            )
        }
    }
}
