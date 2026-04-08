//
//  CaptureNoteCard.swift
//  Deadliner
//
//  Created by Codex on 2026/4/8.
//

import SwiftUI

struct CaptureNoteCard: View {
    @EnvironmentObject private var themeStore: ThemeStore

    let item: CaptureInboxItem
    let relativeTimeText: String
    let selectionMode: Bool
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    if selectionMode {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 22))
                            .foregroundStyle(isSelected ? themeStore.accentColor : .secondary.opacity(0.5))
                            .frame(width: 24, alignment: .leading)
                    } else {
                        Image(systemName: "quote.opening")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(themeStore.accentColor.opacity(0.8))
                            .frame(width: 24, alignment: .leading)
                    }

                    Text(item.text)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(relativeTimeText)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(selectionMode ? "已选中后可批量删除或合并整理。" : "点开后可以继续编辑，或整理成任务与习惯。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 36)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .overlay {
                if selectionMode && isSelected {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(themeStore.accentColor.opacity(0.55), lineWidth: 1.5)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
