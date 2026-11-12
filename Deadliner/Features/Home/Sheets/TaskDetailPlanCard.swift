import SwiftUI

struct TaskDetailPlanCard: View {
  @ObservedObject var viewModel: TaskDetailPlanViewModel
  let onMutation: () -> Void
  let onFocusChange: (Bool) -> Void
  let onRevealComposer: () -> Void
  @EnvironmentObject private var themeStore: ThemeStore
  @State private var showsCompleted = false
  @State private var showsComposer = false
  @State private var draft = ""
  @State private var editingSubtask: InnerTodo?
  @State private var errorText: String?
  @FocusState private var composerFocused: Bool

  private var ordered: [InnerTodo] {
    viewModel.subTasks.sorted {
      if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
      return $0.id < $1.id
    }
  }
  private var completed: [InnerTodo] { ordered.filter(\.isCompleted) }
  private var active: [InnerTodo] { ordered.filter { !$0.isCompleted } }
  private var trimmedDraft: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }

  var body: some View {
    Group {
      VStack(alignment: .leading, spacing: 12) {
        ViewThatFits(in: .horizontal) {
          HStack {
            title
            Spacer()
            summary
          }
          VStack(alignment: .leading, spacing: 6) {
            title
            summary
          }
        }
        ProgressView(
          value: Double(completed.count), total: Double(max(viewModel.subTasks.count, 1))
        )
        .tint(themeStore.accentColor)
        .accessibilityLabel("计划完成进度")
        if viewModel.isLoading && viewModel.subTasks.isEmpty {
          ProgressView("正在加载子任务").frame(maxWidth: .infinity).padding(.vertical, 8)
        } else if viewModel.subTasks.isEmpty {
          Text("还没有子任务，添加一个小目标开始拆解。")
            .font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 8)
        }
        VStack(spacing: 0) {
          ForEach(active) { row($0) }
        }
        if !completed.isEmpty {
          Button {
            withAnimation(.easeInOut(duration: 0.2)) { showsCompleted.toggle() }
          } label: {
            Label(
              "已完成 \(completed.count) 项",
              systemImage: showsCompleted ? "chevron.down" : "chevron.right"
            )
            .font(.subheadline).foregroundStyle(.secondary)
            .frame(minHeight: 44, alignment: .leading)
          }
          .buttonStyle(.plain)
          .accessibilityValue(showsCompleted ? "已展开" : "已折叠")
          .accessibilityIdentifier("detail.plan.completed")
          if showsCompleted {
            VStack(spacing: 0) { ForEach(completed) { row($0) } }
          }
        }
        if showsComposer {
          composer.id("detail.plan.composer")
        } else {
          Button("添加子任务", systemImage: "plus") {
            showsComposer = true
            composerFocused = true
          }
          .font(.subheadline)
          .frame(minHeight: 44)
          .accessibilityIdentifier("detail.plan.add")
        }
        if let errorText {
          Text(errorText).font(.footnote).foregroundStyle(.red)
            .accessibilityIdentifier("detail.plan.error")
        }
      }
      .detailCard()
      .onChange(of: composerFocused) { _, focused in
        onFocusChange(focused)
        if focused {
          onRevealComposer()
        }
      }
      .onChange(of: showsComposer) { _, visible in
        if visible {
          onRevealComposer()
        }
      }
      .task(id: composerFocused) {
        guard composerFocused else { return }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        onRevealComposer()
      }
      .onDisappear { onFocusChange(false) }
      .sheet(item: $editingSubtask) { subtask in
        TaskDetailSubtaskEditor(subtask: subtask, viewModel: viewModel, onMutation: onMutation)
          .presentationDetents([.medium, .large])
          .presentationDragIndicator(.visible)
      }
    }
  }

  private var title: some View { Text("详细计划").font(.headline) }
  private var summary: some View {
    Text("已完成 \(completed.count) / \(viewModel.subTasks.count)")
      .font(.subheadline).foregroundStyle(.secondary)
      .accessibilityIdentifier("detail.plan.summary")
  }

  private func row(_ subtask: InnerTodo) -> some View {
    HStack(spacing: 8) {
      Button {
        mutate { try await viewModel.toggleSubTask(subtask) }
      } label: {
        Image(systemName: subtask.isCompleted ? "checkmark.circle.fill" : "circle")
          .font(.system(size: 22)).foregroundStyle(themeStore.accentColor)
          .frame(width: 44, height: 44)
      }
      .buttonStyle(.plain)
      .accessibilityLabel(
        subtask.isCompleted ? "恢复子任务：\(subtask.content)" : "完成子任务：\(subtask.content)")
      Text(subtask.content)
        .font(.subheadline)
        .foregroundStyle(subtask.isCompleted ? .secondary : .primary)
        .strikethrough(subtask.isCompleted)
        .frame(maxWidth: .infinity, alignment: .leading)
      Button {
        composerFocused = false
        editingSubtask = subtask
      } label: {
        Image(systemName: "ellipsis").frame(width: 44, height: 44)
      }
      .buttonStyle(.plain).foregroundStyle(.secondary)
      .accessibilityLabel("编辑子任务：\(subtask.content)")
    }
    .disabled(viewModel.isMutating)
  }

  private var composer: some View {
    HStack(alignment: .center, spacing: 2) {
      TextField("输入子任务内容", text: $draft, axis: .vertical)
        .font(.subheadline).lineLimit(1...4)
        .padding(12)
        .background(
          Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14)
        )
        .overlay {
          RoundedRectangle(cornerRadius: 14).strokeBorder(themeStore.accentColor, lineWidth: 1)
        }
        .focused($composerFocused)
        .submitLabel(.next)
        .onSubmit(addSubtask)
        .disabled(viewModel.isMutating)
        .accessibilityIdentifier("detail.plan.draft")
      Button("确认添加", systemImage: "checkmark", action: addSubtask)
        .labelStyle(.iconOnly).frame(width: 44, height: 44)
        .disabled(trimmedDraft.isEmpty || viewModel.isMutating)
        .accessibilityIdentifier("detail.plan.save")
      Button("取消添加", systemImage: "xmark") {
        composerFocused = false
        showsComposer = false
        draft = ""
        errorText = nil
      }
      .labelStyle(.iconOnly).foregroundStyle(.secondary)
      .frame(width: 44, height: 44)
      .disabled(viewModel.isMutating)
    }
  }

  private func addSubtask() {
    let content = trimmedDraft
    guard !content.isEmpty, !viewModel.isMutating else { return }
    mutate {
      try await viewModel.addSubTask(content: content)
      draft = ""
      composerFocused = true
    }
  }

  private func mutate(_ operation: @escaping @MainActor () async throws -> Void) {
    guard !viewModel.isMutating else { return }
    errorText = nil
    Task { @MainActor in
      do {
        try await operation()
        onMutation()
      } catch { errorText = "保存失败，内容已保留：\(error.localizedDescription)" }
    }
  }
}

