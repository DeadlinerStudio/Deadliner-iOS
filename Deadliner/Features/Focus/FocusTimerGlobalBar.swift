#if canImport(Shared)
import SwiftUI
import Shared

/// The TabView supplies the material and layout; only content lives here.
struct FocusTimerGlobalBar: View {
    @ObservedObject var model: FocusTimerPresentationModel
    let onOpen: () -> Void
    var body: some View {
        if #available(iOS 26.0, *) {
            FocusAccessoryContent(model: model, onOpen: onOpen)
        } else {
            FocusBarContent(model: model, onOpen: onOpen, inline: false)
        }
    }
}

@available(iOS 26.0, *)
private struct FocusAccessoryContent: View {
    @ObservedObject var model: FocusTimerPresentationModel
    let onOpen: () -> Void
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    var body: some View { FocusBarContent(model: model, onOpen: onOpen, inline: placement == .inline) }
}

private struct FocusBarContent: View {
    @ObservedObject var model: FocusTimerPresentationModel
    let onOpen: () -> Void
    let inline: Bool
    var body: some View {
        if let timer = model.state?.timer {
            HStack(spacing: 12) {
                Button(action: onOpen) {
                    HStack(spacing: 10) {
                        Image(systemName: timer.target?.kind == .habit ? "leaf" : "timer")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(timer.taskTitle).font(.subheadline.weight(.semibold)).lineLimit(1)
                            if !inline {
                                Text(timer.state == .paused ? "已暂停" : "专注中")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                        Text(FocusTimerFormatting.clock(timer.remainingSeconds?.int64Value ?? timer.elapsedSeconds))
                            .monospacedDigit().font(.subheadline)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("focus.global.open")
                if timer.canPause || timer.canResume {
                    Button {
                        timer.canPause ? model.pause() : model.resume()
                    } label: {
                        Image(systemName: timer.canPause ? "pause.fill" : "play.fill")
                            .frame(minWidth: 32, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(timer.canPause ? "暂停专注" : "继续专注")
                    .accessibilityIdentifier("focus.global.toggle")
                    .disabled(model.state?.isBusy == true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, inline ? 2 : 8)
        }
    }
}

private struct FocusTabAccessoryModifier: ViewModifier {
    @ObservedObject var model: FocusTimerPresentationModel
    let onOpen: () -> Void
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.1, *) {
            content.tabViewBottomAccessory(isEnabled: model.state?.timer != nil) {
                FocusTimerGlobalBar(model: model, onOpen: onOpen)
            }
        } else if #available(iOS 26.0, *) {
            if model.state?.timer != nil {
                content.tabViewBottomAccessory { FocusTimerGlobalBar(model: model, onOpen: onOpen) }
            } else { content }
        } else {
            content.safeAreaInset(edge: .bottom) {
                if model.state?.timer != nil {
                    FocusTimerGlobalBar(model: model, onOpen: onOpen).background(.regularMaterial)
                }
            }
        }
    }
}

extension View {
    func focusTabAccessory(model: FocusTimerPresentationModel, onOpen: @escaping () -> Void) -> some View {
        modifier(FocusTabAccessoryModifier(model: model, onOpen: onOpen))
    }
}
#endif
