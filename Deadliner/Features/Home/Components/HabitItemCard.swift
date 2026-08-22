//
//  HabitItemCard.swift
//  Deadliner
//
//  Created by Gemini CLI on 2026/3/7.
//

import SwiftUI

struct HabitItemCard: View {
    let habit: Habit
    let doneCount: Int
    let targetCount: Int
    let isCompleted: Bool
    let status: DDLStatus
    let remainingText: String?
    var sharedProgressText: String? = nil
    var sharedScheduleLabel: String? = nil
    var categoryBadge: CategoryBadgeModel? = nil
    
    var isSelected: Bool = false
    var selectionMode: Bool = false
    var canToggle: Bool = true
    
    var onToggle: (() -> Void)? = nil
    var onToggleSelect: (() -> Void)? = nil
    var onLongPress: (() -> Void)? = nil
    
    private let corner: CGFloat = 24
    private let height: CGFloat = 72
    @State private var suppressNextTapAfterLongPress = false
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var progress: CGFloat {
        let target = max(1, targetCount)
        return min(1.0, max(0.0, CGFloat(doneCount) / CGFloat(target)))
    }
    
    private var bottomLine: String {
        var text = sharedProgressText ?? "\(doneCount)/\(targetCount)"
        if sharedProgressText == nil && habit.goalType == .total {
            let total = habit.totalTarget.map { String($0) } ?? "∞"
            text = "\(doneCount)/\(total)"
        }
        if let rem = remainingText, !rem.isEmpty {
            text = "\(rem) · \(text)"
        }
        return text
    }
    
    private var rightLabel: String {
        if let sharedScheduleLabel, !sharedScheduleLabel.isEmpty {
            return sharedScheduleLabel
        }
        if habit.goalType == .perPeriod {
            return habit.period.rawValue.capitalized
        } else {
            return "Total"
        }
    }

    private var accessibilityState: String {
        if isCompleted { return "已完成" }
        if !canToggle { return "当前日期不可打卡" }
        return "未完成"
    }

    private var accessibilityHint: String {
        if selectionMode { return "双击选择或取消选择" }
        if canToggle { return "双击打卡，长按打开更多操作" }
        return "长按打开更多操作"
    }
    
    var body: some View {
        let style = DDLStatusStyle.from(status, scheme: colorScheme)
        
        ZStack {
            // 1. 内容层与背景进度
            ZStack(alignment: .leading) {
                // 底色
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(style.background)
                
                // 进度条前景 (对标鸿蒙的渐变前景)
                if progress > 0 {
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 0, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [style.indicator.opacity(0.5), style.indicator.opacity(0.7)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * progress)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                }
                
                // 文本与交互行
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    // Checkbox (模拟鸿蒙版样式)
                    Button {
                        if canToggle { onToggle?() }
                    } label: {
                        Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 24))
                            .foregroundStyle(isCompleted ? style.indicator : .secondary.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canToggle)
                    .alignmentGuide(.firstTextBaseline) { context in
                        context[VerticalAlignment.center]
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(habit.name)
                                .font(.system(size: 16, weight: .medium))
                                .lineLimit(1)

                            // 分类徽章跟在名称后；无徽章时以同高度占位，保持名称纵向位置稳定
                            Group {
                                if let categoryBadge {
                                    CategoryBadgeView(badge: categoryBadge, backgroundColor: Color(UIColor.secondarySystemBackground))
                                } else {
                                    Color.clear.frame(width: 20, height: 20)
                                }
                            }
                            .alignmentGuide(.firstTextBaseline) { context in
                                context[VerticalAlignment.center]
                            }
                        }

                        Text(bottomLine)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text(rightLabel)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
            }
            .frame(height: height)
            
            // 2. 选中态遮罩层 (对标 HabitSelectionOverlay)
            if selectionMode && isSelected {
                SelectionOverlay(cornerRadius: corner)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: corner))
        .onTapGesture {
            if suppressNextTapAfterLongPress {
                suppressNextTapAfterLongPress = false
                return
            }
            if selectionMode {
                onToggleSelect?()
            } else if canToggle {
                onToggle?()
            }
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                suppressNextTapAfterLongPress = true
                if selectionMode {
                    onToggleSelect?()
                } else {
                    onLongPress?()
                }
            }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(habit.name)
        .accessibilityValue("\(bottomLine)，\(rightLabel)，\(accessibilityState)")
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
//
//// 复用或模拟 SelectionOverlay
//struct SelectionOverlay: View {
//    let cornerRadius: CGFloat
//    
//    var body: some View {
//        ZStack(alignment: .topLeading) {
//            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
//                .fill(.background.opacity(0.25))
//            
//            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
//                .stroke(Color.accentColor, lineWidth: 2)
//                .opacity(0.7)
//            
//            Image(systemName: "checkmark")
//                .font(.system(size: 12, weight: .bold))
//                .foregroundStyle(.white)
//                .frame(width: 24, height: 24)
//                .background(Color.accentColor)
//                .clipShape(Circle())
//                .shadow(radius: 2)
//                .padding(8)
//        }
//    }
//}
