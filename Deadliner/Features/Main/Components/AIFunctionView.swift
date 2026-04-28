//
//  AIFunctionView.swift
//  Deadliner
//
//  Created by Aritx 音唯 on 2026/2/22.
//

import SwiftUI

struct AIFunctionView: View {
    let userTier: UserTier
    let useSheetDetents: Bool
    @AppStorage("userName") private var userName: String = "用户"
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var speechInput = SpeechInputService()

    // 状态控制
    @State private var inputText: String = ""
    @State private var isParsing = false
    @State private var isExpanded = false

    @State private var displayItems: [DisplayItem] = []

    @State private var errorMessage: String?
    @State private var showErrorMessage = false
    
    @State private var sessionSummary: String = ""
    @StateObject private var memoryBank = MemoryBank.shared
    
    @State private var pendingTaskToCreate: AITask?
    @State private var showCreateTaskDialog: Bool = false

    @State private var pendingHabitToCreate: AIHabit?
    @State private var showCreateHabitDialog: Bool = false
    
    @State private var pendingToolRequest: AIToolRequest?
    @State private var toolOriginalUserText: String = ""
    @State private var lastSubmittedToolName: String?
    @State private var submittedToolRequestIDs: Set<String> = []
    @State private var pendingMemoryNoticeTask: Task<Void, Never>?
    @State private var inputSectionHeight: CGFloat = 92

    @State private var addedTaskKeys: Set<String> = []      // 用于把卡片变“已添加”
    @State private var addedHabitKeys: Set<String> = []

    @State private var repoBusy: Bool = false               // 防连点
    
    @State private var showMemoryManageSheet: Bool = false
    @State private var showFeedbackShareSheet: Bool = false
    @State private var feedbackShareItems: [Any] = []
    @State private var isPreparingFeedback: Bool = false
    let bottomAccessoryInset: CGFloat

