//
//  IconSettingsView.swift
//  Deadliner
//
//  Created by Aritx 音唯 on 2026/2/22.
//

import SwiftUI
import UIKit

// MARK: - App Icon Model
enum DeadlinerIcon: String, CaseIterable, Identifiable {
    case deadlinerDefault = "DeadlinerDefault"
    case blackGold        = "DeadlinerBlackGold"
    case pixel            = "DeadlinerPixel"
    case lifi             = "LifiAI"
    case spring           = "DeadlinerSpring"
    case summer           = "DeadlinerSummer"
    case autumn           = "DeadlinerAutumn"
    case winter           = "DeadlinerWinter"
    case autoSeason       = "AutoSeason" // UI strategy, not a system icon name

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .deadlinerDefault: return "默认"
        case .blackGold:        return "黑金"
        case .pixel:            return "像素"
        case .lifi:             return "Lifi AI"
        case .spring:           return "春"
        case .summer:           return "夏"
        case .autumn:           return "秋"
        case .winter:           return "冬"
        case .autoSeason:       return "四季"
        }
    }

    var previewAssetName: String { "IconPreview-\(rawValue)" }

    /// Resolve the actual icon to apply.
    /// autoSeason -> seasonal icon by solar terms.
    func resolvedIcon(for date: Date = Date(),
                      calendar: Calendar = .current,
                      timeZone: TimeZone = .current) -> DeadlinerIcon {
        switch self {
        case .autoSeason:
            let s = SeasonUtils.season(for: date, calendar: calendar, timeZone: timeZone)
            return iconForSeason(s)
        default:
            return self
        }
    }

    /// Map Season -> DeadlinerIcon (must be in this file to avoid circular dependency)
    private func iconForSeason(_ s: Season) -> DeadlinerIcon {
        switch s {
        case .spring: return .spring
        case .summer: return .summer
        case .autumn: return .autumn
        case .winter: return .winter
        }
    }

    /// setAlternateIconName needs this value:
    /// - nil means primary icon
    var alternateIconName: String? {
        switch self {
        case .deadlinerDefault: return nil
        case .blackGold:        return "DeadlinerBlackGold"
        case .pixel:            return "DeadlinerPixel"
        case .lifi:             return "LifiAI"
        case .spring:           return "DeadlinerSpring"
        case .summer:           return "DeadlinerSummer"
        case .autumn:           return "DeadlinerAutumn"
        case .winter:           return "DeadlinerWinter"
        case .autoSeason:
            // Strategy only. Apply resolvedIcon().alternateIconName instead.
            return nil
        }
    }
}

// MARK: - View
struct IconSettingsView: View {
    @AppStorage("selectedAppIcon") private var selectedAppIconRaw: String = DeadlinerIcon.deadlinerDefault.rawValue
    @AppStorage("userTier") private var userTier: UserTier = .free
    @State private var isApplying = false
    @State private var errorMessage: String?
    @State private var showPaywall = false

    private var selectedIcon: DeadlinerIcon {
        get { DeadlinerIcon(rawValue: selectedAppIconRaw) ?? .deadlinerDefault }
        set { selectedAppIconRaw = newValue.rawValue }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("选择你喜欢的 Deadliner 图标。更换后会立即生效。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if userTier == .free {
                        Text("当前为 FREE 用户：可浏览全部图标预览，升级 Geek 后可切换图标。")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }

                    if !UIApplication.shared.supportsAlternateIcons {
                        Text("当前系统不支持自定义图标。")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    if selectedIcon == .autoSeason {
                        Text("已启用四季图标（节气）：在进入 App 或回到前台时会自动更新为当前季节。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("图标") {
                ForEach(DeadlinerIcon.allCases) { icon in
                    Button {
                        apply(icon)
                    } label: {
                        HStack(spacing: 12) {
                            iconPreviewView(for: icon)
                                .frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                            Text(icon.displayName)
                                .foregroundStyle(.primary)

                            Spacer()

                            if isApplying && icon == selectedIcon {
                                ProgressView()
                            } else if icon == selectedIcon {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                                    .font(.body.weight(.semibold))
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isApplying)
                }
            }
        }
        .navigationTitle("自定义图标")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPaywall) {
            ProPaywallView().presentationDetents([.large])
        }
        .onAppear {
            syncFromSystemIconIfPossible()
            applyAutoSeasonIfNeeded()
        }
    }
    
    @ViewBuilder
    private func iconPreviewView(for icon: DeadlinerIcon) -> some View {
        if icon == .autoSeason {
            SeasonIconCarouselPreview()
        } else {
            Image(icon.previewAssetName)
                .resizable()
                .scaledToFill()
        }
    }

    private func apply(_ icon: DeadlinerIcon) {
        guard userTier != .free else {
            showPaywall = true
            return
        }

        guard UIApplication.shared.supportsAlternateIcons else {
            errorMessage = "系统不支持自定义图标。"
            return
        }

        if icon == selectedIcon { return }

        isApplying = true
        errorMessage = nil

        let target = icon.resolvedIcon()
        let targetAlternateName = target.alternateIconName

        UIApplication.shared.setAlternateIconName(targetAlternateName) { error in
            DispatchQueue.main.async {
                self.isApplying = false
                if let error {
                    self.errorMessage = "更换失败：\(error.localizedDescription)"
                } else {
                    self.selectedAppIconRaw = icon.rawValue
                }
            }
        }
    }

    private func syncFromSystemIconIfPossible() {
        guard UIApplication.shared.supportsAlternateIcons else { return }

        // Respect stored strategy if it's autoSeason
        if selectedIcon == .autoSeason { return }

        let current = UIApplication.shared.alternateIconName
        if current == nil {
            selectedAppIconRaw = DeadlinerIcon.deadlinerDefault.rawValue
        } else if let mapped = DeadlinerIcon(rawValue: current!) {
            selectedAppIconRaw = mapped.rawValue
        } else {
            selectedAppIconRaw = DeadlinerIcon.deadlinerDefault.rawValue
        }
    }

    private func applyAutoSeasonIfNeeded() {
        guard UIApplication.shared.supportsAlternateIcons else { return }
        guard selectedIcon == .autoSeason else { return }

        let target = DeadlinerIcon.autoSeason.resolvedIcon()
        let currentName = UIApplication.shared.alternateIconName

        let currentIcon: DeadlinerIcon = {
            if currentName == nil { return .deadlinerDefault }
            return DeadlinerIcon(rawValue: currentName!) ?? .deadlinerDefault
        }()

        guard currentIcon != target else { return }

        UIApplication.shared.setAlternateIconName(target.alternateIconName, completionHandler: nil)
    }
}
