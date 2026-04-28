//
//  TaskDetailSheet.swift
//  Deadliner
//
//  Created by Codex on 2026/4/17.
//

import SwiftUI

struct TaskDetailSheetView: View {
    let item: DDLItem
    let isExpanded: Bool

    @EnvironmentObject private var themeStore: ThemeStore

    @State private var currentItem: DDLItem
    @StateObject private var planViewModel: TaskDetailPlanViewModel

    @State private var editSheetItem: DDLItem? = nil
    @State private var isSavingStar = false
    @State private var errorText: String? = nil

    @State private var animatedProgress: CGFloat = 0
    @State private var progressAnimTask: Task<Void, Never>? = nil
    @State private var isProgressAnimating = false

    @State private var hasLoadedPlan = false
    @State private var showPlanComposer = false
    @State private var draftSubTask = ""
    @State private var editingSubTaskId: String? = nil
    @State private var editingSubTaskDraft = ""
    @State private var editingSubTaskOriginalContent = ""
    @FocusState private var isPlanComposerFocused: Bool
    @FocusState private var isEditingSubTaskFocused: Bool

    init(item: DDLItem, isExpanded: Bool) {
        self.item = item
        self.isExpanded = isExpanded
        _currentItem = State(initialValue: item)
        _planViewModel = StateObject(wrappedValue: TaskDetailPlanViewModel(taskId: item.id))
    }

    private var calculatedProgress: CGFloat {
        guard
            let start = DeadlineDateParser.safeParseOptional(currentItem.startTime),
            let end = DeadlineDateParser.safeParseOptional(currentItem.endTime),
            end > start
        else {
            return currentItem.isCompleted ? 1 : 0
        }
        if currentItem.isCompleted { return 1 }

        let now = Date()
        if now <= start { return 0 }
        if now >= end { return 1 }

        let ratio = now.timeIntervalSince(start) / end.timeIntervalSince(start)
        return CGFloat(min(max(ratio, 0), 1))
    }

    private var clampedProgress: CGFloat {
        min(max(calculatedProgress, 0), 1)
    }

    private var progressPercent: Int {
        Int((animatedProgress * 100).rounded())
    }

    private var percentBlurRadius: CGFloat {
        guard isProgressAnimating else { return 0 }
        let delta = abs(clampedProgress - animatedProgress)
        return delta > 0.001 ? max(0.4, delta * 24) : 0
    }

    private var progressAnimationKey: String {
        "\(currentItem.startTime)|\(currentItem.endTime)|\(String(describing: currentItem.state))|\(currentItem.completeTime)"
    }

    private var noteText: String {
        let trimmed = currentItem.note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "无备注" : currentItem.note
    }

