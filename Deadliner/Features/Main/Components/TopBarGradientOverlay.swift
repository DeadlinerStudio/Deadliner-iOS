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

    var body: some View {
        let p = min(max(progress, 0), 1)

        // 高度随滚动缩短
        let h: CGFloat = max(0, 280 - 240 * p)

        let baseAlpha: CGFloat = colorScheme == .dark ? 0.60 : 0.95
        let topAlpha: CGFloat = max(0, baseAlpha - 0.50 * p)

        ZStack {
            if isAIConfigured {
                AIVibrantGlowView()
            } else {
                LinearGradient(
                    colors: [
                        Color.accentColor.opacity(1.0),
                        Color.accentColor.opacity(0.55),
                        Color.accentColor.opacity(0.20)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
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
    }
}

/// 色彩饱满、不发灰的三色非线性渐变
private struct AIVibrantGlowView: View {
    @Environment(\.colorScheme) private var colorScheme
    
    private let blueColor  = Color(red: 106/255, green: 169/255, blue: 1.0)      // #6AA9FF
    private let pinkColor  = Color(red: 1.0,     green: 106/255, blue: 230/255)  // #FF6AE6
    private let amberColor = Color(red: 1.0,     green: 195/255, blue: 106/255)  // #FFC36A
    

    var body: some View {
        GeometryReader { proxy in
            let h = proxy.size.height
            
            let mid = colorScheme == .dark ? 0.6 : 0.85
            
            ZStack {
                RadialGradient(
                    colors: [blueColor, blueColor.opacity(mid), blueColor.opacity(0)],
                    center: UnitPoint(x: 0.15, y: 0.35),
                    startRadius: 0,
                    endRadius: h * 1.2
                )
                
                RadialGradient(
                    colors: [pinkColor, pinkColor.opacity(mid), pinkColor.opacity(0)],
                    center: UnitPoint(x: 0.85, y: 0.35),
                    startRadius: 0,
                    endRadius: h * 1.2
                )
                
                RadialGradient(
                    colors: [amberColor, amberColor.opacity(mid), amberColor.opacity(0)],
                    center: UnitPoint(x: 0.50, y: 0.88),
                    startRadius: 0,
                    endRadius: h * 1.1
                )
            }
        }
    }
}
