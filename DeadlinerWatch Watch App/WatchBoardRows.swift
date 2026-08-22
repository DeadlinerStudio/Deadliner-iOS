import SwiftUI

struct WatchTaskBoardRow: View {
    let item: WatchTaskBoardItem
    @ObservedObject var store: WatchBoardStore

    @State private var showPrimaryConfirm = false
    @State private var showMoreActions = false

    var body: some View {
        rowBody
            .onTapGesture {
                showPrimaryConfirm = true
            }
            .onLongPressGesture(minimumDuration: 0.4) {
                showMoreActions = true
            }
            .confirmationDialog(
                String(localized: "watch.board.confirm.task.title", defaultValue: "Update task?"),
                isPresented: $showPrimaryConfirm,
                titleVisibility: .visible
            ) {
                Button(primaryActionTitle) {
                    store.toggleTaskCompletion(id: item.id)
                }
                Button(String(localized: "watch.board.action.more", defaultValue: "More")) {
                    showMoreActions = true
                }
                Button(String(localized: "watch.board.action.cancel", defaultValue: "Cancel"), role: .cancel) {}
            }
            .confirmationDialog(
                String(localized: "watch.board.more.task.title", defaultValue: "More actions"),
                isPresented: $showMoreActions,
                titleVisibility: .visible
            ) {
                Button(String(localized: "watch.board.action.postpone-day", defaultValue: "Postpone 1 Day")) {
                    store.postponeTaskOneDay(id: item.id)
                }
                Button(String(localized: "watch.board.action.give-up", defaultValue: "Give Up")) {
                    store.giveUpTask(id: item.id)
                }
                Button(String(localized: "watch.board.action.delete", defaultValue: "Delete"), role: .destructive) {
                    store.deleteTask(id: item.id)
                }
                Button(String(localized: "watch.board.action.cancel", defaultValue: "Cancel"), role: .cancel) {}
            }
    }

    private var rowBody: some View {
        HStack(alignment: .top, spacing: 8) {
            Capsule(style: .continuous)
                .fill(emphasisColor)
                .frame(width: 4, height: 30)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.98))
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)

                Text(item.dueText)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.76))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(item.badgeText)
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(emphasisColor)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .watchBoardCardBackground(tint: rowTint)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var primaryActionTitle: String {
        if item.isCompleted {
            return String(localized: "watch.board.action.task.restore", defaultValue: "Restore Task")
        }
        return String(localized: "watch.board.action.task.complete", defaultValue: "Mark Complete")
    }

    private enum RowStatus {
        case normal
        case near
        case overdue
    }

    private var rowStatus: RowStatus {
        if item.isOverdue { return .overdue }
        if item.isUrgent { return .near }
        return .normal
    }

    private var emphasisColor: Color {
        switch rowStatus {
        case .overdue:
            return .red.opacity(0.84)
        case .near:
            return .orange.opacity(0.88)
        case .normal:
            return Color(red: 0.52, green: 0.89, blue: 1.0)
        }
    }

    private var rowTint: Color {
        switch rowStatus {
        case .overdue:
            return .red.opacity(0.08)
        case .near:
            return .orange.opacity(0.08)
        case .normal:
            return Color(red: 0.14, green: 0.66, blue: 1.0).opacity(0.12)
        }
    }
}

struct WatchHabitBoardRow: View {
    let item: WatchHabitBoardItem
    @ObservedObject var store: WatchBoardStore

    @State private var showPrimaryConfirm = false
    @State private var showMoreActions = false

    var body: some View {
        rowBody
            .onTapGesture {
                if item.canApplyPrimaryAction {
                    showPrimaryConfirm = true
                }
            }
            .onLongPressGesture(minimumDuration: 0.4) {
                showMoreActions = true
            }
            .confirmationDialog(
                String(localized: "watch.board.confirm.habit.title", defaultValue: "Update habit?"),
                isPresented: $showPrimaryConfirm,
                titleVisibility: .visible
            ) {
                Button(primaryActionTitle) {
                    store.toggleHabitCompletion(id: item.id)
                }
                Button(String(localized: "watch.board.action.more", defaultValue: "More")) {
                    showMoreActions = true
                }
                Button(String(localized: "watch.board.action.cancel", defaultValue: "Cancel"), role: .cancel) {}
            }
            .confirmationDialog(
                String(localized: "watch.board.more.habit.title", defaultValue: "More actions"),
                isPresented: $showMoreActions,
                titleVisibility: .visible
            ) {
                Button(String(localized: "watch.board.action.clear-today", defaultValue: "Clear Today")) {
                    store.clearHabitProgress(id: item.id)
                }
                Button(String(localized: "watch.board.action.archive", defaultValue: "Archive")) {
                    store.archiveHabit(id: item.id)
                }
                Button(String(localized: "watch.board.action.cancel", defaultValue: "Cancel"), role: .cancel) {}
            }
    }

    private var rowBody: some View {
        HStack(alignment: .top, spacing: 8) {
            Capsule(style: .continuous)
                .fill(item.isCompleted ? Color.green : Color(red: 0.28, green: 0.92, blue: 0.84))
                .frame(width: 4, height: 30)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)

                Text(item.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.82))
            }

            Spacer(minLength: 8)

            Text(item.progressText)
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .watchBoardCardBackground()
        .opacity(item.canApplyPrimaryAction ? 1 : 0.62)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityAddTraits(item.canApplyPrimaryAction ? [] : .isStaticText)
    }

    private var primaryActionTitle: String {
        if item.isCompleted {
            return String(localized: "watch.board.action.habit.undo", defaultValue: "Undo Check-in")
        }
        return String(localized: "watch.board.action.habit.complete", defaultValue: "Check In")
    }
}

struct WatchIdeaBoardRow: View {
    let item: WatchIdeaBoardItem
    @ObservedObject var store: WatchBoardStore
    var onOpen: ((WatchIdeaBoardItem) -> Void)? = nil

    @State private var showMoreActions = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
                .lineLimit(2)

            Text(item.updatedText)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.82))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .watchBoardCardBackground()
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture {
            onOpen?(item)
        }
        .onLongPressGesture(minimumDuration: 0.4) {
            showMoreActions = true
        }
        .confirmationDialog(
            String(localized: "watch.board.more.idea.title", defaultValue: "More actions"),
            isPresented: $showMoreActions,
            titleVisibility: .visible
        ) {
            Button(String(localized: "watch.board.action.delete", defaultValue: "Delete"), role: .destructive) {
                store.deleteIdea(id: item.id)
            }
            Button(String(localized: "watch.board.action.cancel", defaultValue: "Cancel"), role: .cancel) {}
        }
    }
}

private extension View {
    func watchBoardCardBackground(tint: Color = .clear) -> some View {
        background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.12))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(tint)
                }
        }
    }
}
