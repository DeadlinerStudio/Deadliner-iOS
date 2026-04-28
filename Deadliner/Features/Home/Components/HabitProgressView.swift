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
    
    @State private var animatedProgress: CGFloat = 0
    @State private var isAnimating = false
    @State private var animTask: Task<Void, Never>? = nil
    
    private var clampedProgress: CGFloat {
        min(max(CGFloat(progress), 0), 1)
    }
    
    private var progressPercent: Int {
        Int((animatedProgress * 100).rounded())
    }
    
    private var percentBlurRadius: CGFloat {
        guard isAnimating else { return 0 }
        let delta = abs(clampedProgress - animatedProgress)
        return delta > 0.001 ? max(0.4, delta * 18) : 0
    }
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("今日完成")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(progressPercent)%")
                    .font(.caption.bold())
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText()) // 数字平滑切换
                    .blur(radius: percentBlurRadius)
                    .animation(.easeInOut(duration: 0.75), value: progressPercent)
            }
            .padding(.horizontal, 4)
            
            GradientProgressBar(
                progress: animatedProgress,
                height: 10,
                gradientColors: [themeStore.accentColor.opacity(0.6), themeStore.accentColor]
            )
            .frame(height: 10)
            .animation(.easeInOut(duration: 0.75), value: animatedProgress)
        }
        .padding(.horizontal, 16)
        .onAppear {
            animateProgressIn()
        }
        .onChange(of: progress) { _, _ in
            animateProgressIn()
        }
        .onDisappear {
            animTask?.cancel()
        }
    }
    
    private func animateProgressIn() {
        animTask?.cancel()
        animatedProgress = 0
        isAnimating = false
        animTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            if Task.isCancelled { return }
            isAnimating = true
            withAnimation(.easeInOut(duration: 0.75)) {
                animatedProgress = clampedProgress
            }
            try? await Task.sleep(for: .milliseconds(700))
            if Task.isCancelled { return }
            isAnimating = false
        }
    }
}
