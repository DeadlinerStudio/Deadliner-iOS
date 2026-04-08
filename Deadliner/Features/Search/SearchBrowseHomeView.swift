//
//  SearchBrowseHomeView.swift
//  Deadliner
//
//  Created by Codex on 2026/4/2.
//

import SwiftUI

struct SearchBrowseHomeView: View {
    private let browseCategories: [SearchBrowseCategory] = [.today, .upcoming, .starred, .archived]
    private let typeCategories: [SearchBrowseCategory] = [.tasks, .habits]

    var body: some View {
        Group {
            Section("浏览") {
                ForEach(browseCategories) { category in
                    browseLinkRow(category)
                }
            }

            Section("内容类型") {
                ForEach(typeCategories) { category in
                    browseLinkRow(category)
                }
            }
        }
    }

    private func browseLinkRow(_ category: SearchBrowseCategory) -> some View {
        Group {
            if category == .archived {
                NavigationLink {
                    SearchArchiveContainerView()
                } label: {
                    browseRowLabel(category)
                }
            } else {
                NavigationLink(value: category) {
                    browseRowLabel(category)
                }
            }
        }
    }

    private func browseRowLabel(_ category: SearchBrowseCategory) -> some View {
        Label {
            Text(category.title)
                .foregroundStyle(.primary)
        } icon: {
            Image(systemName: category.systemImage)
                .foregroundStyle(category.tint)
        }
    }
}
