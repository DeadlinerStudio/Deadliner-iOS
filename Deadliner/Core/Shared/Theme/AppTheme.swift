//
//  AppTheme.swift
//  Deadliner
//
//  Created by Codex on 2026/3/22.
//

import SwiftUI

enum ThemeAccentOption: String, CaseIterable, Identifiable, Sendable {
    case systemDefault
    case blue
    case brown
    case cyan
    case gray
    case green
    case indigo
    case mint
    case orange
    case pink
    case purple
    case red
    case teal
    case yellow

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .systemDefault: return "经典"
        case .blue: return "晴空"
        case .brown: return "琥珀"
        case .cyan: return "冰川"
        case .gray: return "雾灰"
        case .green: return "森屿"
        case .indigo: return "深海"
        case .mint: return "薄荷"
        case .orange: return "落日"
        case .pink: return "樱语"
        case .purple: return "暮紫"
        case .red: return "绯红"
        case .teal: return "潮汐"
        case .yellow: return "晨光"
        }
    }

    var color: Color {
        switch self {
        case .systemDefault, .blue: return .blue
        case .brown: return .brown
        case .cyan: return .cyan
        case .gray: return .gray
        case .green: return .green
        case .indigo: return .indigo
        case .mint: return .mint
        case .orange: return .orange
        case .pink: return .pink
        case .purple: return .purple
        case .red: return .red
        case .teal: return .teal
        case .yellow: return .yellow
        }
    }

    var usesSystemControlBehavior: Bool {
        self == .systemDefault
    }
}

struct AIGlowPalette {
    let blue: Color
    let pink: Color
    let amber: Color

    static let brandDefault = AIGlowPalette(
        blue: Color(hex: "#6AA9FF"),
        pink: Color(hex: "#FF6AE6"),
        amber: Color(hex: "#FFC36A")
    )

    static func aiAdaptive(for accent: ThemeAccentOption) -> AIGlowPalette {
        let accentTriad = accentOnly(for: accent)
        return .init(
            blue: brandDefault.blue
                .vividBlend(with: accentTriad.blue, ratio: 0.42)
                .adjusted(saturationBy: -0.05, brightnessBy: 0.01),
            pink: brandDefault.pink
                .vividBlend(with: accentTriad.pink, ratio: 0.36)
                .adjusted(saturationBy: -0.06, brightnessBy: 0.01),
            amber: brandDefault.amber
                .vividBlend(with: accentTriad.amber, ratio: 0.32)
                .adjusted(saturationBy: -0.07, brightnessBy: 0.02)
        )
    }

    static func accentOnly(for accent: ThemeAccentOption) -> AIGlowPalette {
        switch accent {
        case .systemDefault:
            return .brandDefault
        case .blue:
            return .init(
                blue: .blue,
                pink: Color(hex: "#7B8CFF"),
                amber: Color(hex: "#6FD3FF")
            )
        case .brown:
            return .init(
                blue: Color(hex: "#B07D52"),
                pink: Color(hex: "#D59A73"),
                amber: Color(hex: "#F4C58C")
            )
        case .cyan:
            return .init(
                blue: .cyan,
                pink: Color(hex: "#78E7FF"),
                amber: Color(hex: "#A5FFF4")
            )
        case .gray:
            return .init(
                blue: Color(hex: "#94A3B8"),
                pink: Color(hex: "#C0CAD6"),
                amber: Color(hex: "#E2E8F0")
            )
        case .green:
            return .init(
                blue: .green,
                pink: Color(hex: "#6EE7B7"),
                amber: Color(hex: "#B7F27D")
            )
        case .indigo:
            return .init(
                blue: .indigo,
                pink: Color(hex: "#8B7CFF"),
                amber: Color(hex: "#6AC7FF")
            )
        case .mint:
            return .init(
                blue: .mint,
                pink: Color(hex: "#83F7D5"),
                amber: Color(hex: "#C6FFE4")
            )
        case .orange:
            return .init(
                blue: .orange,
                pink: Color(hex: "#FF8A65"),
                amber: Color(hex: "#FFD36E")
            )
        case .pink:
            return .init(
                blue: .pink,
                pink: Color(hex: "#FF8AD8"),
                amber: Color(hex: "#FFC38F")
            )
        case .purple:
            return .init(
                blue: .purple,
                pink: Color(hex: "#D28BFF"),
                amber: Color(hex: "#8FA8FF")
            )
        case .red:
            return .init(
                blue: .red,
                pink: Color(hex: "#FF7A8A"),
                amber: Color(hex: "#FFB86A")
            )
        case .teal:
            return .init(
                blue: .teal,
                pink: Color(hex: "#66E3D7"),
                amber: Color(hex: "#A6FFF1")
            )
        case .yellow:
            return .init(
                blue: .yellow,
                pink: Color(hex: "#FFD95A"),
                amber: Color(hex: "#FFF1A8")
            )
        }
    }
}

enum ThemeDefaults {
    static let fabColor = Color(hex: "#FFFF6D6D")
}
