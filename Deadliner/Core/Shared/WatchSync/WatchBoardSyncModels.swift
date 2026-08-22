import Foundation

struct WatchBoardSyncSnapshot: Codable, Sendable {
    let generatedAt: Date
    let pages: [WatchBoardSyncPage]
}

struct WatchBoardSyncPage: Codable, Sendable {
    let page: WatchBoardSyncPageKind
    let theme: WatchBoardSyncTheme
    let progress: Double
    let activeCount: Int
    let totalCount: Int
    let items: [WatchBoardSyncItem]
}

enum WatchBoardSyncPageKind: String, Codable, Sendable {
    case tasks
    case habits
    case ideas
}

enum WatchBoardSyncTheme: String, Codable, Sendable {
    case taskNormal
    case taskNear
    case taskOverdue
    case taskEmpty
    case habit
    case idea
}

struct WatchBoardSyncItem: Codable, Identifiable, Sendable {
    let id: String
    let title: String
    let subtitle: String?
    let badgeText: String?
    let isCompleted: Bool
    let isUrgent: Bool
    let isOverdue: Bool
    let canApplyPrimaryAction: Bool?

    init(
        id: String,
        title: String,
        subtitle: String?,
        badgeText: String?,
        isCompleted: Bool,
        isUrgent: Bool,
        isOverdue: Bool,
        canApplyPrimaryAction: Bool? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.badgeText = badgeText
        self.isCompleted = isCompleted
        self.isUrgent = isUrgent
        self.isOverdue = isOverdue
        self.canApplyPrimaryAction = canApplyPrimaryAction
    }
}

struct WatchBoardActionEnvelope: Codable, Sendable {
    let actionId: UUID
    let action: WatchBoardAction

    init(action: WatchBoardAction) {
        self.actionId = UUID()
        self.action = action
    }
}

enum WatchBoardAction: Codable, Sendable {
    case snapshotRefreshRequest
    case taskToggle(String)
    case taskPostponeDay(String)
    case taskGiveUp(String)
    case taskDelete(String)
    case habitToggle(String)
    case habitClearToday(String)
    case habitArchive(String)
    case ideaDelete(String)

    private enum CodingKeys: String, CodingKey {
        case kind
        case uid
        case uuidValue
    }

    private enum Kind: String, Codable {
        case snapshotRefreshRequest
        case taskToggle
        case taskPostponeDay
        case taskGiveUp
        case taskDelete
        case habitToggle
        case habitClearToday
        case habitArchive
        case ideaDelete
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)

        switch kind {
        case .snapshotRefreshRequest:
            self = .snapshotRefreshRequest
        case .taskToggle:
            self = .taskToggle(try container.decode(String.self, forKey: .uid))
        case .taskPostponeDay:
            self = .taskPostponeDay(try container.decode(String.self, forKey: .uid))
        case .taskGiveUp:
            self = .taskGiveUp(try container.decode(String.self, forKey: .uid))
        case .taskDelete:
            self = .taskDelete(try container.decode(String.self, forKey: .uid))
        case .habitToggle:
            self = .habitToggle(try container.decode(String.self, forKey: .uid))
        case .habitClearToday:
            self = .habitClearToday(try container.decode(String.self, forKey: .uid))
        case .habitArchive:
            self = .habitArchive(try container.decode(String.self, forKey: .uid))
        case .ideaDelete:
            // `uuidValue` is the pre-KMP Capture wire key. Keep decoding it so
            // queued actions from older Watch builds are safely replayable.
            let legacyUID = try container.decodeIfPresent(String.self, forKey: .uuidValue)
            let uid = try container.decodeIfPresent(String.self, forKey: .uid)
            guard let uid = uid ?? legacyUID else {
                throw DecodingError.keyNotFound(
                    CodingKeys.uid,
                    .init(codingPath: container.codingPath, debugDescription: "Missing Capture UID")
                )
            }
            self = .ideaDelete(uid)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .snapshotRefreshRequest:
            try container.encode(Kind.snapshotRefreshRequest, forKey: .kind)
        case .taskToggle(let value):
            try container.encode(Kind.taskToggle, forKey: .kind)
            try container.encode(value, forKey: .uid)
        case .taskPostponeDay(let value):
            try container.encode(Kind.taskPostponeDay, forKey: .kind)
            try container.encode(value, forKey: .uid)
        case .taskGiveUp(let value):
            try container.encode(Kind.taskGiveUp, forKey: .kind)
            try container.encode(value, forKey: .uid)
        case .taskDelete(let value):
            try container.encode(Kind.taskDelete, forKey: .kind)
            try container.encode(value, forKey: .uid)
        case .habitToggle(let value):
            try container.encode(Kind.habitToggle, forKey: .kind)
            try container.encode(value, forKey: .uid)
        case .habitClearToday(let value):
            try container.encode(Kind.habitClearToday, forKey: .kind)
            try container.encode(value, forKey: .uid)
        case .habitArchive(let value):
            try container.encode(Kind.habitArchive, forKey: .kind)
            try container.encode(value, forKey: .uid)
        case .ideaDelete(let value):
            try container.encode(Kind.ideaDelete, forKey: .kind)
            try container.encode(value, forKey: .uid)
        }
    }
}
