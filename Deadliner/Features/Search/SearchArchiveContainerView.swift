//
//  SearchArchiveContainerView.swift
//  Deadliner
//
//  Created by Codex on 2026/4/3.
//

import SwiftUI

struct SearchArchiveContainerView: View {
    @EnvironmentObject private var themeStore: ThemeStore
    @State private var query: String = ""
    @State private var overlayProgress: CGFloat = 0

    var body: some View {
        ArchiveView(query: $query, onScrollProgressChange: { overlayProgress = $0 })
            .navigationTitle("归档")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $query, prompt: "搜索归档...")
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        NotificationCenter.default.post(name: .ddlDeleteAllArchived, object: nil)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel("删除所有归档")
                }
            }
            .background {
                ZStack(alignment: .top) {
                    Color(uiColor: .systemGroupedBackground)
                        .ignoresSafeArea()

                    SearchCategoryTopOverlay(
                        progress: overlayProgress,
                        palette: SearchBrowseCategory.archived.overlayPalette,
                        isEnabled: themeStore.overlayEnabled
                    )
                }
            }
    }
}
