//
//  DDLItemCard.swift
//  Deadliner
//
//  Created by Aritx 音唯 on 2026/2/16.
//

import SwiftUI

struct DDLItemCard: View {
    let title: String
    let remainingTimeAlt: String
    let note: String
    let progress: CGFloat   // 0...1
    let isStarred: Bool
    var categoryBadge: CategoryBadgeModel? = nil
    var status: DDLStatus = .undergo
    var onTap: (() -> Void)? = nil

    private let corner: CGFloat = 28
    private let height: CGFloat = 76

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let p = max(0, min(progress, 1))
        let style = DDLStatusStyle.from(status, scheme: colorScheme)

        Button {
            onTap?()
        } label: {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(style.background)

                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 0, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [style.indicator.opacity(0.45), style.indicator],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * p)
                }
                .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {  // 默认 .center 对齐
                        if isStarred {
                            Image(systemName: "star.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(style.indicator)
                        }

                        Text(title)
                            .font(.title3.weight(.bold))
                            .lineLimit(1)
                        
                        Text(" ").font(.title3.weight(.bold)).frame(width: 0).opacity(0)

                        Spacer(minLength: 8)

                        if let categoryBadge {
                            CategoryBadgeView(badge: categoryBadge,
                                              backgroundColor: Color(UIColor.secondarySystemBackground))
                        }

                        Text(remainingTimeAlt)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 24)

                    // 备注行始终占位，保证有/无备注时标题的纵向位置不变
                    HStack {
                        Text(note.isEmpty ? "\u{00A0}" : note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .opacity(note.isEmpty ? 0 : 1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .frame(height: height)
        }
        .buttonStyle(.plain)
    }
}

struct DDLItemCardSwipeable: View {
    let title: String
    let remainingTimeAlt: String
    let note: String
    let progress: CGFloat
    let isStarred: Bool
    var categoryBadge: CategoryBadgeModel? = nil
    var status: DDLStatus = .undergo

    var selectionMode: Bool = false
    var selected: Bool = false

    var onTap: (() -> Void)? = nil
    var onLongPressSelect: (() -> Void)? = nil
    var onToggleSelect: (() -> Void)? = nil

    var onComplete: () -> Void
    var onDelete: () -> Void
    var onGiveUp: (() -> Void)? = nil
    
    var onArchive: (() -> Void)? = nil
    var onEdit: (() -> Void)? = nil
    var onFocus: (() -> Void)? = nil

    private let corner: CGFloat = 28
    @State private var suppressNextTapAfterLongPress = false

    var body: some View {
        ZStack {
            DDLItemCard(
                title: title,
                remainingTimeAlt: remainingTimeAlt,
                note: note,
                progress: progress,
                isStarred: isStarred,
                categoryBadge: categoryBadge,
                status: status,
                onTap: {
                    if suppressNextTapAfterLongPress {
                        suppressNextTapAfterLongPress = false
                        return
                    }
                    if selectionMode {
                        onToggleSelect?()
                    } else {
                        onTap?()
                    }
                }
            )
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.35).onEnded { _ in
                    suppressNextTapAfterLongPress = true
                    if let onLongPressSelect {
                        onLongPressSelect()
                    } else {
                        onEdit?()
                    }
                }
            )
            .swipeActions(edge: .trailing, allowsFullSwipe: !selectionMode) {
                if !selectionMode {
                    Button {
                        onDelete()
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                    .tint(.red)

                    Button {
                        onEdit?()
                    } label: {
                        Label("编辑", systemImage: "pencil")
                    }
                    .tint(.blue)
                }
            }
            .swipeActions(edge: .leading, allowsFullSwipe: !selectionMode) {
                if !selectionMode {
                    if status == .completed {
                        Button {
                            onComplete()
                        } label: {
                            Label("撤销完成", systemImage: "arrow.uturn.backward")
                        }
                        .tint(.green)

                        Button {
                            onArchive?()
                        } label: {
                            Label("归档", systemImage: "archivebox")
                        }
                        .tint(.gray)
                    } else if status == .abandoned {
                        Button {
                            onGiveUp?()
                        } label: {
                            Label("恢复", systemImage: "arrow.uturn.backward.circle")
                        }
                        .tint(.orange)

                        Button {
                            onArchive?()
                        } label: {
                            Label("归档", systemImage: "archivebox")
                        }
                        .tint(.gray)
                    } else {
                        Button {
                            onComplete()
                        } label: {
                            Label("完成", systemImage: "checkmark")
                        }
                        .tint(.green)

                        if let onFocus {
                            Button(action: onFocus) { Label("专注", systemImage: "timer") }
                                .tint(.indigo).accessibilityIdentifier("focus.entry.task")
                        }

                        if onGiveUp != nil {
                            Button {
                                onGiveUp?()
                            } label: {
                                Label("放弃", systemImage: "flag")
                            }
                            .tint(.orange)
                        }
                    }
                }
            }


            if selectionMode && selected {
                SelectionOverlay(cornerRadius: corner)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}
