//
//  CaptureComposerCard.swift
//  Deadliner
//
//  Created by Codex on 2026/4/8.
//

import SwiftUI

struct CaptureComposerCard: View {
    @EnvironmentObject private var themeStore: ThemeStore

    @Binding var draftText: String

    let speechIsRecording: Bool
    let speechIsPreparing: Bool
    let speechIsBusy: Bool
    let helperText: String?
    let errorText: String?
    let onToggleRecording: () -> Void
    let onCommit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("先记下一句想法")
                    .font(.title3.weight(.bold))

                Spacer()

                Text("稍后再整理")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("这里适合放灵感、计划草稿、稍后可能要做的事，先别急着把它变得太正式。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("记下一句灵感、一段计划，或一个未来要做的念头...", text: $draftText, axis: .vertical)
                .lineLimit(3...7)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color(uiColor: .systemBackground).opacity(0.78))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            HStack(spacing: 10) {
                Button(action: onToggleRecording) {
                    HStack(spacing: 8) {
                        Image(systemName: speechIsRecording ? "stop.circle.fill" : "mic.fill")
                            .foregroundStyle(speechIsRecording ? .red : .secondary)

                        Text(speechIsRecording ? "结束录制" : "开始录制")
                    }
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .tint(speechIsRecording ? .red : .secondary)
                .disabled(speechIsPreparing)

                Button(action: onCommit) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")

                        Text("保存灵感")
                    }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .tint(themeStore.accentColor)
                .disabled(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let helperText, speechIsBusy {
                Label(helperText, systemImage: "waveform")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if let errorText {
                Text(errorText)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding(18)
        .background(background)
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 14, x: 0, y: 6)
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(Color(uiColor: .secondarySystemGroupedBackground))
    }

    private var borderColor: Color {
        themeStore.accentColor.opacity(0.12)
    }
}