    var body: some View {
        Group {
            if isExpanded || !displayItems.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            memoryHintView

                            ForEach(displayItems) { item in
                                renderItem(item)
                                    .id(item.id)
                                    .transition(.asymmetric(
                                        insertion: .move(edge: .bottom).combined(with: .opacity),
                                        removal: .opacity
                                    ))
                            }

                            if isParsing {
                                HStack(spacing: 12) {
                                    ProgressView().tint(.purple)
                                    Text("Lifi AI 正在思考...")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                }
                                .padding(.leading)
                                .id("loading_indicator")
                            }

                            if !displayItems.isEmpty {
                                conversationFeedbackBar
                                    .id("conversation_feedback")
                            }

                            Color.clear
                                .frame(height: inputSectionHeight + bottomAccessoryInset + 24)
                                .id("bottom_spacing")
                        }
                        .padding()
                    }
                    .onChange(of: displayItems.count) { _ in
                        guard let lastId = displayItems.last?.id else { return }
                        withAnimation { proxy.scrollTo(lastId, anchor: .bottom) }
                    }
                    .onChange(of: isParsing) { parsing in
                        if parsing {
                            withAnimation { proxy.scrollTo("loading_indicator", anchor: .bottom) }
                        }
                    }
                }
            } else {
                initialGuideView
            }
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: (isExpanded || !displayItems.isEmpty) ? .top : .center
        )
        .safeAreaInset(edge: .bottom, spacing: 0) {
            inputSection
                .padding(.bottom, bottomAccessoryInset)
        }
        .navigationTitle(isExpanded ? "Lifi AI" : "")
        .navigationBarTitleDisplayMode(.inline)
        // 根据是否展开自动调整 Sheet 高度
        .modifier(AIFunctionDetentsModifier(
            useSheetDetents: useSheetDetents,
            isExpanded: isExpanded
        ))
        .alert("出错了", isPresented: $showErrorMessage) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "未知错误")
        }
        .confirmationDialog(
            "确认创建任务？",
            isPresented: $showCreateTaskDialog,
            titleVisibility: .visible
        ) {
            Button("创建任务", role: .none) {
                guard let t = pendingTaskToCreate else { return }
                Task { await createTaskFromProposal(t) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            if let t = pendingTaskToCreate {
                Text(makeTaskConfirmMessage(t))
            }
        }
        .confirmationDialog(
            "确认开启习惯？",
            isPresented: $showCreateHabitDialog,
            titleVisibility: .visible
        ) {
            Button("开启习惯", role: .none) {
                guard let h = pendingHabitToCreate else { return }
                Task { await createHabitFromProposal(h) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            if let h = pendingHabitToCreate {
                Text("习惯：\(h.name)\n频率：\(h.period) / \(h.timesPerPeriod) 次")
            }
        }
        .sheet(isPresented: $showMemoryManageSheet) {
            MemoryManageSheet()
        }
        .sheet(isPresented: $showFeedbackShareSheet) {
            ActivityView(activityItems: feedbackShareItems)
        }
        .onChange(of: speechInput.composedText) { _, newValue in
            inputText = newValue
        }
        .onChange(of: speechInput.lastErrorMessage) { _, newValue in
            guard let newValue, !newValue.isEmpty else { return }
            errorMessage = newValue
            showErrorMessage = true
        }
        .task {
            do {
                try await DeadlinerCoreBridge.shared.initializeIfNeeded()
                DeadlinerCoreBridge.shared.setEventHandler { event in
                    handleCoreEvent(event)
                }
            } catch {
                errorMessage = "核心初始化失败：\(error.localizedDescription)"
                showErrorMessage = true
            }
        }
        .onDisappear {
            DeadlinerCoreBridge.shared.clearEventHandler()
            Task { await speechInput.cancelRecording() }
        }
    }

    init(
        userTier: UserTier,
        bottomAccessoryInset: CGFloat = 0,
        useSheetDetents: Bool = true
    ) {
        self.userTier = userTier
        self.bottomAccessoryInset = bottomAccessoryInset
        self.useSheetDetents = useSheetDetents
    }
}

private struct AIFunctionDetentsModifier: ViewModifier {
    let useSheetDetents: Bool
    let isExpanded: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if useSheetDetents {
            content.presentationDetents(isExpanded ? [.large] : [.medium, .large])
        } else {
            content
        }
    }
}

// MARK: - UI 渲染组件
extension AIFunctionView {
    private var messageBubbleRadius: CGFloat { 28 }
    private var proposalCardRadius: CGFloat { 28 }
    private var proposalCardFill: Color {
        colorScheme == .dark ? Color(hex: "#111111").opacity(0.8) : Color.white.opacity(0.8)
    }
    private var proposalCardStroke: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)
    }

    @ViewBuilder
    private func renderItem(_ item: DisplayItem) -> some View {
        switch item.kind {
        case .userQuery(let text):
            userBubble(text: text)
        case .aiChat(let text):
            chatBubble(text: text)
        case .aiThinking(let text):
            thinkingBubble(text: text)
        case .aiTask(let task):
            proposalCard(task: task)
        case .aiHabit(let habit):
            habitCard(habit: habit)
        case .aiMemory(let content):
            memoryCapturedBubble(content: content)
        case .aiToolRequest(let req):
            toolRequestCard(req)
        case .aiToolResult(let res):
            toolResultBubble(res)
        }
    }

    private func userBubble(text: String) -> some View {
        HStack {
            Spacer()
            Text(text)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color.blue)
                .foregroundColor(.white)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: messageBubbleRadius,
                        bottomLeadingRadius: messageBubbleRadius,
                        bottomTrailingRadius: 10,
                        topTrailingRadius: messageBubbleRadius,
                        style: .continuous
                    )
                )
                .frame(maxWidth: UIScreen.main.bounds.width * 0.78, alignment: .trailing)
        }
    }

    private func chatBubble(text: String) -> some View {
        HStack {
            Text(text)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color(uiColor: .secondarySystemFill))
                .foregroundColor(.primary)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: messageBubbleRadius,
                        bottomLeadingRadius: 10,
                        bottomTrailingRadius: messageBubbleRadius,
                        topTrailingRadius: messageBubbleRadius,
                        style: .continuous
                    )
                )
                .frame(maxWidth: UIScreen.main.bounds.width * 0.82, alignment: .leading)
            Spacer()
        }
    }

    private func thinkingBubble(text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .foregroundColor(.blue)
                .font(.caption)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.blue.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func memoryCapturedBubble(content: String) -> some View {
        HStack {
            Image(systemName: "brain.head.profile.fill")
                .foregroundColor(.purple)
                .font(.caption)
            Text("记住了：\(content)")
                .font(.caption)
                .italic()
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.purple.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func proposalCard(task: AITask) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "doc.text.fill").foregroundColor(.blue)
                Text("识别到任务").font(.caption.bold()).foregroundColor(.secondary)
            }
            Text(task.name).font(.headline)
            if let due = task.dueTime, !due.isEmpty {
                Text(due).font(.subheadline).foregroundColor(.blue)
            }
            
            let taskKey = makeTaskKey(task)

            Button(action: {
                pendingTaskToCreate = task
                showCreateTaskDialog = true
            }) {
                Text(addedTaskKeys.contains(taskKey) ? "已添加" : "确认添加")
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(addedTaskKeys.contains(taskKey) ? Color.gray.opacity(0.4) : Color.blue)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
            }
            .disabled(addedTaskKeys.contains(taskKey) || repoBusy)
        }
        .padding()
        .background(proposalCardFill)
        .overlay(
            RoundedRectangle(cornerRadius: proposalCardRadius, style: .continuous)
                .stroke(proposalCardStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: proposalCardRadius, style: .continuous))
    }

    private func habitCard(habit: AIHabit) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath").foregroundColor(.purple)
                Text("识别到习惯").font(.caption.bold()).foregroundColor(.secondary)
            }
            Text(habit.name).font(.headline)
            Text("\(habit.period) / \(habit.timesPerPeriod)次")
                .font(.subheadline)
                .foregroundColor(.purple)

            let habitKey = makeHabitKey(habit)

            Button(action: {
                pendingHabitToCreate = habit
                showCreateHabitDialog = true
            }) {
                Text(addedHabitKeys.contains(habitKey) ? "已开启" : "开启习惯")
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(addedHabitKeys.contains(habitKey) ? Color.gray.opacity(0.4) : Color.purple)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
            }
            .disabled(addedHabitKeys.contains(habitKey) || repoBusy)
        }
        .padding()
        .background(proposalCardFill)
        .overlay(
            RoundedRectangle(cornerRadius: proposalCardRadius, style: .continuous)
                .stroke(proposalCardStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: proposalCardRadius, style: .continuous))
    }
    
    private func toolRequestCard(_ req: AIToolRequest) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "tray.full.fill").foregroundColor(.orange)
                Text(AIToolPresentation.toolRequestTitle(for: req.tool)).font(.caption.bold()).foregroundColor(.secondary)
                Spacer()
            }

            if let r = req.reason, !r.isEmpty {
                Text(r)
                    .font(.callout)
                    .foregroundColor(.primary)
            } else {
                Text(AIToolPresentation.toolRequestDefaultReason(for: req.tool))
                    .font(.callout)
                    .foregroundColor(.primary)
            }

            if let scope = AIToolPresentation.toolRequestScopeSummary(req) {
                Text(scope)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 10) {
                Button(role: .cancel) {
                    withAnimation(.spring()) {
                        displayItems.append(DisplayItem(kind: .aiChat("好的，我不读取任务列表。你可以告诉我更具体的任务信息，我也能继续帮你。")))
                    }
                } label: {
                    Text("拒绝")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)

                Button {
                    pendingToolRequest = req
                    Task { await approveAndRunTool(req) }
                } label: {
                    Text("允许一次")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .disabled(repoBusy || submittedToolRequestIDs.contains(req.id))
            }
        }
        .padding()
        .background(proposalCardFill)
        .overlay(
            RoundedRectangle(cornerRadius: proposalCardRadius, style: .continuous)
                .stroke(proposalCardStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: proposalCardRadius, style: .continuous))
    }

    private func toolResultBubble(_ res: AIToolResult) -> some View {
        return HStack {
            Image(systemName: "checklist")
                .foregroundColor(.orange)
                .font(.caption)

            Text(AIToolPresentation.toolResultDisplayText(res))
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var inputSection: some View {
        GlassEffectContainer(spacing: 12) {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 18) {
                    TextField("和 Deadliner 聊聊你接下来想做什么", text: $inputText, axis: .vertical)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1...6)
                        .submitLabel(.send)
                        .onSubmit {
                            Task { await runSmartAgent() }
                        }

                    HStack(spacing: 10) {
                        Spacer(minLength: 0)

                        voicePlaceholderButton

                        Button(action: {
                            print("[AIFunctionView] Send tapped. input=\(inputText)")
                            Task { await runSmartAgent() }
                        }) {
                            Image(systemName: isParsing ? "ellipsis" : "arrow.up")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(sendButtonForeground)
                            .frame(width: 44, height: 44)
                            .background(sendButtonBackground, in: Circle())
                    }
                    .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isParsing || speechInput.isBusy)
                    .opacity(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isParsing || speechInput.isBusy ? 0.6 : 1)
                    }

                    if let speechStatusText = speechStatusText {
                        Text(speechStatusText)
                            .font(.caption)
                            .foregroundColor(speechInput.isRecording ? .secondary : .red.opacity(0.9))
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.18), value: speechInput.isRecording)
                .animation(.easeInOut(duration: 0.18), value: speechInput.helperText)
                .animation(.easeInOut(duration: 0.18), value: speechInput.lastErrorMessage)
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 16)
            }
            .glassEffect(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(inputCardStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.26 : 0.08), radius: 18, x: 0, y: 8)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        inputSectionHeight = proxy.size.height
                    }
                    .onChange(of: proxy.size.height) { newHeight in
                        inputSectionHeight = newHeight
                    }
            }
        )
    }

    private var conversationFeedbackBar: some View {
        HStack {
            Button {
                Task { await prepareFeedbackAndShare() }
            } label: {
                HStack(spacing: 6) {
                    if isPreparingFeedback {
                        ProgressView()
                            .tint(.secondary)
                    } else {
                        Image(systemName: "ladybug")
                            .font(.caption)
                    }
                    Text(isPreparingFeedback ? "正在打包反馈..." : "反馈")
                        .font(.caption)
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.1), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isPreparingFeedback)
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private var memoryHintView: some View {
        Button {
            showMemoryManageSheet = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "brain.head.profile")
                Text("画像: \(memoryBank.userProfile.isEmpty ? "未建立" : "已建立") · 记忆 \(memoryBank.fragments.count) 条")
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .font(.caption2)
            .foregroundColor(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    private var initialGuideView: some View {
        ViewThatFits(in: .vertical) {
            initialGuideViewRegular
            initialGuideViewCompact
        }
    }
    
    private var initialGuideViewRegular: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 24)

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.white.opacity(0.15), Color.white.opacity(0.02), .clear],
                            center: .center,
                            startRadius: 4,
                            endRadius: 44
                        )
                    )
                    .frame(width: 88, height: 88)

                Image("lifi.logo.v1")
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(colors: [Color.purple, Color.indigo], startPoint: .top, endPoint: .bottom)
                    )
            }

            VStack(spacing: 8) {
                Text("你好，\(userName)")
                    .font(.system(size: 34, weight: .bold))

                Text("我是 Lifi，你可以这样问我")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 12) {
                quickRow("安排一个任务", "明天下午 3 点和产品开评审会", icon: "calendar.badge.clock") {
                    applyQuickPrompt("明天下午 3 点和产品开评审会")
                }
                quickRow("建立一个习惯", "每周 3 次力量训练，每次 40 分钟", icon: "figure.run") {
                    applyQuickPrompt("每周 3 次力量训练，每次 40 分钟")
                }
                quickRow("帮我整理计划", "把这周要交付的 Deadliner 功能排一下优先级", icon: "square.stack.3d.up") {
                    applyQuickPrompt("把这周要交付的 Deadliner 功能排一下优先级")
                }
            }
            .padding(.top, 6)

            Spacer(minLength: 12)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 32)
    }
    
    private var initialGuideViewCompact: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.secondary.opacity(0.12))
                    .frame(width: 72, height: 72)

                Image("lifi.logo.v1")
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(colors: [Color.purple, Color.indigo], startPoint: .top, endPoint: .bottom)
                    )
            }

            VStack(spacing: 4) {
                Text("你好，\(userName)")
                    .font(.title3.weight(.bold))
                Text("我是 Lifi，你可以这样问我")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            HStack(spacing: 10) {
                quickChip("安排任务", icon: "calendar.badge.clock") {
                    applyQuickPrompt("明天下午 3 点和产品开评审会")
                }
                quickChip("建立习惯", icon: "figure.run") {
                    applyQuickPrompt("每周 3 次力量训练，每次 40 分钟")
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 24)
    }
    
    @MainActor
    private func applyQuickPrompt(_ text: String) {
        // 保持 medium：不要强制 isExpanded=true
        inputText = text
    }

    private func quickChip(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func quickRow(_ title: String, _ subtitle: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.9), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(colorScheme == .dark ? 0.04 : 0.88))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.45), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var voicePlaceholderButton: some View {
        Button {
            Task { await handleVoiceTap() }
        } label: {
            Group {
                if speechInput.state == .preparing || speechInput.state == .installingAssets {
                    ProgressView()
                        .tint(.secondary)
                } else {
                    Image(systemName: speechInput.isRecording ? "stop.fill" : "waveform")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(speechInput.isRecording ? .red : .secondary)
                }
            }
            .frame(width: 34, height: 34)
            .background(Color.white.opacity(colorScheme == .dark ? 0.04 : 0.65), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(isParsing)
    }

    private var inputCardStroke: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08)
    }

    private var sendButtonBackground: Color {
        colorScheme == .dark ? .white : Color(hex: "#111111")
    }

    private var sendButtonForeground: Color {
        colorScheme == .dark ? Color(hex: "#111111") : .white
    }

    private var speechStatusText: String? {
        if speechInput.isRecording {
            return speechInput.helperText ?? "正在听写..."
        }

        return speechInput.lastErrorMessage
    }

    @MainActor
    private func handleVoiceTap() async {
        do {
            if speechInput.isRecording {
                try await speechInput.stopRecording()
            } else {
                try await speechInput.startRecording(initialText: inputText)
            }
        } catch {
            errorMessage = error.localizedDescription
            showErrorMessage = true
        }
    }
}

