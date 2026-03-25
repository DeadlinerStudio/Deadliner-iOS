//
//  WeekRow.swift
//  Deadliner
//
//  Created by Gemini CLI on 2026/3/7.
//

import SwiftUI

struct WeekRow: View {
    @EnvironmentObject private var themeStore: ThemeStore

    // 数据源
    let weekOverview: [DayOverview]
    let selectedDate: Date
    let currentDate: Date = Date()
    
    // 回调
    var onSelectDate: (Date) -> Void
    var onChangeWeek: (Int) -> Void // -1: 上一周, 1: 下一周
    
    // 动画状态
    @State private var animOffset: CGFloat = 0
    @State private var animOpacity: Double = 1.0
    
    private let calendar = Calendar.current
    private let haptic = UIImpactFeedbackGenerator(style: .light)
    
    // --- 逻辑判断方法 ---
    
    private func isSameDay(_ d1: Date, _ d2: Date) -> Bool {
        calendar.isDate(d1, inSameDayAs: d2)
    }
    
    private func getDayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE" // e.g., Mon, Tue
        return formatter.string(from: date)
    }
    
    private func getMonthTitle() -> (String, String) {
        guard !weekOverview.isEmpty else { return ("", "") }
        let firstDay = weekOverview[0].date
        let fYear = DateFormatter(); fYear.dateFormat = "yyyy"
        let fMonth = DateFormatter(); fMonth.dateFormat = "M"
        return (fYear.string(from: firstDay), fMonth.string(from: firstDay))
    }
    
    // --- 核心动画逻辑 ---
    
    private func triggerSwitchAnimation(direction: Int) {
        haptic.impactOccurred()
        let screenWidth: CGFloat = 300
        
        withAnimation(.easeOut(duration: 0.2)) {
            self.animOffset = direction == 1 ? -screenWidth : screenWidth
            self.animOpacity = 0
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.onChangeWeek(direction)
            self.animOffset = direction == 1 ? screenWidth : -screenWidth
            
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                self.animOffset = 0
                self.animOpacity = 1.0
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 8) {
            // 1. 顶部操作栏
            HStack {
                Button { triggerSwitchAnimation(direction: -1) } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44) // 增大点击区域
                        .background(Color.black.opacity(0.001)) // 确保透明区域也能响应点击
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                let title = getMonthTitle()
                HStack(spacing: 4) {
                    Text(title.0)
                        .font(.system(size: 16, weight: .medium))
                    Text("/")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(themeStore.accentColor)
                    Text(title.1)
                        .font(.system(size: 16, weight: .medium))
                }
                .opacity(animOpacity)
                
                Spacer()
                
                Button { triggerSwitchAnimation(direction: 1) } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44) // 增大点击区域
                        .background(Color.black.opacity(0.001)) // 确保透明区域也能响应点击
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)
            
            // 2. 日期列表
            HStack(spacing: 0) {
                ForEach(weekOverview) { day in
                    dayItem(day)
                        .frame(maxWidth: .infinity)
                }
            }
            .offset(x: animOffset)
            .opacity(animOpacity)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        self.animOffset = value.translation.width
                    }
                    .onEnded { value in
                        let threshold: CGFloat = 60
                        if value.translation.width < -threshold {
                            triggerSwitchAnimation(direction: 1)
                        } else if value.translation.width > threshold {
                            triggerSwitchAnimation(direction: -1)
                        } else {
                            withAnimation(.spring()) {
                                self.animOffset = 0
                            }
                        }
                    }
            )
        }
    }
    
    @ViewBuilder
    private func dayItem(_ day: DayOverview) -> some View {
        let isToday = isSameDay(day.date, currentDate)
        let isSelected = isSameDay(day.date, selectedDate)
        
        VStack(spacing: 4) {
            Text(getDayLabel(day.date))
                .font(.system(size: 12))
                .foregroundStyle(isToday ? themeStore.accentColor : .secondary)
                .fontWeight(isToday ? .bold : .regular)
            
            Text("\(calendar.component(.day, from: day.date))")
                .font(.system(size: 16, weight: (isToday || isSelected) ? .bold : .medium))
                .foregroundStyle(isToday ? themeStore.accentColor : (isSelected ? .primary : .secondary))
                .frame(width: 36, height: 36)
                .background(isSelected ? themeStore.accentColor.opacity(0.15) : Color.clear)
                .clipShape(Circle())
            
            if day.completionRatio > 0 {
                Circle()
                    .fill(themeStore.accentColor)
                    .frame(width: 5, height: 5)
            } else {
                Spacer().frame(height: 5)
            }
        }
        .onTapGesture {
            onSelectDate(day.date)
        }
    }
}
