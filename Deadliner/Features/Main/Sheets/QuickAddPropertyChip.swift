import SwiftUI

/// Editing and removing are separate accessible targets, as in the other clients.
struct QuickAddPropertyChip: View {
    let title: String
    let symbol: String
    var color: Color = .primary
    let onEdit: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onEdit) {
                Label(title, systemImage: symbol)
                    .font(.caption)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.leading, 12)
            }
            .accessibilityLabel("编辑" + title)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.medium))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("移除" + title)
        }
        .buttonStyle(.plain)
        .foregroundStyle(color)
        .background(color.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
    }
}
