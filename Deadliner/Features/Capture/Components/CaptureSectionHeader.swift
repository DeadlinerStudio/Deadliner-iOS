//
//  CaptureSectionHeader.swift
//  Deadliner
//
//  Created by Codex on 2026/4/8.
//

import SwiftUI

struct CaptureSectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .textCase(nil)
        .padding(.horizontal, 16)
    }
}
