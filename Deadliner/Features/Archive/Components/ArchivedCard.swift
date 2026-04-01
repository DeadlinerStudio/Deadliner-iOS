//
//  ArchivedCard.swift
//  Deadliner
//
//  Created by Aritx 音唯 on 2026/3/1.
//

import SwiftUI

struct ArchivedDDLItemCard: View {
    let title: String
    let startTime: String
    let completeTime: String
    let note: String
    var indicatorColor: Color = .blue
    var onUndo: () -> Void = {}
    var onDelete: () -> Void = {}

    private let corner: CGFloat = 28
    private let height: CGFloat = 84

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let backgroundColor = Color(uiColor: .secondarySystemBackground)
        
        ZStack(alignment: .leading) {
            // 卡片背景
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(backgroundColor)

            // 左侧指示条
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 0, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [indicatorColor.opacity(0.15), indicatorColor.opacity(0.3)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geo.size.width)
            }
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    // 标题
                    Text(title)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    // 时间信息 (起始 - 完成)
                    Text("\(startTime) - \(completeTime)")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)

                    // 备注 (如果有)
                    if !note.isEmpty {
                        Text(note)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 10) {
                    // 撤销归档按钮
                    Button(action: onUndo) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 36, height: 36)
                            .background(Color(uiColor: .systemGray5), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("撤销归档")

                    // 右侧删除按钮 (红色圆形)
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.red, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("永久删除")
                }
            }
            .padding(.horizontal, 20)
        }
        .frame(height: height)
    }
}
