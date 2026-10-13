#if canImport(Shared)
import SwiftUI
import Shared

struct FocusRoundAction: View {
    let symbol: String
    let title: String
    var primary = false
    var enabled = true
    var identifier = ""
    let action: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Button(action: action) {
                Image(systemName: symbol)
                    .font(.system(size: primary ? 30 : 23, weight: .semibold))
                    .frame(width: primary ? 80 : 56, height: primary ? 80 : 56)
                    .foregroundStyle(primary ? Color.white : Color.primary)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .modifier(FocusActionMaterial(primary: primary))
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.4)
            .accessibilityLabel(title)
            .accessibilityIdentifier(identifier)
            Text(title).font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity)
    }
}

private struct FocusActionMaterial: ViewModifier {
    let primary: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.tint(primary ? Color.accentColor : Color.clear).interactive(), in: Circle())
        } else {
            content.background(primary ? Color.accentColor : Color(uiColor: .secondarySystemGroupedBackground), in: Circle())
        }
    }
}

struct FocusTimerDial: View {
    let timer: FocusTimerSnapshot
    private var progress: Double {
        if timer.mode == .countdown {
            return min(1, max(0, Double(timer.elapsedSeconds) / max(1, timer.plannedDurationSeconds?.doubleValue ?? 1)))
        }
        return Double(max(0, timer.elapsedSeconds) % 60) / 60
    }
    var body: some View {
        ZStack {
            Circle().stroke(Color.accentColor.opacity(0.1), lineWidth: 5)
            Circle().trim(from: 0, to: progress)
                .stroke(Color.accentColor.opacity(timer.state == .paused ? 0.4 : 0.9), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 8) {
                Text(timer.mode == .countdown ? "剩余时间" : "已专注")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text(FocusTimerFormatting.clock(timer.remainingSeconds?.int64Value ?? timer.elapsedSeconds))
                    .font(.system(size: 60, weight: .semibold, design: .rounded))
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                    .contentTransition(.numericText())
                    .accessibilityIdentifier("focus.clock")
                Text(timer.state == .paused ? "已暂停" : "专注中")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(timer.state == .paused ? Color.secondary : Color.accentColor)
            }.padding(30)
        }
        .frame(maxWidth: 320).aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .combine)
    }
}

struct FocusSetupContent: View {
    @ObservedObject var model: FocusTimerPresentationModel
    @Binding var mode: Int
    @Binding var minutes: Int
    @State private var customDuration = false
    let busy: Bool
    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 20) {
                Menu {
                    Section("任务") {
                        ForEach(model.activeTasks) { task in Button(task.name) { model.selectTask(task.id) } }
                    }
                    Section("习惯") {
                        ForEach(model.activeHabits) { habit in Button(habit.name) { model.selectHabit(habit.id) } }
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: model.state?.selectedTarget?.kind == .habit ? "leaf" : "timer")
                        Text(model.selectedTitle.isEmpty ? "选择任务或习惯" : model.selectedTitle)
                            .font(.headline).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.down").font(.caption)
                    }.contentShape(Rectangle())
                }.accessibilityIdentifier("focus.target")
                Picker("计时模式", selection: $mode) {
                    Text("正计时").tag(0)
                    Text("倒计时").tag(1)
                }.pickerStyle(.segmented).accessibilityIdentifier("focus.mode")
                Text(mode == 0 ? "00:00" : FocusTimerFormatting.clock(Int64(minutes * 60)))
                    .font(.system(size: 48, weight: .semibold, design: .rounded)).monospacedDigit()
                    .padding(.vertical, 8)
                if mode == 1 {
                    HStack {
                        ForEach([15, 25, 45, 60], id: \.self) { value in
                            Button("\(value) 分") { minutes = value }
                                .font(.subheadline.weight(minutes == value ? .semibold : .regular))
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(minutes == value ? Color.accentColor.opacity(0.12) : Color.clear, in: Capsule())
                        }
                    }.buttonStyle(.plain)
                    DisclosureGroup("自定义 · \(minutes) 分钟", isExpanded: $customDuration) {
                        Slider(value: Binding(get: { Double(minutes) }, set: { minutes = Int($0.rounded()) }), in: 1...180, step: 1)
                            .accessibilityLabel("倒计时分钟数")
                    }.font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
            .disabled(busy)
            FocusRoundAction(symbol: "play.fill", title: "开始专注", primary: true,
                             enabled: !busy && model.selectedTargetAvailable,
                             identifier: mode == 0 ? "focus.start.stopwatch" : "focus.start.countdown") {
                mode == 0 ? model.startStopwatch() : model.startCountdown(minutes: minutes)
            }
        }.padding(.vertical, 16)
    }
}
#endif
