import SwiftUI

struct TaskDetailSheetView: View {
  let item: DDLItem

  @EnvironmentObject private var themeStore: ThemeStore
  @Environment(\.dismiss) private var dismiss
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @ScaledMetric(relativeTo: .subheadline) private var actionLabelHeight: CGFloat = 24
  @State private var currentItem: DDLItem
  @StateObject private var planViewModel: TaskDetailPlanViewModel
  private let taskStore: any KMPTaskUIStore = PersistenceStores.tasks

  @State private var category: TaskCategory?
  @State private var presentedSheet: DetailSheetDestination?
  @State private var measuredActionHeight: CGFloat = 52
  @State private var pendingConfirmation: DDLStateAction?
  @State private var confirmsDelete = false
  @State private var isMutating = false
  @State private var planHasFocus = false
  @State private var errorText: String?
  @State private var animatedProgress: CGFloat = 0
  @State private var refreshGeneration = 0
  @State private var refreshTask: Task<Void, Never>?

  init(item: DDLItem) {
    self.item = item
    _currentItem = State(initialValue: item)
    _planViewModel = StateObject(wrappedValue: TaskDetailPlanViewModel(taskId: item.id))
  }

  private var busy: Bool { isMutating || planViewModel.isMutating }

  private var progress: CGFloat {
    if currentItem.isCompleted { return 1 }
    guard let start = DeadlineDateParser.safeParseOptional(currentItem.startTime),
      let end = DeadlineDateParser.safeParseOptional(currentItem.endTime), end > start
    else { return 0 }
    return CGFloat(min(max(Date().timeIntervalSince(start) / end.timeIntervalSince(start), 0), 1))
  }

  private var progressKey: String {
    "\(currentItem.startTime)|\(currentItem.endTime)|\(currentItem.state.rawValue)"
  }

  private var primaryAction: DDLStateAction {
    switch currentItem.state {
    case .active, .completed: .markComplete
    case .archived, .abandonedArchived: .unarchive
    case .abandoned: .restoreActive
    }
  }

  private var primaryTitle: String {
    switch currentItem.state {
    case .active: "标记完成"
    case .completed, .abandoned: "恢复任务"
    case .archived, .abandonedArchived: "取消归档"
    }
  }

  private var stateTitle: String {
    switch currentItem.state {
    case .active: "进行中"
    case .completed: "已完成"
    case .archived: "已归档"
    case .abandoned: "已放弃"
    case .abandonedArchived: "放弃后归档"
    }
  }

