//
//  CaptureView.swift
//  Deadliner
//
//  Created by Codex on 2026/4/5.
//

import SwiftUI

struct CaptureInboxView: View {
    var query: Binding<String>? = nil
    var onScrollProgressChange: ((CGFloat) -> Void)? = nil

    @EnvironmentObject private var themeStore: ThemeStore

    @StateObject private var store = CaptureStore()
    @StateObject private var speechInput = SpeechInputService()

    @State private var draftText = ""
    @State private var selectedItem: CaptureInboxItem?
    @State private var conversionRequest: CaptureConversionRequest?
    @State private var pendingDeleteItems: [CaptureInboxItem] = []
    @State private var showDeleteAlert = false
    @State private var selectionMode = false
    @State private var selectedIDs = Set<UUID>()

    private var visibleItems: [CaptureInboxItem] {
        let rawQuery = query?.wrappedValue ?? ""
        let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return store.items }

        return store.items.filter {
            $0.text.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        List {
            composerSection

            if visibleItems.isEmpty {
                emptyRow
            } else {
                Section {
                    ForEach(visibleItems) { item in
                        noteRow(item)
                    }
                } header: {
                    CaptureSectionHeader(
                        title: "最近灵感",
                        subtitle: selectionMode
                            ? "选中多条后可以批量删除，或合并整理成一个任务 / 习惯。"
                            : "先保留它的原始样子，之后再决定要不要变成任务或习惯。"
                    )
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(.clear)
        .toolbar {
            captureToolbar
        }
        .animation(.smooth(duration: 0.26, extraBounce: 0), value: selectionMode)
        .animation(.smooth(duration: 0.22, extraBounce: 0), value: selectedIDs.count)
        .onScrollGeometryChange(for: CGFloat.self) { geo in
            max(0, geo.contentOffset.y + geo.contentInsets.top)
        } action: { _, newValue in
            let progress = min(max(newValue / 120, 0), 1)
            onScrollProgressChange?(progress)
        }
        .sheet(item: $selectedItem) { item in
            CaptureItemDetailSheet(
                item: item,
                onSave: { updatedText in
                    store.updateItem(id: item.id, text: updatedText)
                },
                onConvertToTask: {
                    selectedItem = nil
                    conversionRequest = singleConversionRequest(kind: .task, item: item)
                },
                onConvertToHabit: {
                    selectedItem = nil
                    conversionRequest = singleConversionRequest(kind: .habit, item: item)
                },
                onAIConvertToTask: {
                    selectedItem = nil
                    conversionRequest = singleConversionRequest(kind: .aiTask, item: item)
                },
                onAIConvertToHabit: {
                    selectedItem = nil
                    conversionRequest = singleConversionRequest(kind: .aiHabit, item: item)
                },
                onDelete: {
                    selectedItem = nil
                    requestDelete(items: [item])
                }
            )
        }
        .sheet(item: $conversionRequest) { request in
            conversionDestination(for: request)
        }
        .alert(deleteAlertTitle, isPresented: $showDeleteAlert) {
            Button("取消", role: .cancel) {
                pendingDeleteItems = []
            }
            Button("删除", role: .destructive) {
                store.deleteItems(ids: Set(pendingDeleteItems.map(\.id)))
                pendingDeleteItems = []
                clearSelection()
            }
        } message: {
            Text(deleteAlertMessage)
        }
        .onChange(of: speechInput.composedText) { _, newValue in
            guard speechInput.isRecording || speechInput.isBusy else { return }
            draftText = newValue
        }
    }

    private var composerSection: some View {
        CaptureComposerCard(
            draftText: $draftText,
            speechIsRecording: speechInput.isRecording,
            speechIsPreparing: speechInput.state == .preparing,
            speechIsBusy: speechInput.isBusy,
            helperText: speechInput.helperText,
            errorText: speechInput.lastErrorMessage,
            onToggleRecording: {
                Task { await toggleRecording() }
            },
            onCommit: commitDraft
        )
        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 8, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private var emptyRow: some View {
        VStack(spacing: 14) {
            Image(systemName: "note.text")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)

            Text("还没有新的灵感")
                .font(.headline)

            Text("想到什么就先记下来。等它成熟一点，再决定要不要整理成任务或习惯。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    @ToolbarContentBuilder
    private var captureToolbar: some ToolbarContent {
        if selectionMode {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    clearSelection()
                } label: {
                    Image(systemName: "xmark")
                }
                .contentTransition(.symbolEffect(.replace))
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    requestDelete(items: selectedItems)
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(selectedIDs.isEmpty)
            }
            
            ToolbarSpacer(placement: .topBarTrailing)
            
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("AI 合并成任务") {
                        if let request = mergedConversionRequest(kind: .aiTask) {
                            conversionRequest = request
                        }
                    }

                    Button("AI 合并成习惯") {
                        if let request = mergedConversionRequest(kind: .aiHabit) {
                            conversionRequest = request
                        }
                    }

                    Divider()

                    Button("直接整理成任务") {
                        if let request = mergedConversionRequest(kind: .task) {
                            conversionRequest = request
                        }
                    }

                    Button("直接整理成习惯") {
                        if let request = mergedConversionRequest(kind: .habit) {
                            conversionRequest = request
                        }
                    }
                } label: {
                    Text("合并\(selectedIDs.count)项")
                }
                .disabled(selectedIDs.isEmpty)
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                Button("多选") {
                    withAnimation(.smooth(duration: 0.26, extraBounce: 0)) {
                        selectionMode = true
                    }
                }
                .disabled(visibleItems.isEmpty)
            }
        }
    }

    private func noteRow(_ item: CaptureInboxItem) -> some View {
        CaptureNoteCard(
            item: item,
            relativeTimeText: relativeTimeText(for: item.updatedAt),
            selectionMode: selectionMode,
            isSelected: selectedIDs.contains(item.id),
            onTap: {
                if selectionMode {
                    toggleSelection(for: item.id)
                } else {
                    selectedItem = item
                }
            }
        )
        .swipeActions(edge: .trailing, allowsFullSwipe: !selectionMode) {
            if !selectionMode {
                Button(role: .destructive) {
                    requestDelete(items: [item])
                } label: {
                    Label("删除", systemImage: "trash")
                }
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if !selectionMode {
                Button {
                    conversionRequest = singleConversionRequest(kind: .aiHabit, item: item)
                } label: {
                    Label("AI 习惯", systemImage: "leaf")
                }
                .tint(.green)

                Button {
                    conversionRequest = singleConversionRequest(kind: .aiTask, item: item)
                } label: {
                    Label("AI 任务", image: "lifi.logo.v1")
                }
                .tint(.blue)
            }
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private func conversionDestination(for request: CaptureConversionRequest) -> some View {
        switch request.kind {
        case .task:
            NavigationStack {
                TaskEditorSheetView(
                    repository: TaskRepository.shared,
                    mode: .add,
                    initialDraft: TaskDraft(
                        name: request.item.text,
                        note: "",
                        startTime: Date(),
                        endTime: Date().addingTimeInterval(3600),
                        isStarred: false
                    ),
                    onSaved: {
                        store.consumeItems(ids: Set(request.consumedIDs))
                        conversionRequest = nil
                        clearSelection()
                    }
                )
            }
        case .habit:
            NavigationStack {
                HabitEditorSheetView(
                    mode: .add,
                    initialDraft: HabitDraft(
                        name: request.item.text,
                        description: "",
                        period: .daily,
                        goalType: .perPeriod,
                        timesPerPeriod: "1",
                        totalTarget: "100"
                    ),
                    onSaved: {
                        store.consumeItems(ids: Set(request.consumedIDs))
                        conversionRequest = nil
                        clearSelection()
                    }
                )
            }
        case .aiTask:
            NavigationStack {
                TaskEditorSheetView(
                    repository: TaskRepository.shared,
                    mode: .add,
                    initialDraft: .empty(),
                    onSaved: {
                        store.consumeItems(ids: Set(request.consumedIDs))
                        conversionRequest = nil
                        clearSelection()
                    },
                    initialAIInput: request.item.text,
                    autoRunAIOnAppear: true
                )
            }
        case .aiHabit:
            NavigationStack {
                HabitEditorSheetView(
                    mode: .add,
                    initialDraft: .empty(),
                    onSaved: {
                        store.consumeItems(ids: Set(request.consumedIDs))
                        conversionRequest = nil
                        clearSelection()
                    },
                    initialAIInput: request.item.text,
                    autoRunAIOnAppear: true
                )
            }
        }
    }

    private var selectedItems: [CaptureInboxItem] {
        visibleItems.filter { selectedIDs.contains($0.id) }
    }

    private var deleteAlertTitle: String {
        pendingDeleteItems.count > 1 ? "确认删除这些灵感？" : "确认删除这条灵感？"
    }

    private var deleteAlertMessage: String {
        guard !pendingDeleteItems.isEmpty else { return "此操作不可撤销。" }
        if pendingDeleteItems.count == 1, let item = pendingDeleteItems.first {
            return "将删除「\(item.text)」。此操作不可撤销。"
        }
        return "将删除选中的 \(pendingDeleteItems.count) 条灵感。此操作不可撤销。"
    }

    private func requestDelete(items: [CaptureInboxItem]) {
        pendingDeleteItems = items
        showDeleteAlert = !items.isEmpty
    }

    private func toggleSelection(for id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    private func clearSelection() {
        withAnimation(.smooth(duration: 0.26, extraBounce: 0)) {
            selectionMode = false
            selectedIDs.removeAll()
        }
    }

    private func singleConversionRequest(kind: CaptureConversionKind, item: CaptureInboxItem) -> CaptureConversionRequest {
        CaptureConversionRequest(kind: kind, item: item, consumedIDs: [item.id])
    }

    private func mergedConversionRequest(kind: CaptureConversionKind) -> CaptureConversionRequest? {
        let items = selectedItems
        guard !items.isEmpty else { return nil }

        if items.count == 1, let item = items.first {
            return singleConversionRequest(kind: kind, item: item)
        }

        let mergedText = items
            .map(\.text)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        guard !mergedText.isEmpty else { return nil }

        let syntheticItem = CaptureInboxItem(
            text: mergedText,
            createdAt: items.map(\.createdAt).min() ?? Date(),
            updatedAt: Date()
        )

        return CaptureConversionRequest(
            kind: kind,
            item: syntheticItem,
            consumedIDs: items.map(\.id)
        )
    }

    private func commitDraft() {
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.addItem(text: trimmed)
        draftText = ""
        Task {
            await speechInput.cancelRecording()
        }
    }

    private func toggleRecording() async {
        if speechInput.isBusy {
            try? await speechInput.stopRecording()
            draftText = speechInput.composedText
            return
        }

        do {
            try await speechInput.startRecording(initialText: draftText)
        } catch {
            print("CaptureInboxView startRecording failed: \(error)")
        }
    }

    private func relativeTimeText(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