private struct TaskDetailSubtaskEditor: View {
  let subtask: InnerTodo
  @ObservedObject var viewModel: TaskDetailPlanViewModel
  let onMutation: () -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var draft: String
  @State private var errorText: String?
  @State private var saving = false
  @FocusState private var focused: Bool

  init(subtask: InnerTodo, viewModel: TaskDetailPlanViewModel, onMutation: @escaping () -> Void) {
    self.subtask = subtask
    self.viewModel = viewModel
    self.onMutation = onMutation
    _draft = State(initialValue: subtask.content)
  }

  var body: some View {
    NavigationStack {
      Form {
        TextField("子任务内容", text: $draft, axis: .vertical)
          .lineLimit(2...6).focused($focused)
          .accessibilityIdentifier("detail.plan.editDraft")
        if let errorText { Text(errorText).font(.footnote).foregroundStyle(.red) }
        Button("删除子任务", role: .destructive) {
          save { try await viewModel.deleteSubTask(subtask) }
        }
      }
      .disabled(saving)
      .navigationTitle("编辑子任务")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("取消", role: .cancel) { dismiss() }.disabled(saving)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("保存") {
            let content = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            save {
              try await viewModel.updateSubTaskContent(subTaskId: subtask.id, content: content)
            }
          }
          .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || saving)
        }
      }
    }
    .interactiveDismissDisabled(saving)
  }

  private func save(_ operation: @escaping @MainActor () async throws -> Void) {
    guard !saving, !viewModel.isMutating else { return }
    saving = true
    errorText = nil
    Task { @MainActor in
      defer { saving = false }
      do {
        try await operation()
        onMutation()
        dismiss()
      } catch { errorText = error.localizedDescription }
    }
  }
}
