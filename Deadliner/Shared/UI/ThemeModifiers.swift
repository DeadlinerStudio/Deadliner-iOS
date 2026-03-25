//
//  ThemeModifiers.swift
//  Deadliner
//
//  Created by Codex on 2026/3/22.
//

import SwiftUI

private struct OptionalTintModifier: ViewModifier {
    let color: Color?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let color {
            content.tint(color)
        } else {
            content
        }
    }
}

extension View {
    func optionalTint(_ color: Color?) -> some View {
        modifier(OptionalTintModifier(color: color))
    }
}
