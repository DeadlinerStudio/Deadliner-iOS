//
//  FloatUpRow.swift
//  Deadliner
//
//  Created by Aritx 音唯 on 2026/2/27.
//

import SwiftUI

struct FloatUpRow<Content: View>: View {
    let index: Int
    var maxLoad: Int = 15
    var enable: Bool = true
    var animateToken: Int = 0
    @ViewBuilder var content: () -> Content

    @State private var isVisible: Bool = false

    private var delaySeconds: Double {
        let safeIndex = max(0, index)
        return Double((safeIndex % maxLoad)) * 0.05 // 50ms per item
    }

    var body: some View {
        content()
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 20)
            .onAppear {
                triggerAnimation()
            }
            // 当外部 Token 改变时（例如刷新或重排），重置并重新播放动画
            .onChange(of: animateToken) { _, _ in
                isVisible = false
                triggerAnimation()
            }
    }

    private func triggerAnimation() {
        guard enable else {
            isVisible = true
            return
        }
        
        withAnimation(
            .spring(response: 0.5, dampingFraction: 0.8)
            .delay(delaySeconds)
        ) {
            isVisible = true
        }
    }
}