// MARK: - 业务逻辑
extension AIFunctionView {

    @MainActor
    private func runSmartAgent() async {
        let query = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        AILog.log("[Input] \(query)")

        withAnimation(.spring()) {
            isExpanded = true
            isParsing = true
            displayItems.append(DisplayItem(kind: .userQuery(query)))
            inputText = ""
        }

        toolOriginalUserText = query
        await DeadlinerCoreBridge.shared.processInput(query)
    }
    
    @MainActor
    private func createTaskFromProposal(_ task: AITask) async {
        if repoBusy { return }
        repoBusy = true
        defer { repoBusy = false }

        do {
            let params = try makeDDLInsertParams(from: task)

            _ = try await TaskRepository.shared.insertDDL(params)

            let key = makeTaskKey(task)
            addedTaskKeys.insert(key)

            withAnimation(.spring()) {
                displayItems.append(DisplayItem(kind: .aiChat("已添加任务：\(task.name)")))
            }
        } catch {
            errorMessage = error.localizedDescription
            showErrorMessage = true
        }
    }

    @MainActor
    private func createHabitFromProposal(_ habit: AIHabit) async {
        if repoBusy { return }
        repoBusy = true
        defer { repoBusy = false }

        do {
            // 1. 先创建一个 DDLItem 作为载体 (类型为 .habit)
            let ddlParams = DDLInsertParams(
                name: habit.name,
                startTime: Date().toLocalISOString(),
                endTime: "", // 习惯通常没有明确截止时间
                state: .active,
                completeTime: "",
                note: "",
                isStared: false,
                subTasks: [],
                type: .habit,
                calendarEventId: nil
            )
            
            let ddlId = try await TaskRepository.shared.insertDDL(ddlParams)
            
            // 2. 解析周期与目标类型
            let periodEnum = HabitPeriod(rawValue: habit.period.uppercased()) ?? .daily
            let goalTypeEnum = HabitGoalType(rawValue: habit.goalType.uppercased()) ?? .perPeriod
            
            // 3. 创建 Habit 本体
            _ = try await HabitRepository.shared.createHabitForDdl(
                ddlId: ddlId,
                name: habit.name,
                period: periodEnum,
                timesPerPeriod: habit.timesPerPeriod,
                goalType: goalTypeEnum,
                totalTarget: habit.totalTarget,
                description: ""
            )

            let key = makeHabitKey(habit)
            addedHabitKeys.insert(key)

            withAnimation(.spring()) {
                displayItems.append(DisplayItem(kind: .aiChat("已开启习惯：\(habit.name)")))
            }
        } catch {
            errorMessage = error.localizedDescription
            showErrorMessage = true
        }
    }
    
