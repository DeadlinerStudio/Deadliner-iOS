//
//  SelectionOverlay.swift
//  Deadliner
//
//  Created by Aritx 音唯 on 2026/2/16.
//

import SwiftUI

struct SelectionOverlay: View {
    @EnvironmentObject private var themeStore: ThemeStore

    var cornerRadius: CGFloat = 28

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(themeStore.accentColor.opacity(0.18))

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(themeStore.accentColor.opacity(0.75), lineWidth: 2)

            ZStack {
                Circle()
                    .fill(themeStore.accentColor)
                    .frame(width: 24, height: 24)

                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
            .padding(8)
        }
        .allowsHitTesting(false)
    }
}