    private var trimmedDraftSubTask: String {
        draftSubTask.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var displayedSubTasks: [InnerTodo] {
        planViewModel.subTasks.sorted { lhs, rhs in
            if lhs.isCompleted != rhs.isCompleted {
                return lhs.isCompleted == false
            }
            if lhs.sortOrder != rhs.sortOrder {
                return lhs.sortOrder < rhs.sortOrder
            }
            return lhs.id < rhs.id
        }
    }

    private var planSummaryText: String {
        let total = planViewModel.subTasks.count
        let completed = planViewModel.subTasks.filter(\.isCompleted).count
        if total == 0 { return "还没有子任务" }
        return "已完成 \(completed) / \(total)"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    progressCard
                    taskMetaCard
                    noteCard
                    planCard
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .overlay(alignment: .bottomTrailing) {
                floatingActionButton
                    .opacity(isExpanded ? 1 : 0)
                    .offset(y: isExpanded ? 0 : 18)
                    .allowsHitTesting(isExpanded)
                    .animation(.smooth(duration: 0.22, extraBounce: 0), value: isExpanded)
            }
            .background(
                Group {
                    if isExpanded {
                        Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
                    } else {
                        Color.clear
                    }
                }
            )
            .animation(.easeInOut(duration: 0.2), value: isExpanded)
            .navigationTitle("任务详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        editSheetItem = currentItem
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await toggleStar() }
                    } label: {
                        Image(systemName: currentItem.isStared ? "star.fill" : "star")
                    }
                    .disabled(isSavingStar)
                }
            }
        }
        .onAppear {
            animateProgressIn()
            loadPlanIfNeeded()
        }
        .onChange(of: progressAnimationKey) { _, _ in
            animateProgressIn()
        }
        .onChange(of: isPlanComposerFocused) { oldValue, newValue in
            if oldValue, !newValue {
                submitSubTask(keepComposerVisible: false)
            }
        }
        .onChange(of: isEditingSubTaskFocused) { oldValue, newValue in
            if oldValue, !newValue {
                commitSubTaskEditIfNeeded()
            }
        }
        .onDisappear {
            progressAnimTask?.cancel()
        }
        .sheet(item: $editSheetItem) { editItem in
            EditTaskSheetView(
                repository: TaskRepository.shared,
                item: editItem,
                onDone: {
                    Task { await reloadItem() }
                }
            )
            .presentationDetents([.large])
        }
        .alert("提示", isPresented: Binding(
            get: { errorText != nil },
            set: { if !$0 { errorText = nil } }
        )) {
            Button("确定", role: .cancel) { errorText = nil }
        } message: {
            Text(errorText ?? "")
        }
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(progressPercent)%")
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .blur(radius: percentBlurRadius)
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.9), value: progressPercent)

            Text(progressSubtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            GradientProgressBar(
                progress: animatedProgress,
                height: 12,
                gradientColors: [themeStore.accentColor.opacity(0.42), themeStore.accentColor]
            )
            .frame(height: 12)
            .animation(.easeInOut(duration: 0.9), value: animatedProgress)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private var taskMetaCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(currentItem.name)
                .font(.title3.weight(.bold))
                .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            HStack(spacing: 10) {
                Label("开始", systemImage: "play.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.subheadline.weight(.semibold))
                Text(formatTime(currentItem.startTime))
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            HStack(spacing: 10) {
                Label("截止", systemImage: "flag.checkered.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.subheadline.weight(.semibold))
                Text(formatTime(currentItem.endTime))
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("任务备注")
                .font(.headline)
            Text(noteText)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private var planCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("详细计划")
                    .font(.headline)
                Spacer()
                Text(planSummaryText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if planViewModel.isLoading && planViewModel.subTasks.isEmpty {
                ProgressView("正在加载子任务")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else if displayedSubTasks.isEmpty {
                Text("点击右下角 + 添加第一条子任务")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 8) {
                    ForEach(displayedSubTasks) { subTask in
                        subTaskRow(subTask)
                    }
                }
            }

            if showPlanComposer {
                planComposerRow
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private func subTaskRow(_ subTask: InnerTodo) -> some View {
        HStack(spacing: 10) {
            Button {
                Task { await toggleSubTask(subTask) }
            } label: {
                Image(systemName: subTask.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(subTask.isCompleted ? themeStore.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(planViewModel.isMutating)

            Group {
                if editingSubTaskId == subTask.id {
                    TextField("", text: $editingSubTaskDraft, axis: .vertical)
                        .font(.subheadline)
                        .lineLimit(1...3)
                        .focused($isEditingSubTaskFocused)
                        .submitLabel(.done)
                        .onSubmit {
                            commitSubTaskEditIfNeeded()
                        }
                        .disabled(planViewModel.isMutating)
                } else {
                    Text(subTask.content)
                        .font(.subheadline)
                        .foregroundStyle(subTask.isCompleted ? .secondary : .primary)
                        .strikethrough(subTask.isCompleted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(role: .destructive) {
                Task { await deleteSubTask(subTask) }
            } label: {
                Image(systemName: "trash")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.plain)
            .disabled(planViewModel.isMutating)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemGroupedBackground))
        )
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.35).onEnded { _ in
                beginSubTaskEdit(subTask)
            }
        )
    }

    private var planComposerRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "circle.dashed")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField("输入子任务内容", text: $draftSubTask, axis: .vertical)
                .font(.subheadline)
                .lineLimit(1...3)
                .focused($isPlanComposerFocused)
                .submitLabel(.done)
                .onSubmit {
                    submitSubTask(keepComposerVisible: true)
                }
                .disabled(planViewModel.isMutating)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemGroupedBackground))
        )
    }

    private var progressSubtitle: String {
        if currentItem.isCompleted { return "任务已完成" }
        if currentItem.state.isAbandonedLike { return "任务已放弃" }
        return "当前任务时间进度"
    }

    private var floatingActionButton: some View {
        Button {
            handlePlanFabTap()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .semibold))
                .frame(width: 42, height: 42)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .tint(themeStore.accentColor)
        .padding(.trailing, 18)
        .padding(.bottom, 18)
        .accessibilityLabel("新增子任务")
    }

    private func animateProgressIn() {
        progressAnimTask?.cancel()
        animatedProgress = 0
        isProgressAnimating = false
        progressAnimTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            if Task.isCancelled { return }
            isProgressAnimating = true
            withAnimation(.easeInOut(duration: 0.9)) {
                animatedProgress = clampedProgress
            }
            try? await Task.sleep(for: .milliseconds(800))
            if Task.isCancelled { return }
            isProgressAnimating = false
        }
    }

    private func handlePlanFabTap() {
        if editingSubTaskId != nil {
            isEditingSubTaskFocused = false
        }
        withAnimation(.smooth(duration: 0.2, extraBounce: 0)) {
            showPlanComposer = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isPlanComposerFocused = true
        }
    }

    private func submitSubTask(keepComposerVisible: Bool) {
        let content = trimmedDraftSubTask
        guard !content.isEmpty else {
            if !keepComposerVisible {
                withAnimation(.smooth(duration: 0.2, extraBounce: 0)) {
                    showPlanComposer = false
                }
            }
            return
        }

        draftSubTask = ""
        Task {
            do {
                try await planViewModel.addSubTask(content: content)
                if keepComposerVisible {
                    isPlanComposerFocused = true
                } else {
                    withAnimation(.smooth(duration: 0.2, extraBounce: 0)) {
                        showPlanComposer = false
                    }
                }
            } catch {
                errorText = "新增子任务失败：\(error.localizedDescription)"
            }
        }
    }

    private func toggleSubTask(_ subTask: InnerTodo) async {
        do {
            try await planViewModel.toggleSubTask(subTask)
        } catch {
            errorText = "更新子任务失败：\(error.localizedDescription)"
        }
    }

    private func deleteSubTask(_ subTask: InnerTodo) async {
        do {
            try await planViewModel.deleteSubTask(subTask)
            if editingSubTaskId == subTask.id {
                clearSubTaskEditState()
            }
        } catch {
            errorText = "删除子任务失败：\(error.localizedDescription)"
        }
    }

    private func beginSubTaskEdit(_ subTask: InnerTodo) {
        guard planViewModel.isMutating == false else { return }

        if showPlanComposer {
            isPlanComposerFocused = false
            withAnimation(.smooth(duration: 0.2, extraBounce: 0)) {
                showPlanComposer = false
            }
        }

        editingSubTaskId = subTask.id
        editingSubTaskDraft = subTask.content
        editingSubTaskOriginalContent = subTask.content

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            isEditingSubTaskFocused = true
        }
    }

    private func commitSubTaskEditIfNeeded() {
        guard let editingId = editingSubTaskId else { return }

        let trimmedDraft = editingSubTaskDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOriginal = editingSubTaskOriginalContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedDraft.isEmpty == false else {
            clearSubTaskEditState()
            return
        }
        guard trimmedDraft != trimmedOriginal else {
            clearSubTaskEditState()
            return
        }

        Task {
            do {
                try await planViewModel.updateSubTaskContent(
                    subTaskId: editingId,
                    content: trimmedDraft
                )
                clearSubTaskEditState()
            } catch {
                errorText = "编辑子任务失败：\(error.localizedDescription)"
            }
        }
    }

    private func clearSubTaskEditState() {
        editingSubTaskId = nil
        editingSubTaskDraft = ""
        editingSubTaskOriginalContent = ""
        isEditingSubTaskFocused = false
    }

    private func loadPlanIfNeeded() {
        guard hasLoadedPlan == false else { return }
        Task {
            do {
                try await planViewModel.load()
                hasLoadedPlan = true
            } catch {
                errorText = "加载子任务失败：\(error.localizedDescription)"
            }
        }
    }

    private func toggleStar() async {
        guard !isSavingStar else { return }
        isSavingStar = true
        let oldItem = currentItem
        currentItem.isStared.toggle()
        do {
            try await TaskRepository.shared.updateDDL(currentItem)
        } catch {
            currentItem = oldItem
            errorText = "星标更新失败：\(error.localizedDescription)"
        }
        isSavingStar = false
    }

    private func reloadItem() async {
        do {
            if let latest = try await TaskRepository.shared.getDDLById(currentItem.id) {
                currentItem = latest
            }
            try await planViewModel.load()
            hasLoadedPlan = true
        } catch {
            errorText = "刷新任务详情失败：\(error.localizedDescription)"
        }
    }

    private func formatTime(_ raw: String) -> String {
        guard let date = DeadlineDateParser.safeParseOptional(raw) else { return raw.isEmpty ? "未设置" : raw }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
