//
//  HabitProgressView.swift
//  Deadliner
//
//  Created by Aritx 音唯 on 2026/3/7.
//

import SwiftUI

struct HabitProgressView: View {
    @EnvironmentObject private var themeStore: ThemeStore

    let progress: Double
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("今日完成")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.caption.bold())
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText()) // 数字平滑切换
            }
            .padding(.horizontal, 4)
            
            LinearProgressView(value: progress, shape: Capsule())
                .frame(height: 8)
                .tint(themeStore.accentColor)
        }
        .padding(.horizontal, 16)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: progress)
    }
}
