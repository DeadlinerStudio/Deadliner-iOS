//
//  OnboardingView.swift
//  Deadliner
//
//  Created by Codex on 2026/4/27.
//

import SwiftUI

struct AppRootView: View {
    @AppStorage(OnboardingStorageKey.hasSeen) private var hasSeenOnboarding = false
    @AppStorage(OnboardingStorageKey.showOnNextLaunch) private var showOnboardingOnNextLaunch = false
    @State private var shouldPresentOnboarding = false
    @State private var launchDecisionMade = false

    var body: some View {
        Group {
            if shouldPresentOnboarding {
                OnboardingView {
                    hasSeenOnboarding = true
                    showOnboardingOnNextLaunch = false
                    shouldPresentOnboarding = false
                }
            } else if launchDecisionMade {
                MainView()
            } else {
                Color(uiColor: .systemBackground)
                    .ignoresSafeArea()
            }
        }
        .task {
            guard !launchDecisionMade else { return }
            shouldPresentOnboarding = !hasSeenOnboarding || showOnboardingOnNextLaunch
            launchDecisionMade = true
        }
    }
}

struct OnboardingView: View {
    @Environment(\.colorScheme) private var colorScheme

    let scenes: [OnboardingSceneMeta]
    let onFinish: () -> Void

    @State private var selection = 0

    init(
        scenes: [OnboardingSceneMeta] = OnboardingScenes.all,
        onFinish: @escaping () -> Void
    ) {
        self.scenes = scenes
        self.onFinish = onFinish
    }

    var body: some View {
        ZStack {
            backgroundView
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                pageContent
                bottomBar
            }
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .padding(.bottom, 24)
        }
    }

    private var isLastPage: Bool {
        selection == scenes.count - 1
    }

    private var topBar: some View {
        HStack {
            Text("新手引导")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            Spacer()

            Button("跳过") {
                onFinish()
            }
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    private var pageContent: some View {
        TabView(selection: $selection) {
            ForEach(Array(scenes.enumerated()), id: \.element.id) { index, scene in
                VStack(spacing: 28) {
                    Spacer(minLength: 16)

                    OnboardingLottieView(animationName: scene.animationName)
                    .frame(maxWidth: .infinity)
                    .frame(height: 340)

                    VStack(alignment: .leading, spacing: 14) {
                        Text(scene.title)
                            .font(.system(size: 31, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        Text(scene.subtitle)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.primary.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)

                        Text(scene.detail)
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer(minLength: 0)
                }
                .tag(index)
                .padding(.bottom, 16)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    private var bottomBar: some View {
        VStack(spacing: 18) {
            HStack(spacing: 8) {
                ForEach(Array(scenes.indices), id: \.self) { index in
                    Capsule()
                        .fill(index == selection ? Color.primary : Color.primary.opacity(0.16))
                        .frame(width: index == selection ? 28 : 8, height: 8)
                        .animation(.easeInOut(duration: 0.2), value: selection)
                }
            }

            Button {
                if isLastPage {
                    onFinish()
                } else {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        selection += 1
                    }
                }
            } label: {
                Text(isLastPage ? "开始使用" : "下一步")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.accentColor, Color.blue.opacity(0.78)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            Text("\(selection + 1) / \(scenes.count)")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    private var backgroundView: some View {
        ZStack {
            if colorScheme == .dark {
                LinearGradient(
                    colors: [
                        Color(red: 0.06, green: 0.08, blue: 0.12),
                        Color(red: 0.09, green: 0.12, blue: 0.18),
                        Color(red: 0.10, green: 0.08, blue: 0.16)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Circle()
                    .fill(Color.cyan.opacity(0.14))
                    .frame(width: 260, height: 260)
                    .blur(radius: 18)
                    .offset(x: -120, y: -280)

                Circle()
                    .fill(Color.blue.opacity(0.16))
                    .frame(width: 240, height: 240)
                    .blur(radius: 16)
                    .offset(x: 130, y: -180)

                Circle()
                    .fill(Color.indigo.opacity(0.16))
                    .frame(width: 220, height: 220)
                    .blur(radius: 16)
                    .offset(x: 120, y: 320)
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 0.98, green: 0.98, blue: 1.0),
                        Color(red: 0.93, green: 0.97, blue: 1.0),
                        Color(red: 0.97, green: 0.95, blue: 1.0)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Circle()
                    .fill(Color.cyan.opacity(0.16))
                    .frame(width: 260, height: 260)
                    .blur(radius: 12)
                    .offset(x: -120, y: -280)

                Circle()
                    .fill(Color.blue.opacity(0.14))
                    .frame(width: 240, height: 240)
                    .blur(radius: 10)
                    .offset(x: 130, y: -180)

                Circle()
                    .fill(Color.pink.opacity(0.09))
                    .frame(width: 220, height: 220)
                    .blur(radius: 10)
                    .offset(x: 120, y: 320)
            }
        }
    }
}
