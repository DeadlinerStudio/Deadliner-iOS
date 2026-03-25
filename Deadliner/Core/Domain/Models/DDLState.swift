//
//  DDLState.swift
//  Deadliner
//

import Foundation

enum DDLState: String, Codable, Sendable {
    case active
    case completed
    case archived
    case abandoned

    var isCompletedLike: Bool {
        switch self {
        case .completed, .archived:
            return true
        case .active, .abandoned:
            return false
        }
    }

    var isArchivedLike: Bool {
        self == .archived
    }
}

enum DDLStateTransitionError: Error {
    case invalidTransition(from: DDLState, to: DDLState)
}

enum DDLStateMachine {
    static func canTransition(from: DDLState, to: DDLState) -> Bool {
        switch (from, to) {
        case let (lhs, rhs) where lhs == rhs:
            return true
        case (.active, .completed), (.active, .abandoned):
            return true
        case (.completed, .active), (.completed, .archived):
            return true
        case (.archived, .active), (.archived, .completed):
            return true
        case (.abandoned, .active):
            return true
        default:
            return false
        }
    }

    static func validateTransition(from: DDLState, to: DDLState) throws {
        guard canTransition(from: from, to: to) else {
            throw DDLStateTransitionError.invalidTransition(from: from, to: to)
        }
    }
}
