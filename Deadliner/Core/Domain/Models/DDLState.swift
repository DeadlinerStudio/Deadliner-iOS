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
    case abandonedArchived

    var isCompletedLike: Bool {
        switch self {
        case .completed, .archived:
            return true
        case .active, .abandoned, .abandonedArchived:
            return false
        }
    }

    var isArchivedLike: Bool {
        self == .archived || self == .abandonedArchived
    }

    var isAbandonedLike: Bool {
        self == .abandoned || self == .abandonedArchived
    }
}

enum DDLStateTransitionError: Error {
    case invalidTransition(from: DDLState, to: DDLState)
    case invalidAction(state: DDLState, action: DDLStateAction)
}

enum DDLStateAction: Sendable {
    case markComplete
    case markArchive
    case markGiveUp
    case restoreActive
    case unarchive
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
        case (.abandoned, .active), (.abandoned, .abandonedArchived):
            return true
        case (.abandonedArchived, .abandoned):
            return true
        default:
            return false
        }
    }

    static func nextState(from state: DDLState, action: DDLStateAction) throws -> DDLState {
        let target: DDLState

        switch (state, action) {
        case (.active, .markComplete):
            target = .completed
        case (.completed, .markComplete):
            target = .active
        case (.completed, .markArchive):
            target = .archived
        case (.archived, .unarchive):
            target = .completed
        case (.active, .markGiveUp):
            target = .abandoned
        case (.abandoned, .markGiveUp):
            target = .active
        case (.abandoned, .markArchive):
            target = .abandonedArchived
        case (.abandonedArchived, .unarchive):
            target = .abandoned
        case (.active, .restoreActive), (.completed, .restoreActive), (.abandoned, .restoreActive):
            target = .active
        default:
            throw DDLStateTransitionError.invalidAction(state: state, action: action)
        }

        try validateTransition(from: state, to: target)
        return target
    }

    static func validateTransition(from: DDLState, to: DDLState) throws {
        guard canTransition(from: from, to: to) else {
            throw DDLStateTransitionError.invalidTransition(from: from, to: to)
        }
    }
}
