//
//  QuickInspirationCaptureSheet.swift
//  Deadliner
//
//  Created for the Control Center quick-capture entry point.
//

import SwiftUI

struct QuickInspirationCaptureSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var themeStore: ThemeStore

    let onSave: (String) -> Void

    @State private var text = ""
    @FocusState private var isInputFocused: Bool

    private var normalizedText: String? {
        InspirationCaptureText.normalized(text)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("记下此刻", systemImage: "pencil.and.outline")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(themeStore.accentColor)

                    Text("先保存原始想法，之后再整理成任务或习惯。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                TextField(
                    "记下一句灵感、一段计划，或一个未来要做的念头…",
                    text: $text,
                    axis: .vertical
                )
                .lineLimit(4...8)
                .focused($isInputFocused)
                .submitLabel(.done)
                .onSubmit(save)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                Spacer(minLength: 0)
            }
            .padding(20)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("快速记录灵感")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save)
                        .fontWeight(.semibold)
                        .disabled(normalizedText == nil)
                }
            }
        }
        .onAppear {
            Task { @MainActor in
                await Task.yield()
                isInputFocused = true
            }
        }
    }

    private func save() {
        guard let normalizedText else { return }
        onSave(normalizedText)
        dismiss()
    }
}