  var body: some View {
    presentations(
      NavigationStack {
        ScrollViewReader { proxy in
          ScrollView {
            VStack(spacing: 16) {
              progressCard
              metaCard
              noteCard
              TaskDetailPlanCard(
                viewModel: planViewModel,
                onMutation: scheduleRefresh,
                onFocusChange: { planHasFocus = $0 },
                onRevealComposer: {
                  withAnimation { proxy.scrollTo("detail.plan.composer", anchor: .bottom) }
                }
              )
              .id(currentItem.id)
              .disabled(isMutating)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
          }
          .scrollDismissesKeyboard(.interactively)
          .deadlinerScrollEdgeEffect()
          .background(Color(uiColor: .systemGroupedBackground))
          .safeAreaInset(edge: .bottom, spacing: 0) {
            if !planHasFocus { actionBar.padding(.horizontal, 16).padding(.vertical, 10) }
          }
          .navigationTitle("任务详情")
          .navigationBarTitleDisplayMode(.inline)
          .toolbar { navigationButtons }
        }
      }

    )
    .task { await reload() }
    .onReceive(NotificationCenter.default.publisher(for: .persistenceDataChanged)) { notification in
      guard let event = notification.object as? PersistenceChangeEvent,
        !event.resourceKinds.isDisjoint(with: [.task, .taskSubtask, .category])
      else { return }
      scheduleRefresh()
    }
    .onChange(of: progressKey) { _, _ in animateProgress() }
    .onDisappear {
      refreshTask?.cancel()
      refreshGeneration += 1
    }
  }

  @ToolbarContentBuilder
  private var navigationButtons: some ToolbarContent {
    ToolbarItem(placement: .cancellationAction) {
      Button("关闭", systemImage: "xmark") { dismiss() }
        .labelStyle(.iconOnly)
        .accessibilityIdentifier("detail.close")
        .disabled(busy)
    }
    ToolbarItem(placement: .topBarTrailing) {
      Button("星标", systemImage: currentItem.isStared ? "star.fill" : "star") {
        runMutation {
          // Read the latest aggregate so a plan edit is not replaced by a stale snapshot.
          guard var latest = try await taskStore.task(id: currentItem.id) else {
            dismiss()
            return
          }
          latest.isStared.toggle()
          try await taskStore.updateTask(latest)
        }
      }
      .labelStyle(.iconOnly)
      .tint(currentItem.isStared ? .orange : themeStore.accentColor)
      .disabled(busy)
      .accessibilityValue(currentItem.isStared ? "已加星标" : "未加星标")
    }
  }

  private var progressCard: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .firstTextBaseline) {
        Text("\(Int((animatedProgress * 100).rounded()))%")
          .font(.system(size: 38, weight: .bold, design: .rounded))
          .contentTransition(.numericText())
        Spacer()
        Text("时间进度").font(.subheadline).foregroundStyle(.secondary)
      }
      Text(currentItem.isCompleted ? "任务已完成" : currentItem.isAbandoned ? "任务已放弃" : "当前任务时间进度")
        .font(.subheadline).foregroundStyle(.secondary)
      GradientProgressBar(
        progress: animatedProgress, height: 12,
        gradientColors: [themeStore.accentColor.opacity(0.42), themeStore.accentColor]
      )
      .frame(height: 12)
      .accessibilityLabel("任务时间进度")
      .accessibilityValue("\(Int((progress * 100).rounded()))%")
    }
    .detailCard()
  }

  private var metaCard: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .top, spacing: 12) {
        Text(currentItem.name)
          .font(.title3.weight(.bold))
          .frame(maxWidth: .infinity, alignment: .leading)
        Color.clear.frame(width: 24, height: 24)
          .overlay {
            Button("编辑任务", systemImage: "square.and.pencil") { presentedSheet = .edit(currentItem) }
              .labelStyle(.iconOnly)
              .frame(width: 44, height: 44)
              .contentShape(Rectangle())
              .disabled(busy)
              .accessibilityIdentifier("detail.edit")
          }
      }
      Divider()
      timeRow("开始", symbol: "play.circle.fill", value: currentItem.startTime)
      timeRow("截止", symbol: "flag.checkered.circle.fill", value: currentItem.endTime)
      Divider()
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 8) { badges }
        VStack(alignment: .leading, spacing: 8) { badges }
      }
    }
    .detailCard()
  }

  @ViewBuilder
  private var badges: some View {
    DetailBadge(
      title: stateTitle, symbol: nil,
      color: currentItem.isAbandoned
        ? .orange : currentItem.isCompleted ? .green : themeStore.accentColor)
    DetailBadge(
      title: category?.name ?? "未分类",
      symbol: category.map { CategoryPresentationSupport.safeIconKey($0.iconKey) } ?? "tag",
      color: category.map { Color(hex: $0.colorHex) } ?? .secondary)
  }

  private func timeRow(_ title: String, symbol: String, value: String) -> some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 10) {
        Label(title, systemImage: symbol).foregroundStyle(.secondary)
        Spacer(minLength: 8)
        Text(formatTime(value)).multilineTextAlignment(.trailing)
      }
      VStack(alignment: .leading, spacing: 6) {
        Label(title, systemImage: symbol).foregroundStyle(.secondary)
        Text(formatTime(value))
      }
    }
    .font(.subheadline)
  }

  private var noteCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("任务备注").font(.headline)
      Text(
        currentItem.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          ? "无备注" : currentItem.note
      )
      .font(.body).foregroundStyle(.secondary)
      .frame(maxWidth: .infinity, alignment: .leading)
      .textSelection(.enabled)
    }
    .detailCard()
  }

  private var actionBar: some View {
    GlassEffectContainer(spacing: 8) {
      Group {
        if dynamicTypeSize.isAccessibilitySize {
          VStack(spacing: 12) {
            primaryButton
            HStack(spacing: 12) {
              focusButton
              Spacer()
              moreButton
            }
          }
        } else {
          HStack(spacing: 12) {
            primaryButton
            focusButton
            moreButton
          }
        }
      }
    }
    .controlSize(.large)
    .font(.subheadline.weight(.semibold))
    .disabled(busy)
    .accessibilityIdentifier("detail.actions")
  }

  private var primaryButton: some View {
    Group {
      if currentItem.state == .active {
        taskActionButton
          .buttonStyle(.glassProminent)
          .tint(themeStore.accentColor)
      } else {
        taskActionButton
          .foregroundStyle(.primary)
          .buttonStyle(.glass)
          .tint(.primary)
      }
    }
    .buttonBorderShape(.capsule)
    .onGeometryChange(for: CGFloat.self) {
      $0.size.height
    } action: {
      measuredActionHeight = $0
    }
    .accessibilityIdentifier("detail.primary")
  }

  private var taskActionButton: some View {
    Button {
      runMutation {
        currentItem = try await taskStore.performTaskAction(
          id: currentItem.id, action: primaryAction)
      }
    } label: {
      Label(
        primaryTitle,
        systemImage: currentItem.state == .active ? "checkmark.circle" : "arrow.uturn.backward"
      )
      .frame(maxWidth: .infinity)
      .frame(height: actionLabelHeight)
    }
  }

  private var focusButton: some View {
    Button {
      presentedSheet = .focus
    } label: {
      Label("专注", systemImage: "clock")
        .foregroundStyle(.primary)
        .frame(height: actionLabelHeight)
    }
    .buttonStyle(.glass)
    .buttonBorderShape(.capsule)
    .tint(.primary)
    .disabled(!currentItem.state.isActionable)
    .accessibilityIdentifier("detail.focus")
  }

  private var moreButton: some View {
    TaskDetailMoreButton(
      state: currentItem.state,
      hasDeadline: DeadlineDateParser.safeParseOptional(currentItem.endTime) != nil,
      isEnabled: !busy,
      onPostpone: { presentedSheet = .postpone },
      onGiveUp: { pendingConfirmation = .markGiveUp },
      onArchive: {
        runMutation {
          currentItem = try await taskStore.performTaskAction(
            id: currentItem.id, action: .markArchive)
        }
      },
      onCalendar: { presentedSheet = .calendar },
      onDelete: { confirmsDelete = true }
    )
    .frame(width: measuredActionHeight, height: measuredActionHeight)
    .glassEffect(.regular.interactive(), in: .circle)
  }

  private func presentations<Content: View>(_ content: Content) -> some View {
    content
      .sheet(item: $presentedSheet, onDismiss: scheduleRefresh) { destination in
        switch destination {
        case .edit(let editItem):
          EditTaskSheetView(repository: taskStore, item: editItem, onDone: scheduleRefresh)
            .presentationDetents([.large])
        case .focus:
          FocusTimerView(taskUID: currentItem.id, taskTitle: currentItem.name)
            .presentationDetents([.large]).presentationDragIndicator(.visible)
        case .postpone:
          TaskDetailPostponeDialog(item: currentItem) { amount, inHours in
            currentItem = try await taskStore.postponeTask(
              id: currentItem.id, amount: amount, inHours: inHours)
            presentedSheet = nil
            scheduleRefresh()
          }
          .presentationDetents([.height(400), .large])
          .presentationDragIndicator(.visible)
        case .calendar:
          TaskDetailCalendarEditor(item: currentItem)
        }
      }
      .alert(
        "提示", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })
      ) {
        Button("确定", role: .cancel) { errorText = nil }
      } message: {
        Text(errorText ?? "")
      }
      .alert(
        "放弃这项任务？",
        isPresented: Binding(
          get: { pendingConfirmation != nil }, set: { if !$0 { pendingConfirmation = nil } })
      ) {
        Button("取消", role: .cancel) { pendingConfirmation = nil }
        Button("放弃任务", role: .destructive) {
          pendingConfirmation = nil
          runMutation {
            currentItem = try await taskStore.performTaskAction(
              id: currentItem.id, action: .markGiveUp)
          }
        }
      } message: {
        Text("之后可以恢复任务。")
      }
      .alert("删除这项任务？", isPresented: $confirmsDelete) {
        Button("取消", role: .cancel) {}
        Button("删除任务", role: .destructive) {
          runMutation {
            try await taskStore.deleteTask(id: currentItem.id)
            dismiss()
          }
        }
      } message: {
        Text("任务及其详细计划将被删除。")
      }
      .interactiveDismissDisabled(busy)
  }

  private func runMutation(_ operation: @escaping @MainActor () async throws -> Void) {
    guard !busy else { return }
    isMutating = true
    Task { @MainActor in
      defer { isMutating = false }
      do {
        try await operation()
        await reload()
      } catch is CancellationError {
        // Cancelling focus resolution leaves the task unchanged.
      } catch { errorText = error.localizedDescription }
    }
  }

  private func scheduleRefresh() {
    refreshTask?.cancel()
    refreshTask = Task { await reload() }
  }

  private func reload() async {
    refreshGeneration += 1
    let generation = refreshGeneration
    do {
      guard let latest = try await taskStore.task(id: item.id) else {
        if !Task.isCancelled, generation == refreshGeneration { dismiss() }
        return
      }
      let latestCategory: TaskCategory?
      if let uid = latest.categoryUID {
        latestCategory = try await PersistenceStores.categories.category(uid: uid)
      } else {
        latestCategory = nil
      }
      guard !Task.isCancelled, generation == refreshGeneration else { return }
      currentItem = latest
      category = latestCategory
      animateProgress()
      try await planViewModel.load()
    } catch is CancellationError {} catch {
      guard !Task.isCancelled, generation == refreshGeneration else { return }
      errorText = "刷新任务详情失败：\(error.localizedDescription)"
    }
  }

  private func animateProgress() {
    withAnimation(.easeInOut(duration: 0.65)) { animatedProgress = progress }
  }

  private func formatTime(_ raw: String) -> String {
    guard let date = DeadlineDateParser.safeParseOptional(raw) else {
      return raw.isEmpty ? "未设置" : raw
    }
    return date.formatted(date: .abbreviated, time: .shortened)
  }
}

extension View {
  func detailCard() -> some View {
    padding(18)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        Color(uiColor: .secondarySystemGroupedBackground),
        in: RoundedRectangle(cornerRadius: 28, style: .continuous))
  }
}

private struct DetailBadge: View {
  let title: String
  let symbol: String?
  let color: Color

  var body: some View {
    HStack(spacing: 4) {
      if let symbol { Image(systemName: symbol) }
      Text(title)
    }
    .font(.caption.weight(.medium))
    .padding(.horizontal, 10).padding(.vertical, 5)
    .foregroundStyle(color)
    .background(color.opacity(0.12), in: Capsule())
  }
}

/// A single presentation source prevents competing sheet modifiers on the detail host.
private enum DetailSheetDestination: Identifiable {
  case edit(DDLItem)
  case focus
  case postpone
  case calendar

  var id: String {
    switch self {
    case .edit(let item): "edit:" + item.id
    case .focus: "focus"
    case .postpone: "postpone"
    case .calendar: "calendar"
    }
  }
}
