//
//  GradientProgressBar.swift
//  Deadliner
//
//  Created by Codex on 2026/4/18.
//

import SwiftUI

struct GradientProgressBar: View {
    let progress: CGFloat
    var height: CGFloat = 12
    var cornerRadius: CGFloat? = nil
    var trackColor: Color = Color.secondary.opacity(0.18)
    var gradientColors: [Color] = [.blue, .cyan]
    var startPoint: UnitPoint = .leading
    var endPoint: UnitPoint = .trailing

    private var clampedProgress: CGFloat {
        min(max(progress, 0), 1)
    }

    private var resolvedCornerRadius: CGFloat {
        cornerRadius ?? (height / 2)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: resolvedCornerRadius, style: .continuous)
                    .fill(trackColor)

                RoundedRectangle(cornerRadius: resolvedCornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: gradientColors,
                            startPoint: startPoint,
                            endPoint: endPoint
                        )
                    )
                    .frame(width: geo.size.width * clampedProgress)
                    .opacity(clampedProgress > 0.001 ? 1 : 0)
                    .animation(.easeInOut(duration: 0.2), value: clampedProgress > 0.001)
            }
        }
        .frame(height: height)
    }
}
