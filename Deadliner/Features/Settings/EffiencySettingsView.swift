//
//  EfficiencySettingsView.swift
//  Deadliner
//
//  Created by Aritx 音唯 on 2026/2/21.
//

import SwiftUI

struct EfficiencySettingsView: View {
    @EnvironmentObject private var themeStore: ThemeStore

    @AppStorage("userTier") private var userTier: UserTier = .free
    
    @State private var enableEbbinghaus = false
    @State private var defaultReviewCount = 4
    
    @State private var showPaywall = false

    var body: some View {
        Form {
            // 免费用户看得到推销横幅
            if userTier == .free {
                PlusUpsellSection(showPaywall: $showPaywall)
            }
            
            Section {
                Toggle("启用艾宾浩斯复习引擎", isOn: $enableEbbinghaus)
                    .disabled(userTier == .free)
                
                if enableEbbinghaus && userTier != .free {
                    Stepper(value: $defaultReviewCount, in: 1...8) {
                        HStack {
                            Text("默认复习节点数")
                            Spacer()
                            Text("\(defaultReviewCount) 次")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } footer: {
                if userTier == .free {
                    Text("根据人类遗忘曲线规律，自动为任务生成 12h, 1天, 2天, 4天, 7天... 的动态复习日程。特别适合考研、考公与语言学习。解锁 Deadliner+ 后可用。")
                        .font(.footnote)
                        .foregroundColor(.orange)
                        .padding(.top, 4)
                }
            }
        }
        .navigationTitle("科学记忆")
        .navigationBarTitleDisplayMode(.inline)
        .optionalTint(themeStore.switchTint)
        .sheet(isPresented: $showPaywall) {
            ProPaywallView().presentationDetents([.large])
        }
    }
}
