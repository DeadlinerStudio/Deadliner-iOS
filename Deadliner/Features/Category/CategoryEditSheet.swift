//
//  CategoryEditSheet.swift
//  Deadliner
//
//  Created by Codex on 2026/7/17.
//

import SwiftUI

struct CategoryEditSheet: View {
    @Environment(\.dismiss) private var dismiss

    let category: TaskCategory?
    var onSaved: (TaskCategory) -> Void

    @State private var name: String
    @State private var iconKey: String
    @State private var colorHex: String
    @State private var isSaving = false
    @State private var alertMessage: String?
    @State private var showAlert = false

    private let repository: any CategoryPersistenceStore = PersistenceStores.categories

    init(category: TaskCategory? = nil, onSaved: @escaping (TaskCategory) -> Void) {
        self.category = category
        self.onSaved = onSaved
        _name = State(initialValue: category?.name ?? "")
        _iconKey = State(initialValue: CategoryPresentationSupport.semanticIconKey(category?.iconKey ?? "tag"))
        _colorHex = State(initialValue: CategoryPresentationSupport.normalizedColorHex(category?.colorHex ?? "#3B82F6"))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: CategoryPresentationSupport.systemImageName(for: iconKey))
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(Color(hex: colorHex))
                            .frame(width: 52, height: 52)
                            .background(Color(hex: colorHex).opacity(0.14), in: Circle())

                        VStack(alignment: .leading, spacing: 4) {
                            Text(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "新分类" : name)
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Text(category == nil ? "新建分类" : "编辑分类")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 4)
                }

                Section("基础信息") {
                    TextField("分类名称", text: $name)
                }

                Section("图标") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
                        ForEach(CategoryPresentationSupport.iconOptions, id: \.self) { icon in
                            Button {
                                iconKey = icon
                            } label: {
                                Image(systemName: CategoryPresentationSupport.systemImageName(for: icon))
                                    .font(.system(size: 17, weight: .semibold))
                                    .frame(width: 38, height: 38)
                                    .foregroundStyle(iconKey == icon ? .white : Color(hex: colorHex))
                                    .background(iconKey == icon ? Color(hex: colorHex) : Color(hex: colorHex).opacity(0.12), in: Circle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("颜色") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5), spacing: 14) {
                        ForEach(CategoryPresentationSupport.colorOptions, id: \.self) { color in
                            Button {
                                colorHex = color
                            } label: {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color(hex: color))
                                        .frame(height: 36)

                                    if colorHex == color {
                                        Image(systemName: "checkmark")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle(category == nil ? "添加分类" : "编辑分类")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("取消")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await save() }
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("保存")
                }
            }
            .alert("提示", isPresented: $showAlert) {
                Button("确定", role: .cancel) {}
            } message: {
                Text(alertMessage ?? "")
            }
        }
    }

    @MainActor
    private func save() async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isSaving = true
        defer { isSaving = false }

        do {
            let saved: TaskCategory
            if var category {
                category.name = trimmed
                category.iconKey = iconKey
                category.colorHex = colorHex
                try await repository.updateCategory(category)
                saved = category
            } else {
                saved = try await repository.createCategory(name: trimmed, iconKey: iconKey, colorHex: colorHex)
            }
            onSaved(saved)
            dismiss()
        } catch {
            alertMessage = "保存失败：\(error.localizedDescription)"
            showAlert = true
        }
    }
}
