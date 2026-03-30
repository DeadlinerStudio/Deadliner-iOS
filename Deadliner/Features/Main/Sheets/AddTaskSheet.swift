//
//  AddTaskSheet.swift
//  Deadliner
//
//  Created by Aritx 音唯 on 2026/2/16.
//

import SwiftUI

struct AddTaskSheetView: View {
    let repository: TaskRepository
    var onDone: (() -> Void)? = nil
    var principalToolbarContent: AnyView? = nil
    var embedsInParentNavigationStack: Bool = false
    var saveTrigger: Int = 0
    var onSaveEnabledChange: ((Bool) -> Void)? = nil

    var body: some View {
        TaskEditorSheetView(
            repository: repository,
            mode: .add,
            initialDraft: .empty(),
            onDone: onDone,
            principalToolbarContent: principalToolbarContent,
            embedsInParentNavigationStack: embedsInParentNavigationStack,
            saveTrigger: saveTrigger,
            onSaveEnabledChange: onSaveEnabledChange
        )
    }
}

struct AddEntrySheetView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var themeStore: ThemeStore

    let repository: TaskRepository
    var onDone: (() -> Void)? = nil

    @State private var selection: TaskSegment
    @State private var taskSaveTrigger: Int = 0
    @State private var habitSaveTrigger: Int = 0
    @State private var isTaskSaveEnabled: Bool = false
    @State private var isHabitSaveEnabled: Bool = false

    init(
        repository: TaskRepository,
        initialSelection: TaskSegment = .tasks,
        onDone: (() -> Void)? = nil
    ) {
        self.repository = repository
        self.onDone = onDone
        _selection = State(initialValue: initialSelection)
    }

    private var segmentedControl: AnyView {
        AnyView(
            Picker("Add Entry Type", selection: $selection) {
                ForEach(TaskSegment.allCases) { segment in
                    Text(segment.rawValue).tag(segment)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AddTaskSheetView(
                    repository: repository,
                    onDone: onDone,
                    embedsInParentNavigationStack: true,
                    saveTrigger: taskSaveTrigger,
                    onSaveEnabledChange: { isEnabled in
                        isTaskSaveEnabled = isEnabled
                    }
                )
                .opacity(selection == .tasks ? 1 : 0)
                .allowsHitTesting(selection == .tasks)
                .accessibilityHidden(selection != .tasks)

                AddHabitSheetView(
                    onDone: onDone,
                    embedsInParentNavigationStack: true,
                    saveTrigger: habitSaveTrigger,
                    onSaveEnabledChange: { isEnabled in
                        isHabitSaveEnabled = isEnabled
                    }
                )
                .opacity(selection == .habits ? 1 : 0)
                .allowsHitTesting(selection == .habits)
                .accessibilityHidden(selection != .habits)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        onDone?()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }

                ToolbarItem(placement: .principal) {
                    segmentedControl
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        switch selection {
                        case .tasks:
                            taskSaveTrigger += 1
                        case .habits:
                            habitSaveTrigger += 1
                        }
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .disabled(!currentSaveEnabled)
                    .buttonStyle(.glassProminent)
                    .tint(themeStore.accentColor)
                }
            }
        }
    }

    private var currentSaveEnabled: Bool {
        switch selection {
        case .tasks:
            return isTaskSaveEnabled
        case .habits:
            return isHabitSaveEnabled
        }
    }
}