    private func makeTaskKey(_ task: AITask) -> String {
        // 你也可以换成 task.id（如果 AITask 有）
        let due = (task.dueTime?.isEmpty == false) ? task.dueTime! : "none"
        return "\(task.name)#\(due)"
    }

    private func makeHabitKey(_ habit: AIHabit) -> String {
        return "\(habit.name)#\(habit.period)#\(habit.timesPerPeriod)"
    }

    private func makeTaskConfirmMessage(_ task: AITask) -> String {
        let due = (task.dueTime?.isEmpty == false) ? task.dueTime! : "无"
        return "任务：\(task.name)\n截止：\(due)"
    }
    
    @MainActor
    private func approveAndRunTool(_ req: AIToolRequest) async {
        if repoBusy { return }
        if submittedToolRequestIDs.contains(req.id) { return }

        submittedToolRequestIDs.insert(req.id)
        repoBusy = true
        isParsing = true
        defer {
            repoBusy = false
        }

        guard ToolCallExecutor.shared.supports(req.tool) else {
            displayItems.append(DisplayItem(kind: .aiChat("暂不支持的工具：\(req.tool)")))
            isParsing = false
            return
        }

        // 1) 本地执行 ToolCallAdapter
        let execution = await ToolCallExecutor.shared.execute(toolName: req.tool, argsJson: req.argsJson)
        AILog.log("[ToolResult] id=\(req.id) tool=\(execution.normalizedToolName) result=\(execution.resultJson)")
        lastSubmittedToolName = execution.normalizedToolName

        let toolResult = AIToolResult(
            id: req.id,
            tool: execution.normalizedToolName,
            requestArgsJson: req.argsJson,
            resultJson: execution.resultJson,
            displayMessage: execution.displayMessage
        )

        withAnimation(.spring()) {
            displayItems.append(DisplayItem(kind: .aiToolResult(toolResult)))
            if execution.normalizedToolName == "create_task", let args = req.createTaskArgs {
                let proposal = AITask(name: args.name, dueTime: args.dueTime, note: args.note)
                displayItems.append(DisplayItem(kind: .aiTask(proposal)))
            }
            if execution.normalizedToolName == "create_habit", let args = req.createHabitArgs {
                let proposal = AIHabit(
                    name: args.name,
                    period: args.period.uppercased(),
                    timesPerPeriod: max(1, args.timesPerPeriod),
                    goalType: args.goalType.uppercased(),
                    totalTarget: args.totalTarget
                )
                displayItems.append(DisplayItem(kind: .aiHabit(proposal)))
            }
        }

        // 2) 回灌给 Rust Core，让其继续下一阶段
        print("[AIFunctionView] submitToolResult id=\(req.id) tool=\(execution.normalizedToolName) payloadJson=\(execution.resultJson)")
        await DeadlinerCoreBridge.shared.submitToolResult(id: req.id, resultJson: execution.resultJson)
    }

