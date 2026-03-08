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
    
    var isSelected: Bool = false
    var selectionMode: Bool = false
    var canToggle: Bool = true
    
    var onToggle: (() -> Void)? = nil
    var onLongPress: (() -> Void)? = nil
    
    private let corner: CGFloat = 24
    private let height: CGFloat = 72
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var progress: CGFloat {
        let target = max(1, targetCount)
        return min(1.0, max(0.0, CGFloat(doneCount) / CGFloat(target)))
    }
    
    private var bottomLine: String {
        var text = "\(doneCount)/\(targetCount)"
        if habit.goalType == .total {
            let total = habit.totalTarget.map { String($0) } ?? "∞"
            text = "\(doneCount)/\(total)"
        }
        if let rem = remainingText, !rem.isEmpty {
            text = "\(rem) · \(text)"
        }
        return text
    }
    
    private var rightLabel: String {
        if habit.goalType == .perPeriod {
            return habit.period.rawValue.capitalized
        } else {
            return "Total"
        }
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
                HStack(spacing: 12) {
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
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(habit.name)
                            .font(.system(size: 16, weight: .medium))
                            .lineLimit(1)
                        
                        Text(bottomLine)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
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
            if canToggle { onToggle?() }
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                onLongPress?()
            }
        )
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
