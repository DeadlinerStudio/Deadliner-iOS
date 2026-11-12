import SwiftUI

struct QuickAddGlassPanel: View {
    @Binding var input: String
    let draft: QuickAddDraft
    let modelStatus: QuickAddModelDownloadStatus
    let loading: Bool
    let saving: Bool
    let recognizingAI: Bool
    let message: String
    let canSave: Bool
    let categoryName: String?
    let availableHeight: CGFloat
    var backend: QuickAddBackend = .kivo
    var language: String = "zh"
    var startAt: Date? = nil
    var onRemoveAttribute: (QuickAddAttribute) -> Void = { _ in }
    var onRemoveCategory: () -> Void = {}
    var categories: [TaskCategory] = []
    var selectedCategoryUID: String? = nil
    var onSelectCategory: (String?) -> Void = { _ in }
    var morphSource: QuickAddMorphSource? = nil
    var morphProgress: CGFloat = 1
    var inputFocused: FocusState<Bool>.Binding
    let onClose: () -> Void
    let onExpand: () -> Void
    let onCategory: () -> Void
    let onAttribute: (QuickAddAttribute) -> Void
    let onAI: () -> Void
    let onSave: () -> Void
    let onRetry: () -> Void

    @State private var contentHeight: CGFloat = 180
    @State private var headerHeight: CGFloat = 48
    @State private var footerHeight: CGFloat = 52
    private var busy: Bool { saving || recognizingAI }

