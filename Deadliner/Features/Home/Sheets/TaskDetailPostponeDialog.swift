import Shared
import SwiftUI

struct TaskDetailPostponeDialog: View {
  let item: DDLItem
  let onConfirm: (Int, Bool) async throws -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var inHours = true
  @State private var amount = 1
  @State private var isSaving = false
  @State private var errorText: String?

  private var delay: TaskDeadlineDelay {
    TaskDeadlineDelay(amount: Int32(amount), unit: inHours ? .hours : .days)
  }
  private var preview: String? {
    TaskDeadlineShift.shared.postponed(raw: item.endTime, delay: delay)
  }
  private var unitSelection: Binding<Bool> {
    Binding(
      get: { inHours },
      set: { hours in
        // Clamp before the unit picker changes the numeric range, avoiding an invalid selection.
        let maximum = TaskDeadlineDelay(amount: 1, unit: hours ? .hours : .days).maximum
        amount = min(amount, Int(maximum))
        inHours = hours
        errorText = nil
      })
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 16) {
          Text("单次最多延后 7 天（168 小时）")
            .font(.subheadline).foregroundStyle(.secondary)
          HStack(spacing: 0) {
            Picker("延后数量", selection: $amount) {
              ForEach(1...Int(delay.maximum), id: \.self) { value in
                Text(value.formatted()).tag(value)
              }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 150)
            .clipped()
            .accessibilityIdentifier("detail.postpone.amount")
            Picker("延后单位", selection: unitSelection) {
              Text("小时").tag(true)
              Text("天").tag(false)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 150)
            .clipped()
            .accessibilityIdentifier("detail.postpone.unit")
          }
          .pickerStyle(.wheel)
          .labelsHidden()
          .frame(height: 150)
          VStack(alignment: .leading, spacing: 12) {
            previewRow("原截止", raw: item.endTime, emphasized: false)
            previewRow("延后至", raw: preview, emphasized: true)
          }
          .padding(16)
          .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 20))
          if let errorText {
            Text(errorText).font(.footnote).foregroundStyle(.red)
              .accessibilityIdentifier("detail.postpone.error")
          }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .disabled(isSaving)
      }
      .scrollBounceBehavior(.basedOnSize)
      .background(Color(uiColor: .systemGroupedBackground))
      .navigationTitle("延后截止时间")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("取消", role: .cancel) { dismiss() }.disabled(isSaving)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("确认延后", action: confirm)
            .disabled(isSaving || preview == nil || !delay.isValid)
            .accessibilityIdentifier("detail.postpone.confirm")
        }
      }
      .overlay { if isSaving { ProgressView("正在延后…") } }
    }
    .interactiveDismissDisabled(isSaving)
  }

  private func previewRow(_ label: String, raw: String?, emphasized: Bool) -> some View {
    LabeledContent(label) {
      Text(formattedDeadline(raw))
        .fontWeight(emphasized ? .semibold : .regular)
        .foregroundStyle(.primary)
        .multilineTextAlignment(.trailing)
        .accessibilityIdentifier(
          emphasized ? "detail.postpone.preview" : "detail.postpone.original")
    }
    .font(.subheadline)
  }

  private func formattedDeadline(_ raw: String?) -> String {
    guard let raw, let date = DeadlineDateParser.safeParseOptional(raw) else { return "无有效截止时间" }
    return date.formatted(date: .abbreviated, time: .shortened)
  }

  private func confirm() {
    guard !isSaving, delay.isValid, preview != nil else { return }
    isSaving = true
    errorText = nil
    _Concurrency.Task { @MainActor in
      defer { isSaving = false }
      do { try await onConfirm(amount, inHours) } catch { errorText = error.localizedDescription }
    }
  }
}
