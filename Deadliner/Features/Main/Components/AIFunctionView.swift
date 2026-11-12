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
    let onScrollProgressChange: ((CGFloat) -> Void)?
    @AppStorage("userName") var userName: String = "用户"
    @AppStorage("settings.ai.auto_approve_read_tasks") var autoApproveReadTasks: Bool = false
    @AppStorage("settings.ai.silent_task_add") var silentTaskAdd: Bool = true
    @AppStorage("settings.ai.hide_thinking_process") var hideThinkingProcess: Bool = false
    @Environment(\.colorScheme) var colorScheme
    @StateObject var speechInput = SpeechInputService()

    // 状态控制
    @State var inputText: String = ""
    @State var isParsing = false
    @State var isExpanded = false
    @FocusState var isInputFocused: Bool

    @State var displayItems: [DisplayItem] = []

    @State var errorMessage: String?
    @State var showErrorMessage = false
    
    @State var sessionSummary: String = ""
    @StateObject var memoryBank = MemoryBank.shared
    
    @State var pendingToolRequest: AIToolRequest?
    @State var toolOriginalUserText: String = ""
    @State var lastSubmittedToolName: String?
    @State var submittedToolRequestIDs: Set<String> = []
    @State var pendingMemoryNoticeTask: Task<Void, Never>?
    @State var inputSectionHeight: CGFloat = 92
    @State var readTasksPromptCount: Int = 0
    @State var sessionAutoApproveReadTasks: Bool = false
    @State var pendingReadTasksApprovalRequest: AIToolRequest?
    @State var showReadTasksApprovalDialog: Bool = false

    @State var addedTaskKeys: Set<String> = []      // 用于把卡片变“已添加”
    @State var createdTaskIDsByKey: [String: String] = [:]
    @State var addedHabitKeys: Set<String> = []
    @State var createdHabitDdlIDsByKey: [String: String] = [:]

    @State private var eventSubscriptionID: UUID?
    @State var repoBusy: Bool = false               // 防连点
    
    @State var showMemoryManageSheet: Bool = false
    @State var showFeedbackShareSheet: Bool = false
    @State var feedbackShareItems: [Any] = []
    @State var isPreparingFeedback: Bool = false
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
                                    Text(hideThinkingProcess ? "Lifi AI 正在处理中..." : "Lifi AI 正在思考...")
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
                    .scrollDismissesKeyboard(.interactively)
                    .onScrollGeometryChange(for: CGFloat.self) { geometry in
                        geometry.contentOffset.y
                    } action: { _, newOffsetY in
                        let progress = min(max(newOffsetY / 180.0, 0), 1)
                        onScrollProgressChange?(progress)
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
        .simultaneousGesture(
            TapGesture().onEnded {
                if isInputFocused {
                    isInputFocused = false
                }
            }
        )
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
            "允许读取任务列表？",
            isPresented: $showReadTasksApprovalDialog,
            titleVisibility: .visible
        ) {
            Button("允许一次") {
                guard let req = pendingReadTasksApprovalRequest else { return }
                pendingReadTasksApprovalRequest = nil
                pendingToolRequest = req
                Task { await approveAndRunTool(req) }
            }
            Button("记住本会话") {
                guard let req = pendingReadTasksApprovalRequest else { return }
                sessionAutoApproveReadTasks = true
                pendingReadTasksApprovalRequest = nil
                pendingToolRequest = req
                withAnimation(.spring()) {
                    displayItems.append(DisplayItem(kind: .aiChat("已记住本会话：后续读取任务列表将自动确认。")))
                }
                Task { await approveAndRunTool(req) }
            }
            Button("永久开启") {
                guard let req = pendingReadTasksApprovalRequest else { return }
                autoApproveReadTasks = true
                pendingReadTasksApprovalRequest = nil
                pendingToolRequest = req
                withAnimation(.spring()) {
                    displayItems.append(DisplayItem(kind: .aiChat("已永久开启“自动确认读取任务列表”。")))
                }
                Task { await approveAndRunTool(req) }
            }
            Button("取消", role: .cancel) {
                pendingReadTasksApprovalRequest = nil
            }
        } message: {
            Text("你可以只允许本次，也可以记住本会话，或直接永久开启自动确认。")
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
                try await KMPLifiCoreBridge.shared.initializeIfNeeded()
                guard !Task.isCancelled else { return }
                if let id = eventSubscriptionID { KMPLifiCoreBridge.shared.unsubscribe(id) }
                eventSubscriptionID = KMPLifiCoreBridge.shared.subscribe { event in
                    handleCoreEvent(event)
                }
            } catch {
                errorMessage = "核心初始化失败：\(error.localizedDescription)"
                showErrorMessage = true
            }
        }
        .onDisappear {
            if let id = eventSubscriptionID { KMPLifiCoreBridge.shared.unsubscribe(id) }; eventSubscriptionID = nil
            Task { await speechInput.cancelRecording() }
            onScrollProgressChange?(0)
        }
    }

    init(
        userTier: UserTier,
        bottomAccessoryInset: CGFloat = 0,
        useSheetDetents: Bool = true,
        onScrollProgressChange: ((CGFloat) -> Void)? = nil
    ) {
        self.userTier = userTier
        self.bottomAccessoryInset = bottomAccessoryInset
        self.useSheetDetents = useSheetDetents
        self.onScrollProgressChange = onScrollProgressChange
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
