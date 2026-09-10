//
//  AboutSettingsView.swift
//  Deadliner
//
//  Created by Codex on 2026/8/30.
//

import Foundation
import SwiftUI

#if canImport(Shared)
import Shared
#endif

struct AboutSettingsView: View {
    @AppStorage(OnboardingStorageKey.showOnNextLaunch) private var showOnboardingOnNextLaunch = false
    @AppStorage("selectedAppIcon") private var selectedAppIconRaw = DeadlinerIcon.deadlinerDefault.rawValue
    @State private var versionTapCount = 0
    @State private var showGuideUnlockedAlert = false

    var body: some View {
        ZStack {
            AboutFloatingGlowBackground()

            ScrollView {
                VStack(spacing: 28) {
                    appHeader
                    informationContainer

                    if versionTapCount > 0 {
                        Text("再点 \(10 - versionTapCount) 次软件版本，下次启动时重新显示新手引导。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    } else if showOnboardingOnNextLaunch {
                        Text("已设为下次启动时显示新手引导。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: 620)
                .padding(.horizontal, 20)
                .padding(.top, 30)
                .padding(.bottom, 44)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("版本信息")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .alert("已开启新手引导", isPresented: $showGuideUnlockedAlert) {
            Button("好的", role: .cancel) { }
        } message: {
            Text("下次打开 App 时，会重新显示新手引导页。")
        }
    }

    private var appHeader: some View {
        VStack(spacing: 14) {
            Image(iconPreviewAssetName)
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 23, style: .continuous)
                        .stroke(.white.opacity(0.34), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.16), radius: 20, y: 10)

            VStack(spacing: 7) {
                HStack(spacing: 8) {
                    Text("Deadliner")
                        .font(.system(.title, design: .rounded, weight: .bold))

                    Text("KMP")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            LinearGradient(
                                colors: [.blue, .indigo],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: Capsule()
                        )
                }

                Text("软件版本 \(softwareVersion)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var informationContainer: some View {
        VStack(spacing: 0) {
            Button(action: handleVersionInfoTap) {
                AboutInformationRow(
                    title: "软件版本",
                    value: softwareVersion,
                    systemImage: "app.badge.fill",
                    colors: [.blue, .cyan]
                )
            }
            .buttonStyle(.plain)
            .accessibilityHint("连续轻点十次可在下次启动时重新显示新手引导")

            insetDivider

            AboutInformationRow(
                title: "内核版本",
                value: coreVersion,
                systemImage: "cpu.fill",
                colors: [.purple, .pink],
                usesMonospacedValue: true
            )

            insetDivider

            NavigationLink(destination: LogDiagnosticsView()) {
                AboutInformationRow(
                    title: "日志与诊断",
                    value: "导出或清空应用日志",
                    systemImage: "waveform.path.ecg.rectangle.fill",
                    colors: [.orange, .red],
                    showsDisclosureIndicator: true
                )
            }
            .buttonStyle(.plain)
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.22), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 28, y: 14)
    }

    private var insetDivider: some View {
        Divider()
            .padding(.leading, 66)
    }

    private var softwareVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private var coreVersion: String {
        #if canImport(Shared)
        DeadlinerCoreVersion.shared.value
        #else
        "KMP 内核不可用"
        #endif
    }

    private var iconPreviewAssetName: String {
        let selected = DeadlinerIcon(rawValue: selectedAppIconRaw) ?? .deadlinerDefault
        let resolved = selected == .autoSeason ? selected.resolvedIcon() : selected
        return resolved.previewAssetName
    }

    private func handleVersionInfoTap() {
        withAnimation(.easeInOut(duration: 0.2)) {
            versionTapCount += 1
        }

        guard versionTapCount >= 10 else { return }

        showOnboardingOnNextLaunch = true
        versionTapCount = 0
        showGuideUnlockedAlert = true
    }
}

private struct AboutInformationRow: View {
    let title: String
    let value: String
    let systemImage: String
    let colors: [Color]
    var usesMonospacedValue = false
    var showsDisclosureIndicator = false

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: colors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 38, height: 38)
            .shadow(color: colors.first?.opacity(0.24) ?? .clear, radius: 8, y: 4)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)

                Text(value)
                    .font(usesMonospacedValue ? .system(size: 12, design: .monospaced) : .subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(usesMonospacedValue ? 3 : 1)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if showsDisclosureIndicator {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
    }
}

private struct AboutFloatingGlowBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            GeometryReader { proxy in
                let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                let width = proxy.size.width
                let height = proxy.size.height

                ZStack {
                    Color(uiColor: .systemGroupedBackground)

                    glowOrb(
                        color: .blue,
                        size: 330,
                        x: width * 0.10 + CGFloat(sin(time / 7.5)) * 48,
                        y: height * 0.18 + CGFloat(cos(time / 6.4)) * 44
                    )

                    glowOrb(
                        color: .pink,
                        size: 290,
                        x: width * 0.88 + CGFloat(cos(time / 5.6)) * 54,
                        y: height * 0.40 + CGFloat(sin(time / 7.0)) * 62
                    )

                    glowOrb(
                        color: .orange,
                        size: 260,
                        x: width * 0.30 + CGFloat(sin(time / 6.4)) * 60,
                        y: height * 0.86 + CGFloat(cos(time / 7.8)) * 46
                    )
                }
                .frame(width: width, height: height)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func glowOrb(color: Color, size: CGFloat, x: CGFloat, y: CGFloat) -> some View {
        Circle()
            .fill(color.opacity(colorScheme == .dark ? 0.20 : 0.15))
            .frame(width: size, height: size)
            .blur(radius: 78)
            .position(x: x, y: y)
    }
}

private struct LogDiagnosticsView: View {
    @State private var showLogShare = false
    @State private var logURL: URL?
    @State private var showLogClearedAlert = false

    var body: some View {
        List {
            Section("导出日志") {
                Button {
                    exportLog(format: .standard)
                } label: {
                    Label("导出标准应用日志", systemImage: "doc.text.fill")
                }

                Button {
                    exportLog(format: .json)
                } label: {
                    Label("导出 JSON 应用日志", systemImage: "curlybraces.square.fill")
                }
            }

            Section {
                Button("清空应用日志", systemImage: "trash.fill", role: .destructive) {
                    _Concurrency.Task {
                        try? await AppLog.clear()
                        showLogClearedAlert = true
                    }
                }
            } footer: {
                Text("标准日志格式为 [时间][KMP/Native][模块] 内容；也可导出 JSON。日志跨重启保留最多 14 天或 8 MiB。")
            }
        }
        .deadlinerScrollEdgeEffect(forceImmersive: false)
        .deadlinerContainerSystemBackground()
        .navigationTitle("日志与诊断")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showLogShare) {
            if let logURL {
                ActivityView(activityItems: [logURL])
            }
        }
        .alert("应用日志已清空", isPresented: $showLogClearedAlert) {
            Button("好的", role: .cancel) { }
        }
    }

    private func exportLog(format: AppLogExportFormat) {
        _Concurrency.Task {
            logURL = await AppLog.exportURL(format: format)
            showLogShare = true
        }
    }
}
