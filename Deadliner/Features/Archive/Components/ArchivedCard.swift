//
//  ArchivedCard.swift
//  Deadliner
//
//  Created by Aritx 音唯 on 2026/3/1.
//


import SwiftUI

// MARK: - Theme (minimal, replace with your own)
struct ArchivedCardTheme {
    var indicatorUndergo: Color = .blue               // 你这里强制 Undergo 指示色
    var backgroundSecondary: Color = Color(.secondarySystemBackground)
    var backgroundPrimary: Color = Color(.systemBackground)

    var fontPrimary: Color = .primary
    var fontSecondary: Color = .secondary
    var fontTertiary: Color = Color(.tertiaryLabel)

    var warning: Color = .red
}

// MARK: - Card
struct ArchivedDDLItemCard: View {
    // Inputs
    let title: String
    let startTime: String
    let completeTime: String
    let note: String
    var onDelete: () -> Void = {}

    // Theme injection
    var theme: ArchivedCardTheme = .init()

    // Layout constants (matching ArkTS)
    private let height: CGFloat = 84
    private let corner: CGFloat = 24

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Background base layer (ArkTS: Row().backgroundColor(bgColor))
            theme.backgroundSecondary

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    // Title
                    Text(title)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(theme.fontPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Time: start - complete
                    Text("\(startTime) - \(completeTime)")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.fontTertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)

                    // Note (optional)
                    if !note.isEmpty {
                        Text(note)
                            .font(.system(size: 12))
                            .foregroundStyle(theme.fontSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Right: red delete button
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(width: 36, height: 36)
                        .background(theme.warning, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("删除")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .background(theme.backgroundPrimary) // ArkTS 外层 globalBgColor
    }
}
