//
//  CaptureItemDetailSheet.swift
//  Deadliner
//
//  Created by Codex on 2026/4/8.
//

import SwiftUI

struct CaptureItemDetailSheet: View {
    @Environment(\.dismiss) private var dismiss

    let item: CaptureInboxItem
    let onSave: (String) -> Void
    let onConvertToTask: () -> Void
    let onConvertToHabit: () -> Void
    let onDelete: () -> Void

    @State private var text: String

    init(
        item: CaptureInboxItem,
        onSave: @escaping (String) -> Void,
        onConvertToTask: @escaping () -> Void,
        onConvertToHabit: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.item = item
        self.onSave = onSave
        self.onConvertToTask = onConvertToTask
        self.onConvertToHabit = onConvertToHabit
        self.onDelete = onDelete
        _text = State(initialValue: item.text)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("内容") {
                    TextEditor(text: $text)
                        .frame(minHeight: 140)
                }

                Section("整理成") {
                    Button("任务") {
                        saveIfNeeded()
                        dismiss()
                        onConvertToTask()
                    }

                    Button("习惯") {
                        saveIfNeeded()
                        dismiss()
                        onConvertToHabit()
                    }
                }

                Section {
                    Button("删除这条灵感", role: .destructive) {
                        dismiss()
                        onDelete()
                    }
                }
            }
            .navigationTitle("编辑灵感")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        saveIfNeeded()
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func saveIfNeeded() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != item.text else { return }
        onSave(trimmed)
    }
}
