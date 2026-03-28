//
//  TopBarGradientOverlay.swift
//  Deadliner
//
//  Created by Aritx 音唯 on 2026/2/20.
//

import SwiftUI

struct TopBarGradientOverlay: View {
    let progress: CGFloat   // 0...1
    let isAIConfigured: Bool

    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var themeStore: ThemeStore

    var body: some View {
        let p = min(max(progress, 0), 1)

        // 高度随滚动缩短
        let h: CGFloat = max(0, 340 - 340 * p)

        let baseAlpha: CGFloat = colorScheme == .dark ? 0.60 : 0.95
        let topAlpha: CGFloat = max(0, baseAlpha - 0.50 * p)

        ZStack {
            if themeStore.overlayEnabled {
                AIVibrantGlowView(palette: themeStore.overlayPalette(isAIConfigured: isAIConfigured))
            }
        }
        .frame(height: h)
        .allowsHitTesting(false)
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(topAlpha), location: 0.0),
                    .init(color: .black.opacity(0.0),      location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .ignoresSafeArea(edges: .top)
        .animation(.easeOut(duration: 0.15), value: p)
        .animation(.easeInOut(duration: 0.2), value: isAIConfigured)
        .animation(.easeInOut(duration: 0.2), value: themeStore.overlayEnabled)
    }
}

/// 色彩饱满、不发灰的三色非线性渐变
private struct AIVibrantGlowView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var isAnimating = false

    let palette: AIGlowPalette

    var body: some View {
        GeometryReader { proxy in
            let h = proxy.size.height
            let mid = colorScheme == .dark ? 0.6 : 0.85
            
            ZStack {
                RadialGradient(
                    colors: [palette.blue, palette.blue.opacity(mid), palette.blue.opacity(0)],
                    center: UnitPoint(
                        x: isAnimating ? 0.22 : 0.11,
                        y: isAnimating ? 0.28 : 0.40
                    ),
                    startRadius: 0,
                    endRadius: h * 1.2
                )
                .opacity(isAnimating ? 1.0 : 0.76)
                
                RadialGradient(
                    colors: [palette.pink, palette.pink.opacity(mid), palette.pink.opacity(0)],
                    center: UnitPoint(
                        x: isAnimating ? 0.78 : 0.90,
                        y: isAnimating ? 0.42 : 0.29
                    ),
                    startRadius: 0,
                    endRadius: h * 1.2
                )
                .opacity(isAnimating ? 0.82 : 1.0)
                
                RadialGradient(
                    colors: [palette.amber, palette.amber.opacity(mid), palette.amber.opacity(0)],
                    center: UnitPoint(
                        x: isAnimating ? 0.57 : 0.43,
                        y: isAnimating ? 0.79 : 0.93
                    ),
                    startRadius: 0,
                    endRadius: h * 1.1
                )
                .opacity(isAnimating ? 0.96 : 0.70)
            }
            .onAppear {
                guard !isAnimating else { return }
                withAnimation(.easeInOut(duration: 4.2).repeatForever(autoreverses: true)) {
                    isAnimating = true
                }
            }
        }
    }
}