    @MainActor
    private func handleCoreEvent(_ event: DeadlinerCoreBridgeEvent) {
        switch event {
        case .thinking(let agentName, let phase, let message):
            if let message, !message.isEmpty {
                AILog.log("[Thinking] agent=\(agentName) phase=\(phase) message=\(message)")
            } else {
                AILog.log("[Thinking] agent=\(agentName) phase=\(phase)")
            }
            if phase != "memory" {
                isParsing = true
            }
            let thinkingText = AIToolPresentation.collaborationMessage(for: agentName, phase: phase, fallbackMessage: message)
            if shouldAppendThinkingMessage(thinkingText) {
                withAnimation(.spring()) {
                    displayItems.append(DisplayItem(kind: .aiThinking(thinkingText)))
                }
            }
        case .textStream:
            break
        case .toolRequest(let req):
            AILog.log("[ToolRequest] id=\(req.id) tool=\(req.tool) mode=\(req.executionMode ?? "N/A") args=\(req.argsJson)")
            isParsing = false
            let normalizedTool = ToolCallExecutor.shared.normalizeToolName(req.tool)
            let sanitizedReq: AIToolRequest
            if normalizedTool == "read_tasks", let readArgs = req.readTasksArgs {
                let sanitized = sanitizeReadTasksArgs(readArgs, userQuery: toolOriginalUserText)
                sanitizedReq = AIToolRequest(
                    id: req.id,
                    tool: normalizedTool,
                    argsJson: encodeReadTasksArgsJson(sanitized),
                    reason: req.reason,
                    executionMode: req.executionMode
                )
            } else {
                sanitizedReq = AIToolRequest(
                    id: req.id,
                    tool: normalizedTool,
                    argsJson: req.argsJson,
                    reason: req.reason,
                    executionMode: req.executionMode
                )
            }

            if AIToolPresentation.shouldAutoApproveToolRequest(sanitizedReq) {
                withAnimation(.spring()) {
                    displayItems.append(DisplayItem(kind: .aiThinking(AIToolPresentation.toolCollaborationMessage(for: sanitizedReq.tool))))
                }
                pendingToolRequest = sanitizedReq
                Task { await approveAndRunTool(sanitizedReq) }
                return
            }

            withAnimation(.spring()) {
                displayItems.append(DisplayItem(kind: .aiThinking(AIToolPresentation.toolCollaborationMessage(for: sanitizedReq.tool))))
                displayItems.append(DisplayItem(kind: .aiToolRequest(sanitizedReq)))
            }
        case .finish(let payload):
            AILog.log("[Finish] intent=\(payload.primaryIntent) tasks=\(payload.tasks.count) habits=\(payload.habits.count) chat=\((payload.chatResponse ?? "").prefix(120))")
            isParsing = false
            pendingMemoryNoticeTask?.cancel()
            pendingMemoryNoticeTask = nil

            if let s = payload.sessionSummary, !s.isEmpty {
                sessionSummary = String(s.prefix(600))
            }

            let suppressProposalCardsForReadOnlyTool = {
                guard let tool = lastSubmittedToolName else { return false }
                let normalized = ToolCallExecutor.shared.normalizeToolName(tool)
                return normalized == "read_tasks"
                    || normalized == "read_habits"
                    || normalized == "create_task"
                    || normalized == "create_habit"
            }()
            lastSubmittedToolName = nil

            withAnimation(.spring()) {
                if !suppressProposalCardsForReadOnlyTool {
                    for task in payload.tasks {
                        displayItems.append(DisplayItem(kind: .aiTask(task)))
                    }
                    for habit in payload.habits {
                        displayItems.append(DisplayItem(kind: .aiHabit(habit)))
                    }
                }
                if let chat = payload.chatResponse, !chat.isEmpty {
                    displayItems.append(DisplayItem(kind: .aiChat(chat)))
                }
            }
        case .memoryCommitted(let payload):
            AILog.log("[MemoryCommitted] added=\(payload.addedMemories.count) profileUpdated=\(payload.profileUpdated) revision=\(payload.newRevision)")
            isParsing = false
            pendingMemoryNoticeTask?.cancel()
            pendingMemoryNoticeTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 700_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.spring()) {
                    for notice in payload.notices {
                        displayItems.append(DisplayItem(kind: .aiMemory(notice)))
                    }
                }
            }
        case .error(let message):
            AILog.log("[Error] \(message)")
            isParsing = false
            pendingMemoryNoticeTask?.cancel()
            pendingMemoryNoticeTask = nil
            lastSubmittedToolName = nil
            errorMessage = message
            showErrorMessage = true
        }
    }
    
    private func sanitizeReadTasksArgs(_ args: ReadTasksArgs, userQuery: String) -> ReadTasksArgs {
        let days = max(1, min(args.timeRangeDays ?? 7, 30))
        let limit = max(1, min(args.limit ?? 20, 50))

        let status = (args.status ?? "OPEN").uppercased()
        let sort = (args.sort ?? "DUE_ASC").uppercased()

        // 1) 先把 AI 的 keywords 清洗
        var kws = (args.keywords ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if kws.count > 3 { kws = Array(kws.prefix(3)) }
        kws = kws.map { String($0.prefix(12)) }

        let q = userQuery.lowercased()
        kws = kws.filter { k in
            let kk = k.lowercased()
            // 简单包含判断足够用（后续你要更强可以做分词）
            return q.contains(kk)
        }

        if isGenericTaskListQuery(userQuery) && !userExplicitlyProvidedTopic(userQuery) {
            kws = []
        }

        return ReadTasksArgs(
            timeRangeDays: days,
            status: status,
            keywords: kws,
            limit: limit,
            sort: sort
        )
    }

    private func shouldAppendThinkingMessage(_ message: String) -> Bool {
        guard let last = displayItems.last?.kind else { return true }
        switch last {
        case .aiThinking(let previous):
            return previous != message
        default:
            return true
        }
    }
    
    private func isGenericTaskListQuery(_ q: String) -> Bool {
        let s = q.lowercased()
        // 典型泛查询词
        let patterns = ["这周", "本周", "最近", "有哪些任务", "有什么任务", "任务列表", "to do", "todo", "待办", "待办事项", "deadline", "ddl"]
        return patterns.contains { s.contains($0.lowercased()) }
    }

    /// 用户是否显式给了主题：例如“系统论的任务”“关于 BOE 的任务”“BOE 相关任务”
    /// 这里先做最小启发式：包含“关于/相关/的任务/的ddl/的待办/项目”等信号
    private func userExplicitlyProvidedTopic(_ q: String) -> Bool {
        let s = q.lowercased()
        let signals = ["关于", "相关", "的任务", "的ddl", "的待办", "项目", "course", "project"]
        return signals.contains { s.contains($0.lowercased()) }
    }

    private func encodeReadTasksArgsJson(_ args: ReadTasksArgs) -> String {
        guard let data = try? JSONEncoder().encode(args),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    @MainActor
    private func prepareFeedbackAndShare() async {
        if isPreparingFeedback { return }
        isPreparingFeedback = true
        defer { isPreparingFeedback = false }

        let info = Bundle.main.infoDictionary
        let version = (info?["CFBundleShortVersionString"] as? String) ?? "unknown"
        let build = (info?["CFBundleVersion"] as? String) ?? "unknown"

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let context = AIFeedbackService.Context(
            appVersion: version,
            buildNumber: build,
            timestamp: iso.string(from: Date()),
            timezone: TimeZone.current.identifier,
            locale: Locale.current.identifier,
            lastCoreEventSummary: DeadlinerCoreBridge.shared.lastEventSummary ?? "(none)",
            sessionSummary: sessionSummary.isEmpty ? "(empty)" : sessionSummary,
            memoryFragmentsCount: memoryBank.fragments.count,
            memoryProfile: memoryBank.userProfile,
            transcriptLines: makeFeedbackTranscriptLines(maxItems: 120),
            coreLastFinishJson: DeadlinerCoreBridge.shared.getLastFinishJson(),
            coreLastMemorySyncJson: DeadlinerCoreBridge.shared.getLastMemorySyncJson()
        )

        let items = await AIFeedbackService.makeShareItems(context: context)
        feedbackShareItems = items
        showFeedbackShareSheet = true
    }

    private func makeFeedbackTranscriptLines(maxItems: Int) -> [String] {
        let recent = Array(displayItems.suffix(maxItems))
        return recent.map { item in
            switch item.kind {
            case .userQuery(let text):
                return "[User] \(text)"
            case .aiChat(let text):
                return "[AI] \(text)"
            case .aiThinking(let text):
                return "[Thinking] \(text)"
            case .aiTask(let task):
                let due = (task.dueTime?.isEmpty == false) ? task.dueTime! : "N/A"
                return "[TaskCard] name=\(task.name) due=\(due)"
            case .aiHabit(let habit):
                return "[HabitCard] name=\(habit.name) period=\(habit.period) times=\(habit.timesPerPeriod)"
            case .aiMemory(let text):
                return "[Memory] \(text)"
            case .aiToolRequest(let req):
                return "[ToolRequest] tool=\(req.tool) mode=\(req.executionMode ?? "N/A") args=\(req.argsJson)"
            case .aiToolResult(let result):
                return "[ToolResult] tool=\(result.tool) result=\(result.resultJson)"
            }
        }
    }

}
