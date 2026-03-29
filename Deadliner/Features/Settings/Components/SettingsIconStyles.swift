//
//  SettingsIconStyles.swift
//  Deadliner
//
//  Created by Codex on 2026/3/28.
//

import SwiftUI

struct SettingsIconPalette {
    let colors: [Color]

    static let ocean = SettingsIconPalette(colors: [.blue, .cyan])
    static let sky = SettingsIconPalette(colors: [.indigo, .blue])
    static let mint = SettingsIconPalette(colors: [.mint, .teal])
    static let sunrise = SettingsIconPalette(colors: [.orange, .pink])
    static let grape = SettingsIconPalette(colors: [.purple, .pink])
    static let amber = SettingsIconPalette(colors: [.yellow, .orange])
    static let rose = SettingsIconPalette(colors: [.pink, .red])
}

struct SettingsTintBadgeIcon: View {
    let systemName: String
    let colors: [Color]
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: colors,
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            Image(systemName: systemName)
                .font(.system(size: size * 0.56, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

struct SettingsGradientBadgeIcon: View {
    let systemName: String
    let palette: SettingsIconPalette
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.34, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: palette.colors,
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: size * 0.34, style: .continuous)
                        .fill(.white.opacity(0.16))
                        .blur(radius: 4)
                        .mask(alignment: .top) {
                            RoundedRectangle(cornerRadius: size * 0.34, style: .continuous)
                                .frame(height: size * 0.58)
                        }
                }

            Image(systemName: systemName)
                .font(.system(size: size * 0.56, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: palette.colors.last?.opacity(0.22) ?? .clear, radius: 8, x: 0, y: 4)
    }
}

struct SettingsGradientSymbolIcon: View {
    let systemName: String
    let palette: SettingsIconPalette
    var size: CGFloat = 18

    var body: some View {
        LinearGradient(
            colors: palette.colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .mask {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 24)
        }
        .frame(width: 24, height: 24)
    }
}

struct SettingsListLabel: View {
    enum Style {
        case main
        case detail
    }

    let title: String
    let systemImage: String
    var palette: SettingsIconPalette?
    var tintColors: [Color]?
    var style: Style = .main

    var body: some View {
        HStack(spacing: 12) {
            switch style {
            case .main:
                if let tintColors {
                    SettingsTintBadgeIcon(systemName: systemImage, colors: tintColors)
                } else if let palette {
                    SettingsGradientBadgeIcon(systemName: systemImage, palette: palette)
                }
            case .detail:
                if let palette {
                    SettingsGradientSymbolIcon(systemName: systemImage, palette: palette)
                } else if let tintColors, let first = tintColors.first {
                    SettingsGradientSymbolIcon(
                        systemName: systemImage,
                        palette: SettingsIconPalette(colors: [first, first.opacity(0.82)])
                    )
                }
            }

            Text(title)
                .foregroundStyle(.primary)
        }
    }
}

struct SettingsRowEntranceModifier: ViewModifier {
    let isVisible: Bool
    let index: Int

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .scaleEffect(isVisible ? 1 : 0.965)
            .offset(y: isVisible ? 0 : 16)
            .blur(radius: isVisible ? 0 : 3)
            .animation(
                .spring(response: 0.56, dampingFraction: 0.86)
                .delay(Double(index) * 0.045),
                value: isVisible
            )
    }
}

extension View {
    func settingsRowEntrance(isVisible: Bool, index: Int) -> some View {
        modifier(SettingsRowEntranceModifier(isVisible: isVisible, index: index))
    }
}