    var body: some View {
        Group {
            if availableHeight < headerHeight + footerHeight + 96 {
                // In a very short keyboard window, let every control remain reachable by scrolling.
                ScrollView {
                    VStack(spacing: 12) { header; content; actions }
                }
                .frame(maxHeight: max(0, availableHeight - 32))
                .scrollBounceBehavior(.basedOnSize)
                .scrollDismissesKeyboard(.interactively)
            } else {
                VStack(spacing: 12) {
                    header
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
                    ScrollView {
                        content
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
                    }
                    .frame(height: min(contentHeight, max(0, availableHeight - headerHeight - footerHeight - 56)))
                    .animation(.smooth(duration: 0.22), value: contentHeight)
                    .scrollBounceBehavior(.basedOnSize)
                    .scrollDismissesKeyboard(.interactively)
                    actions
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { footerHeight = $0 }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .modifier(QuickAddMorphSurface(source: morphSource, progress: morphProgress))
        .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .onTapGesture { }
        .accessibilityIdentifier("quickAdd.panel")
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("快速添加")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            roundButton("展开完整表单", symbol: "arrow.up.left.and.arrow.down.right", action: onExpand)
            roundButton("关闭快速添加", symbol: "xmark", action: onClose)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("明天下午3点交报告 / 每天读书", text: $input, axis: .vertical)
                .font(.body)
                .lineLimit(1...5)
                .focused(inputFocused)
                .disabled(busy)
                .accessibilityLabel("输入任务或习惯")
                .accessibilityIdentifier("quickAdd.input")
            modelState
            if !draft.title.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(sourceLabel + " · " + (draft.needsAI || !draft.ready ? "待确认草案" : (draft.kind == "HABIT" ? "习惯草案" : "任务草案")))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.tint)
                    Label(draft.title, systemImage: draft.kind == "HABIT" ? "repeat" : "checklist")
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 16))
                .accessibilityElement(children: .combine)
            }
            properties
            if loading || busy || !message.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    if loading || busy { ProgressView().controlSize(.small) }
                    Text(saving ? "正在添加…" : recognizingAI ? "正在生成草案…" : loading ? "正在识别…" : message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var modelState: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: modelStatus.phase == "READY" ? "checkmark.circle" : "circle.dotted")
                Text(modelStatus.phase == "READY" ? backend.modelName(language: language) + " 已就绪" : modelStatus.label)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if modelStatus.retryable {
                    Button("重试", action: onRetry).disabled(busy)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if modelStatus.phase == "DOWNLOADING" { ProgressView(value: modelStatus.progress) }
        }
    }

    private var properties: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], alignment: .leading, spacing: 8) {
            if let categoryName {
                QuickAddPropertyChip(title: categoryName, symbol: "folder", onEdit: onCategory, onRemove: onRemoveCategory)
            }
            if draft.kind == "HABIT" {
                if !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    property(draft.detail.components(separatedBy: " · 提醒").first ?? "重复规则", symbol: "repeat", attribute: .schedule)
                    if let reminder = draft.reminderTime { property("提醒 " + reminder, symbol: "bell", attribute: .reminder) }
                }
            } else {
                if let startAt {
                    property("开始 " + compactDate(startAt), symbol: "circle.fill", color: .green, attribute: .start)
                }
                if draft.dueAt != nil { property("截止 " + dueLabel, symbol: "circle.fill", color: .red, attribute: .due) }
            }
            if !draft.note.isEmpty { property(draft.note, symbol: "note.text", attribute: .note) }
        }
        .disabled(busy)
    }

    private var actions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                attributeActions
                if !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { aiButton }
                Spacer(minLength: 0)
                saveButton
            }
            VStack(spacing: 8) {
                HStack(spacing: 6) { attributeActions; Spacer(minLength: 0) }
                HStack(spacing: 6) {
                    if !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { aiButton }
                    Spacer(minLength: 0)
                    saveButton
                }
            }
        }
    }

    @ViewBuilder private var attributeActions: some View {
        Menu {
            Button("不分类") { onSelectCategory(nil) }
            ForEach(categories) { category in
                Button {
                    onSelectCategory(category.uid)
                } label: {
                    if category.uid == selectedCategoryUID { Label(category.name, systemImage: "checkmark") }
                    else { Label(category.name, systemImage: CategoryPresentationSupport.safeIconKey(category.iconKey)) }
                }
            }
            Divider()
            Button("选择或新建分类…", action: onCategory)
        } label: {
            Image(systemName: "folder")
                .font(.system(size: 18))
                .frame(width: 44, height: 44)
                .background(.primary.opacity(0.06), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .accessibilityLabel(categoryName.map { "分类：" + $0 } ?? "选择分类")
        Button {
            onAttribute(draft.kind == "HABIT" ? .schedule : .due)
        } label: {
            HStack(spacing: 6) {
                if draft.kind == "HABIT" { Image(systemName: "repeat") }
                else { Circle().fill(.red).frame(width: 8, height: 8) }
                Text(draft.kind == "HABIT" ? "重复" : "截止")
                    .font(.caption).lineLimit(1).fixedSize()
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(.primary.opacity(0.06), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .contextMenu {
            Button(draft.kind == "HABIT" ? "提醒时间" : "开始时间") {
                onAttribute(draft.kind == "HABIT" ? .reminder : .start)
            }
        }
        roundButton("编辑备注", symbol: "note.text") { onAttribute(.note) }
    }

    private var aiButton: some View {
        Button(action: onAI) {
            HStack(spacing: 4) {
                if recognizingAI { ProgressView().controlSize(.small) }
                else { Image(systemName: "sparkles") }
                Text("AI").font(.caption.weight(.medium))
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(.primary.opacity(0.06), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("使用 AI 识别")
        .disabled(busy)
    }

    private var saveButton: some View {
        Button(action: onSave) {
            Image(systemName: "arrow.up")
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 44, height: 44)
                .foregroundStyle(Color.white)
                .background(Color.accentColor, in: Circle())
                .opacity(canSave ? 1 : 0.35)
        }
        .buttonStyle(.plain)
        .disabled(!canSave)
        .accessibilityLabel(saving ? "正在添加" : "添加草案")
        .accessibilityIdentifier("quickAdd.save")
    }

    private func property(_ title: String, symbol: String, color: Color = .primary, attribute: QuickAddAttribute) -> some View {
        QuickAddPropertyChip(title: title, symbol: symbol, color: color,
                             onEdit: { onAttribute(attribute) }, onRemove: { onRemoveAttribute(attribute) })
    }

    private func compactDate(_ date: Date) -> String {
        date.formatted(.dateTime.month().day().hour().minute())
    }

    private func roundButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 44, height: 44)
                .background(.primary.opacity(0.06), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .disabled(busy)
    }

    private var sourceLabel: String {
        switch draft.source {
        case "MODEL": return backend.modelName(language: language)
        case "AI": return "AI"
        case "MANUAL": return "手动"
        default: return "规则"
        }
    }

    private var dueLabel: String {
        guard let raw = draft.dueAt else { return "截止时间" }
        guard let date = DeadlineDateParser.safeParseOptional(raw) else { return raw }
        return date.formatted(.dateTime.month().day().hour().minute())
    }
}
