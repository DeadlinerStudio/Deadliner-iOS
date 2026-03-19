//
//  MemoryManageSheet.swift
//  Deadliner
//
//  Created by Aritx 音唯 on 2026/2/24.
//

import SwiftUI

struct MemoryManageSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var memoryBank = MemoryBank.shared

    // Profile editor
    @State private var isEditingProfile = false
    @State private var draftProfile = ""

    // Fragment editor
    @State private var editingOriginalFragment: MemoryFragment?
    @State private var fragDraftContent: String = ""
    @State private var fragDraftCategory: String = ""
    @State private var fragDraftImportance: Int = 3
    @State private var showFragEditor = false
    @State private var didSaveFragmentEditor = false

    @State private var showClearAllConfirm = false

    @MainActor
    private func syncMemoryBankToCore() {
        let snapshotJson = memoryBank.exportSnapshotJson()
        Task {
            await DeadlinerCoreBridge.shared.replaceMemorySnapshot(snapshotJson)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                profileSection
                fragmentsSection
                actionsSection
            }
            .navigationTitle("记忆管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button() { dismiss() } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
            .onAppear {
                draftProfile = memoryBank.userProfile
            }
            .sheet(isPresented: $showFragEditor, onDismiss: handleFragmentEditorDismiss) {
                fragmentEditSheet
            }
            .confirmationDialog(
                "确认清空所有记忆？",
                isPresented: $showClearAllConfirm,
                titleVisibility: .visible
            ) {
                Button("清空全部", role: .destructive) {
                    memoryBank.clearAllMemories()
                    syncMemoryBankToCore()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("这会清空用户画像和所有碎片记忆，且不可恢复。")
            }
        }
    }
}

// MARK: - Sections
extension MemoryManageSheet {
    private var displayedFragments: [MemoryFragment] {
        var fragments = memoryBank.fragments

        if showFragEditor, let original = editingOriginalFragment,
           !fragments.contains(where: { $0.id == original.id }) {
            fragments.append(original)
        }

        return fragments.sorted { lhs, rhs in
            if lhs.timestamp != rhs.timestamp {
                return lhs.timestamp > rhs.timestamp
            }
            return lhs.id.uuidString > rhs.id.uuidString
        }
    }

    private var profileSection: some View {
        Section {
            if isEditingProfile {
                TextEditor(text: $draftProfile)
                    .frame(minHeight: 120)

                HStack {
                    Button() {
                        draftProfile = memoryBank.userProfile
                        isEditingProfile = false
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .foregroundColor(.secondary)

                    Spacer()

                    Button("保存") {
                        // 允许清空
                        memoryBank.setUserProfileAllowEmpty(draftProfile)
                        isEditingProfile = false
                        syncMemoryBankToCore()
                    }
                    .fontWeight(.semibold)
                    .buttonStyle(.glassProminent)
                }
            } else {
                if memoryBank.userProfile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("未建立")
                        .foregroundColor(.secondary)
                } else {
                    Text(memoryBank.userProfile)
                        .textSelection(.enabled)
                }

                HStack {
                    Spacer()
                    Button("编辑画像") {
                        draftProfile = memoryBank.userProfile
                        withAnimation(.spring()) { isEditingProfile = true }
                    }
                    .font(.footnote.weight(.semibold))
                }
            }
        } header: {
            Text("用户画像")
        } footer: {
            Text("画像用于给 Agent 提供稳定偏好与背景。建议控制在几百字以内。")
        }
    }

    private var fragmentsSection: some View {
        Section {
            if displayedFragments.isEmpty {
                Text("暂无碎片记忆")
                    .foregroundColor(.secondary)
            } else {
                ForEach(displayedFragments) { frag in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(frag.content)
                            .lineLimit(3)
                            .textSelection(.enabled)

                        HStack(spacing: 10) {
                            Text(frag.category)
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Text(formatDate(frag.timestamp))
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Spacer()

                            Text("★\(frag.importance)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        HStack(spacing: 12) {
                            Button("编辑") {
                                startEditFragment(frag)
                            }
                            .font(.footnote.weight(.semibold))

                            Button("删除") {
                                memoryBank.deleteFragment(id: frag.id)
                                syncMemoryBankToCore()
                            }
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(.red)

                            Spacer()
                        }
                        .padding(.top, 4)
                    }
                    .padding(.vertical, 6)
                }
                .onDelete { indexSet in
                    // batch delete
                    let ids = indexSet.map { displayedFragments[$0].id }
                    for id in ids {
                        memoryBank.deleteFragment(id: id)
                    }
                    syncMemoryBankToCore()
                }
            }
        } header: {
            Text("碎片记忆（\(displayedFragments.count)）")
        } footer: {
            Text("建议把碎片记忆写成可复用的事实/偏好/约束，避免情绪化长文本。")
        }
    }

    private var actionsSection: some View {
        Section {
            Button(role: .destructive) {
                showClearAllConfirm = true
            } label: {
                Text("清空所有记忆")
            }
        }
    }
}

// MARK: - Fragment Edit Sheet
extension MemoryManageSheet {

    private var fragmentEditSheet: some View {
        NavigationStack {
            Form {
                Section("内容") {
                    TextEditor(text: $fragDraftContent)
                        .frame(minHeight: 140)
                }

                Section("类别") {
                    TextField("category", text: $fragDraftCategory)
                        .textInputAutocapitalization(.never)
                }

                Section("重要性") {
                    Stepper(value: $fragDraftImportance, in: 1...5) {
                        Text("★\(fragDraftImportance)")
                    }
                }
            }
            .navigationTitle("编辑碎片记忆")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { showFragEditor = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        didSaveFragmentEditor = true
                        saveFragmentEdit()
                        showFragEditor = false
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func startEditFragment(_ frag: MemoryFragment) {
        editingOriginalFragment = frag
        fragDraftContent = frag.content
        fragDraftCategory = frag.category
        fragDraftImportance = frag.importance
        didSaveFragmentEditor = false
        showFragEditor = true
    }

    private func saveFragmentEdit() {
        guard let original = editingOriginalFragment else { return }

        let content = fragDraftContent.trimmingCharacters(in: .whitespacesAndNewlines)
        if content.isEmpty {
            // 空内容视为删除
            memoryBank.deleteFragment(id: original.id)
            syncMemoryBankToCore()
            return
        }

        let trimmedCategory = fragDraftCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        let updated = MemoryFragment(
            id: original.id,
            content: content,
            category: trimmedCategory.isEmpty ? original.category : trimmedCategory,
            timestamp: original.timestamp,
            importance: fragDraftImportance
        )
        memoryBank.upsertFragment(updated)
        syncMemoryBankToCore()
    }

    private func handleFragmentEditorDismiss() {
        defer {
            editingOriginalFragment = nil
            didSaveFragmentEditor = false
        }

        guard !didSaveFragmentEditor, let original = editingOriginalFragment else { return }
        let stillExists = memoryBank.fragments.contains(where: { $0.id == original.id })
        guard !stillExists else { return }

        memoryBank.upsertFragment(original)
        syncMemoryBankToCore()
    }

    private func formatDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: d)
    }
}
