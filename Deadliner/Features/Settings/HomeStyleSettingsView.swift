//
//  HomeStyleSettingsView.swift
//  Deadliner
//
//  Created by Codex on 2026/3/30.
//

import SwiftUI

enum HomeStyleOption: String, CaseIterable, Identifiable {
    case focus
    case rich

    var id: String { rawValue }

    var title: String {
        switch self {
        case .focus: return "聚焦模式"
        case .rich: return "丰富模式"
        }
    }

    var summary: String {
        switch self {
        case .focus:
            return "保留当前以底部工具栏为核心的主界面。"
        case .rich:
            return "使用 Tab 导航、独立 AI 页面和悬浮添加按钮。"
        }
    }
}

struct HomeStyleSettingsView: View {
    @AppStorage("settings.home.style") private var homeStyleRawValue: String = HomeStyleOption.rich.rawValue

    var body: some View {
        List {
            Section("主页风格") {
                ForEach(HomeStyleOption.allCases) { option in
                    Button {
                        homeStyleRawValue = option.rawValue
                    } label: {
                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(option.title)
                                    .foregroundStyle(.primary)
                                Text(option.summary)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if selectedOption == option {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("主页风格")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var selectedOption: HomeStyleOption {
        HomeStyleOption(rawValue: homeStyleRawValue) ?? .rich
    }
}
