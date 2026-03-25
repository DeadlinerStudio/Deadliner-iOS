//
//  ThemeStore.swift
//  Deadliner
//
//  Created by Codex on 2026/3/22.
//

import SwiftUI
import Combine

@MainActor
final class ThemeStore: ObservableObject {
    @Published private(set) var accentOption: ThemeAccentOption
    @Published private(set) var overlayEnabled: Bool
    @Published private(set) var useAccentPaletteWhenAI: Bool

    private let defaults: UserDefaults

    private enum Key {
        static let accentOption = "settings.theme.accent_option"
        static let overlayEnabled = "settings.theme.overlay.enabled"
        static let useAccentPaletteWhenAI = "settings.theme.ai_glow.use_accent_palette_when_ai"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        defaults.register(defaults: [
            Key.accentOption: ThemeAccentOption.systemDefault.rawValue,
            Key.overlayEnabled: true,
            Key.useAccentPaletteWhenAI: false
        ])

        accentOption = ThemeAccentOption(rawValue: defaults.string(forKey: Key.accentOption) ?? "") ?? .systemDefault
        overlayEnabled = defaults.bool(forKey: Key.overlayEnabled)
        useAccentPaletteWhenAI = defaults.bool(forKey: Key.useAccentPaletteWhenAI)
    }

    var accentColor: Color {
        accentOption.color
    }

    var fabColor: Color {
        accentOption.usesSystemControlBehavior ? ThemeDefaults.fabColor : accentOption.color
    }

    var switchTint: Color? {
        accentOption.usesSystemControlBehavior ? nil : accentOption.color
    }

    func overlayPalette(isAIConfigured: Bool) -> AIGlowPalette {
        if !isAIConfigured || useAccentPaletteWhenAI {
            return .accentOnly(for: accentOption)
        }

        return accentOption == .systemDefault ? .brandDefault : .aiAdaptive(for: accentOption)
    }

    func setAccentOption(_ option: ThemeAccentOption) {
        accentOption = option
        defaults.set(option.rawValue, forKey: Key.accentOption)
    }

    func setOverlayEnabled(_ enabled: Bool) {
        overlayEnabled = enabled
        defaults.set(enabled, forKey: Key.overlayEnabled)
    }

    func setUseAccentPaletteWhenAI(_ enabled: Bool) {
        useAccentPaletteWhenAI = enabled
        defaults.set(enabled, forKey: Key.useAccentPaletteWhenAI)
    }
}
