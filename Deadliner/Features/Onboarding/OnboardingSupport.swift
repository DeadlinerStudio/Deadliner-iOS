//
//  OnboardingSupport.swift
//  Deadliner
//
//  Created by Codex on 2026/4/27.
//

import SwiftUI
import UIKit
import Lottie

struct OnboardingSceneMeta: Identifiable, Hashable, Codable {
    let id: String
    let fileName: String
    let title: String
    let subtitle: String
    let detail: String

    var animationName: String {
        (fileName as NSString).deletingPathExtension
    }
}

enum OnboardingStorageKey {
    static let hasSeen = "onboarding.has_seen"
    static let showOnNextLaunch = "onboarding.show_on_next_launch"
}

enum OnboardingScenes {
    static let all: [OnboardingSceneMeta] = load()

    private static func load() -> [OnboardingSceneMeta] {
        guard let url = Bundle.main.url(forResource: "onboarding-scenes", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let scenes = try? JSONDecoder().decode([OnboardingSceneMeta].self, from: data),
              !scenes.isEmpty else {
            return fallback
        }

        return scenes
    }

    private static let fallback: [OnboardingSceneMeta] = [
        .init(
            id: "guide_scene_1",
            fileName: "Scene-1.json",
            title: "滑动任务，快捷处理",
            subtitle: "在任务卡片上左右滑动，就能快速完成常用操作。",
            detail: "像完成、归档这类高频动作，不必点进详情页，在列表里就能顺手处理。"
        ),
        .init(
            id: "guide_scene_2",
            fileName: "Scene-2.json",
            title: "点一下 Lifi AI，唤起智能体",
            subtitle: "遇到临时想法、碎片信息或模糊需求，都可以先交给它整理。",
            detail: "Lifi AI 能帮你提炼任务意图、补齐结构，再决定是否加入清单。"
        ),
        .init(
            id: "guide_scene_4",
            fileName: "Scene-4.json",
            title: "长按任务，进入多选",
            subtitle: "想批量完成、归档或删除时，长按任意任务即可开始选择。",
            detail: "连续处理一组任务会更高效，适合做每日清单收尾或集中整理。"
        ),
        .init(
            id: "guide_scene_5",
            fileName: "Scene-5-iOS.json",
            title: "轻点任务，查看详情与子任务",
            subtitle: "短按任务可以进入详情页，继续补充信息或拆分子任务。",
            detail: "当一件事需要更多上下文时，详情页就是你继续展开和整理的地方。"
        ),
        .init(
            id: "guide_scene_6",
            fileName: "Scene-6-iOS.json",
            title: "点击 Tab 顶部按钮，快速导航",
            subtitle: "每个 Tab 上方的按钮都可以带你进入对应功能入口。",
            detail: "把常用入口放在手边，切页之外也能更快抵达你要用的能力。"
        )
    ]
}

#if canImport(Lottie)

struct OnboardingLottieView: UIViewRepresentable {
    let animationName: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let containerView = UIView()
        containerView.backgroundColor = .clear

        let animationView = context.coordinator.animationView
        animationView.translatesAutoresizingMaskIntoConstraints = false
        animationView.backgroundBehavior = .pauseAndRestore
        animationView.contentMode = .scaleAspectFit
        animationView.loopMode = .loop

        containerView.addSubview(animationView)

        NSLayoutConstraint.activate([
            animationView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            animationView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            animationView.topAnchor.constraint(equalTo: containerView.topAnchor),
            animationView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        applyAnimationIfNeeded(to: animationView, coordinator: context.coordinator)
        return containerView
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        applyAnimationIfNeeded(to: context.coordinator.animationView, coordinator: context.coordinator)
    }

    private func applyAnimationIfNeeded(to animationView: LottieAnimationView, coordinator: Coordinator) {
        guard coordinator.currentAnimationName != animationName else {
            if !animationView.isAnimationPlaying {
                animationView.play()
            }
            return
        }

        coordinator.currentAnimationName = animationName
        animationView.animation = LottieAnimation.named(animationName, bundle: .main)
        animationView.play()
    }

    final class Coordinator {
        let animationView = LottieAnimationView()
        var currentAnimationName: String?
    }
}

#else

struct OnboardingLottieView: View {
    let animationName: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 54, weight: .regular))
                .foregroundStyle(.blue.opacity(0.8))
            Text(animationName)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            Text("添加 Lottie Swift Package 后会显示动画")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#endif
