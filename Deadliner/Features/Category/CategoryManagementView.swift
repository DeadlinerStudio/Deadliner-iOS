//
//  CategoryManagementView.swift
//  Deadliner
//
//  Created by Codex on 2026/7/17.
//

import SwiftUI

struct CategoryManagementView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var categories: [TaskCategory] = []
    @State private var editingCategory: TaskCategory?
    @State private var showCreateSheet = false
    @State private var pendingDelete: TaskCategory?
    @State private var showDeleteAlert = false
    @State private var isLoading = true

    private let repository: any CategoryPersistenceStore = PersistenceStores.categories

    var body: some View {
        NavigationStack {
            List {
                Section("分类") {
                    ForEach(categories) { category in
                        Button {
                            editingCategory = category
                        } label: {
                            CategoryRowLabel(category: category)
                        }
                        .foregroundStyle(.primary)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                pendingDelete = category
                                showDeleteAlert = true
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .navigationTitle("分类")
            .navigationBarTitleDisplayMode(.inline)
            .overlay {
                if isLoading {
                    ProgressView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .accessibilityLabel("完成")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCreateSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("添加分类")
                }
            }
            .task {
                await reload()
            }
            .sheet(isPresented: $showCreateSheet) {
                CategoryEditSheet { category in
                    mergeSavedCategory(category)
                }
            }
            .sheet(item: $editingCategory) { category in
                CategoryEditSheet(category: category) { saved in
                    mergeSavedCategory(saved)
                }
            }
            .alert("删除分类？", isPresented: $showDeleteAlert) {
                Button("取消", role: .cancel) {
                    pendingDelete = nil
                }
                Button("删除", role: .destructive) {
                    if let pendingDelete {
                        Task { await delete(pendingDelete) }
                    }
                }
            } message: {
                if let pendingDelete {
                    Text("将删除「\(pendingDelete.name)」。已使用该分类的任务和习惯会显示为未分类。")
                } else {
                    Text("已使用该分类的任务和习惯会显示为未分类。")
                }
            }
        }
    }

    @MainActor
    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            categories = try await repository.allCategories()
        } catch {
            print("CategoryManagementView reload failed: \(error)")
            // Preserve the last known categories instead of flashing an empty list on transient store errors.
        }
    }

    @MainActor
    private func mergeSavedCategory(_ category: TaskCategory) {
        if let index = categories.firstIndex(where: { $0.uid == category.uid }) {
            categories[index] = category
        } else {
            categories.append(category)
        }
        categories.sort {
            if $0.sortOrder != $1.sortOrder {
                return $0.sortOrder < $1.sortOrder
            }
            if $0.name != $1.name {
                return $0.name < $1.name
            }
            return $0.uid < $1.uid
        }
    }

    @MainActor
    private func delete(_ category: TaskCategory) async {
        defer { pendingDelete = nil }
        do {
            try await repository.deleteCategory(uid: category.uid)
            await reload()
        } catch {
            print("CategoryManagementView delete failed: \(error)")
            await reload()
        }
    }
}
