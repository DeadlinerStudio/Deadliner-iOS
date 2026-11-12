import SwiftUI

// MARK: - UI 渲染组件
extension AIFunctionView {
    var messageBubbleRadius: CGFloat { 28 }
    var proposalCardRadius: CGFloat { 28 }
    var proposalCardBaseFill: Color {
        colorScheme == .dark
            ? Color(uiColor: .secondarySystemBackground)
            : Color(uiColor: .systemBackground)
    }
    var proposalCardStroke: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.06)
    }

    @ViewBuilder
    func renderItem(_ item: DisplayItem) -> some View {
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

    func userBubble(text: String) -> some View {
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

    func chatBubble(text: String) -> some View {
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

    func thinkingBubble(text: String) -> some View {
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

    func memoryCapturedBubble(content: String) -> some View {
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

    func proposalCard(task: AITask) -> some View {
        let taskKey = makeTaskKey(task)
        let hasAdded = addedTaskKeys.contains(taskKey)

        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("任务")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.secondary)
                Text(task.name).font(.headline.weight(.semibold))
                Text("截止：\((task.dueTime?.isEmpty == false) ? task.dueTime! : "未指定")")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if let note = task.note, !note.isEmpty {
                    Text("备注：\(note)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Button(action: {
                if hasAdded {
                    Task { await undoTaskFromProposal(task) }
                } else {
                    Task { await createTaskFromProposal(task) }
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: hasAdded ? "arrow.uturn.backward.circle" : "plus.circle")
                    Text(hasAdded ? "撤回" : "添加")
                }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(hasAdded ? Color.orange.opacity(0.15) : Color.blue.opacity(0.15))
                .foregroundColor(hasAdded ? .orange : .blue)
                .clipShape(Capsule())
            }
            .disabled(repoBusy)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: proposalCardRadius, style: .continuous)
                .fill(proposalCardBaseFill)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: proposalCardRadius, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: proposalCardRadius, style: .continuous)
                .stroke(proposalCardStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: proposalCardRadius, style: .continuous))
    }

    func habitCard(habit: AIHabit) -> some View {
        let habitKey = makeHabitKey(habit)
        let hasAdded = addedHabitKeys.contains(habitKey)

        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("习惯")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.secondary)
                Text(habit.name).font(.headline.weight(.semibold))
                Text("\(habit.period) / \(habit.timesPerPeriod) 次")
                    .font(.caption)
                    .foregroundColor(.secondary)
                let target = habit.goalType.uppercased() == "TOTAL" ? " · 总目标\(habit.totalTarget ?? 0)" : ""
                Text("目标：\(habit.goalType)\(target)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 8)
            Button(action: {
                if hasAdded {
                    Task { await undoHabitFromProposal(habit) }
                } else {
                    Task { await createHabitFromProposal(habit) }
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: hasAdded ? "arrow.uturn.backward.circle" : "plus.circle")
                    Text(hasAdded ? "撤回" : "添加")
                }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(hasAdded ? Color.orange.opacity(0.15) : Color.purple.opacity(0.15))
                .foregroundColor(hasAdded ? .orange : .purple)
                .clipShape(Capsule())
            }
            .disabled(repoBusy)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: proposalCardRadius, style: .continuous)
                .fill(proposalCardBaseFill)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: proposalCardRadius, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: proposalCardRadius, style: .continuous)
                .stroke(proposalCardStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: proposalCardRadius, style: .continuous))
    }

    func toolRequestCard(_ req: AIToolRequest) -> some View {
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
                    Task {
                        await KMPLifiCoreBridge.shared.submitToolResult(id: req.id, tool: req.tool, resultJson: "{\"denied\":true}")
                    }
                } label: {
                    Text("拒绝")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)

                Button {
                    let normalized = ToolCallExecutor.shared.normalizeToolName(req.tool)
                    if normalized == "read_tasks" && !autoApproveReadTasks && !sessionAutoApproveReadTasks {
                        pendingReadTasksApprovalRequest = req
                        showReadTasksApprovalDialog = true
                    } else {
                        pendingToolRequest = req
                        Task { await approveAndRunTool(req) }
                    }
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
        .background(
            RoundedRectangle(cornerRadius: proposalCardRadius, style: .continuous)
                .fill(proposalCardBaseFill)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: proposalCardRadius, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: proposalCardRadius, style: .continuous)
                .stroke(proposalCardStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: proposalCardRadius, style: .continuous))
    }

    func toolResultBubble(_ res: AIToolResult) -> some View {
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

    var inputSection: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                TextField("和 Deadliner 聊聊你接下来想做什么", text: $inputText, axis: .vertical)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1...6)
                    .focused($isInputFocused)
                    .submitLabel(.send)
                    .onSubmit {
                        Task { await runSmartAgent() }
                    }

                HStack(spacing: 10) {
                    Spacer(minLength: 0)

                    if isInputFocused {
                        Button {
                            isInputFocused = false
                        } label: {
                            Image(systemName: "keyboard.chevron.compact.down")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 36, height: 36)
                                .background(Color.secondary.opacity(0.12), in: Circle())
                        }
                        .accessibilityLabel("收起键盘")
                    }

                    voicePlaceholderButton

                    Button(action: {
                        if isParsing || pendingToolRequest != nil {
                            Task { await stopActiveLifiRun() }
                        } else {
                            Task { await runSmartAgent() }
                        }
                    }) {
                        Image(systemName: isParsing || pendingToolRequest != nil ? "stop.fill" : "arrow.up")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(sendButtonForeground)
                        .frame(width: 44, height: 44)
                        .background(sendButtonBackground, in: Circle())
                }
                .disabled((!isParsing && pendingToolRequest == nil && inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) || speechInput.isBusy)
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
        .floatingComposerGlass()
        .padding(.horizontal, FloatingComposerStyle.horizontalInset)
        .padding(.top, FloatingComposerStyle.topInset)
        .padding(.bottom, FloatingComposerStyle.bottomInset)
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

    var conversationFeedbackBar: some View {
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

    var memoryHintView: some View {
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

    var initialGuideView: some View {
        ViewThatFits(in: .vertical) {
            initialGuideViewRegular
            initialGuideViewCompact
        }
    }

    var initialGuideViewRegular: some View {
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

    var initialGuideViewCompact: some View {
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
    func applyQuickPrompt(_ text: String) {
        // 保持 medium：不要强制 isExpanded=true
        inputText = text
    }

    func quickChip(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
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

    func quickRow(_ title: String, _ subtitle: String, icon: String, action: @escaping () -> Void) -> some View {
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

    var voicePlaceholderButton: some View {
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

    var inputCardStroke: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08)
    }

    var sendButtonBackground: Color {
        colorScheme == .dark ? .white : Color(hex: "#111111")
    }

    var sendButtonForeground: Color {
        colorScheme == .dark ? Color(hex: "#111111") : .white
    }

    var speechStatusText: String? {
        if speechInput.isRecording {
            return speechInput.helperText ?? "正在听写..."
        }

        return speechInput.lastErrorMessage
    }

}
