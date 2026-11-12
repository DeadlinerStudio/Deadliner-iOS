import ActivityKit
import AppIntents
import WidgetKit
import SwiftUI

struct DeadlinerWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusLiveActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Deadliner · 专注", systemImage: context.state.isPaused ? "pause.circle.fill" : "timer")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(status(context)).font(.caption).foregroundStyle(.secondary)
                }
                FocusActivityClock(state: context.state, isStale: context.isStale)
                    .font(.system(size: 38, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                controls(context)
            }
            .padding(18)
            .activityBackgroundTint(Color(.secondarySystemBackground))
            .activitySystemActionForegroundColor(.primary)
            .widgetURL(context.attributes.url)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("专注", systemImage: context.state.isPaused ? "pause.circle.fill" : "timer")
                        .font(.headline).foregroundStyle(.blue)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(status(context)).font(.caption).foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 12) {
                        FocusActivityClock(state: context.state, isStale: context.isStale)
                            .font(.system(size: 36, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                        controls(context)
                    }
                    .padding(.top, 4)
                }
            } compactLeading: {
                Image(systemName: context.isStale ? "checkmark.circle" : context.state.isPaused ? "pause.fill" : "timer")
                    .foregroundStyle(.blue)
            } compactTrailing: {
                FocusActivityClock(state: context.state, isStale: context.isStale)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 72)
            } minimal: {
                Image(systemName: context.isStale ? "checkmark.circle" : context.state.isPaused ? "pause.fill" : "timer")
                    .foregroundStyle(.blue)
            }
            .widgetURL(context.attributes.url)
            .keylineTint(.blue)
        }
    }

    private func status(_ context: ActivityViewContext<FocusLiveActivityAttributes>) -> String {
        if context.isStale { return context.state.isCountdown && !context.state.isPaused ? "计时已到时" : "请打开应用核对" }
        return context.state.isPaused ? "已暂停" : context.state.isCountdown ? "剩余时间" : "专注中"
    }

    @ViewBuilder
    private func controls(_ context: ActivityViewContext<FocusLiveActivityAttributes>) -> some View {
        if context.isStale {
            Link(destination: context.attributes.url) { Label("查看专注", systemImage: "arrow.up.right") }
                .font(.subheadline.weight(.semibold))
        } else {
            HStack(spacing: 12) {
                if context.state.canPause || context.state.canResume {
                    Button(intent: intent(context, action: context.state.isPaused ? "resume" : "pause")) {
                        Label(context.state.isPaused ? "继续" : "暂停", systemImage: context.state.isPaused ? "play.fill" : "pause.fill")
                            .frame(maxWidth: .infinity)
                    }.tint(.blue)
                }
                // A running snapshot may have been created before the first whole second.
                // Keep the end action reachable as time advances; KMP revalidates it on execution.
                if context.state.canFinish || context.state.canPause {
                    Button(intent: intent(context, action: "finish")) {
                        Label("结束", systemImage: "stop.fill").frame(maxWidth: .infinity)
                    }.tint(.gray)
                }
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
        }
    }

    private func intent(_ context: ActivityViewContext<FocusLiveActivityAttributes>, action: String) -> FocusLiveActivityActionIntent {
        .init(sessionUID: context.attributes.sessionUID, version: context.state.version, action: action)
    }
}

private struct FocusActivityClock: View {
    let state: FocusLiveActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        Group {
            if state.isPaused {
                Text(clock(state.frozenSeconds))
            } else if isStale {
                Text(state.isCountdown ? "00:00" : "—:—")
            } else if state.isCountdown {
                Text(timerInterval: state.timerStart...max(state.timerStart, state.timerEnd), countsDown: true)
            } else {
                Text(timerInterval: state.timerStart...max(state.timerStart, state.timerEnd), countsDown: false)
            }
        }
        .monospacedDigit()
        .contentTransition(.numericText(countsDown: state.isCountdown))
        .accessibilityLabel(state.isPaused ? "已暂停" : state.isCountdown ? "剩余时间" : "已专注时长")
    }

    private func clock(_ seconds: Int64) -> String {
        let value = max(0, seconds)
        return value >= 3_600
            ? String(format: "%02lld:%02lld:%02lld", value / 3_600, value % 3_600 / 60, value % 60)
            : String(format: "%02lld:%02lld", value / 60, value % 60)
    }
}

private let previewAttributes = FocusLiveActivityAttributes(sessionUID: "preview")
private let previewState = FocusLiveActivityAttributes.ContentState(
    version: "preview", isCountdown: true, isPaused: false,
    timerStart: .now, timerEnd: .now.addingTimeInterval(25 * 60), frozenSeconds: 1_500,
    canPause: true, canResume: false, canFinish: true)

#Preview("专注锁屏", as: .content, using: previewAttributes) {
    DeadlinerWidgetLiveActivity()
} contentStates: {
    previewState
}
#Preview("专注灵动岛", as: .dynamicIsland(.expanded), using: previewAttributes) {
    DeadlinerWidgetLiveActivity()
} contentStates: {
    previewState
}
