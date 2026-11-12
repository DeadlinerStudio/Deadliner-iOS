#if canImport(Shared)
import SwiftUI
import Shared

struct FocusPickerOption: Identifiable {
    let uid: String
    let title: String
    let habit: Bool
    var id: String { (habit ? "habit:" : "task:") + uid }
}

/// Both home and management use this native search/grid; the initial selection is the only difference.
struct FocusTargetChooser: View {
    let options: [FocusPickerOption]
    let selectedUID: String
    let selectedHabit: Bool
    let busy: Bool
    let onSelect: (FocusPickerOption) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var habit = false
    @State private var query = ""
    @State private var width: CGFloat = 350
    private var matches: [FocusPickerOption] {
        options.filter { $0.habit == habit && (query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            $0.title.localizedCaseInsensitiveContains(query.trimmingCharacters(in: .whitespacesAndNewlines))) }
    }
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: width < 312 || typeSize >= .xxxLarge ? 1 : 2)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 24) {
                typeTab("任务", value: false)
                typeTab("习惯", value: true)
            }
            Text("\(matches.count) 个目标").font(.caption).foregroundStyle(.secondary)
            if matches.isEmpty {
                ContentUnavailableView("没有匹配的可专注目标", systemImage: "magnifyingglass",
                    description: Text(query.isEmpty ? "前往任务或习惯列表创建、恢复目标。" : "换个关键词试试。"))
            } else {
                tiles
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .searchable(text: $query, prompt: "搜索任务或习惯")
        .onAppear { habit = selectedHabit }
        .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: habit)
    }
    @ViewBuilder private var tiles: some View {
        if #available(iOS 26, *) { GlassEffectContainer(spacing: 12) { grid } }
        else { grid }
    }
    private var grid: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            ForEach(matches) { option in
                let selected = selectedUID == option.uid && selectedHabit == option.habit
                Button { withAnimation(reduceMotion ? nil : .smooth(duration: 0.28)) { onSelect(option) } } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(option.title).font(.subheadline.weight(selected ? .semibold : .medium)).lineLimit(2)
                        if selected { Text("当前选择").font(.caption) }
                    }
                    .foregroundStyle(selected ? Color.accentColor : .primary)
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading).padding(14)
                    .contentShape(RoundedRectangle(cornerRadius: 24))
                }
                .buttonStyle(.plain).modifier(FocusPickerMaterial(selected: selected))
                .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(selected ? Color.accentColor.opacity(0.65) : .clear, lineWidth: 1))
                .disabled(busy).accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
    private func typeTab(_ title: String, value: Bool) -> some View {
        Button { habit = value } label: {
            VStack(spacing: 8) {
                Text(title).font(.headline.weight(habit == value ? .semibold : .regular))
                    .foregroundStyle(habit == value ? Color.primary : .secondary)
                Capsule().fill(habit == value ? Color.accentColor : .clear).frame(width: 18, height: 3)
            }.frame(minWidth: 48, minHeight: 48)
        }.buttonStyle(.plain).disabled(busy).accessibilityAddTraits(habit == value ? .isSelected : [])
    }
}

private struct FocusPickerMaterial: ViewModifier {
    let selected: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26, *), !reduceTransparency {
            content.glassEffect(.regular.tint(selected ? Color.accentColor.opacity(0.14) : .clear).interactive(),
                                in: RoundedRectangle(cornerRadius: 24))
        } else {
            content.background(selected ? Color.accentColor.opacity(0.12) : Color(uiColor: .secondarySystemGroupedBackground),
                               in: RoundedRectangle(cornerRadius: 24))
        }
    }
}
#endif
