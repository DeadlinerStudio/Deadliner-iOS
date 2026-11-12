import ActivityKit
import AppIntents
import Foundation

/// The same contract is compiled into the app and Widget Extension.
nonisolated struct FocusLiveActivityAttributes: ActivityAttributes {
    var sessionUID: String

    struct ContentState: Codable, Hashable {
        var version: String
        var isCountdown: Bool
        var isPaused: Bool
        var timerStart: Date
        var timerEnd: Date
        var frozenSeconds: Int64
        var canPause: Bool
        var canResume: Bool
        var canFinish: Bool
    }

    var url: URL {
        var components = URLComponents()
        components.scheme = "deadliner"
        components.host = "focus"
        components.queryItems = [URLQueryItem(name: "session", value: sessionUID)]
        return components.url!
    }

    static func sessionUID(from url: URL) -> String? {
        guard url.scheme == "deadliner", url.host == "focus",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.queryItems?.count == 1,
              let uid = components.queryItems?.first(where: { $0.name == "session" })?.value,
              !uid.isEmpty, uid.count <= 128 else { return nil }
        return uid
    }
}

struct FocusLiveActivityActionIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "操作专注计时"
    static var isDiscoverable: Bool = false

    @Parameter(title: "专注会话") var sessionUID: String
    @Parameter(title: "会话版本") var version: String
    @Parameter(title: "操作") var action: String

    init() {}
    init(sessionUID: String, version: String, action: String) {
        self.sessionUID = sessionUID
        self.version = version
        self.action = action
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        #if DEADLINER_APP
        await FocusTimerPresentationModel.shared.performLiveActivityAction(
            sessionUID: sessionUID, version: version, action: action)
        #endif
        return .result()
    }
}
