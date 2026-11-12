import EventKitUI
import SwiftUI

/// The system editor owns calendar selection and the user's final save/cancel.
/// It requires no broad calendar-reading permission on supported iOS versions.
struct TaskDetailCalendarEditor: UIViewControllerRepresentable {
  let item: DDLItem
  @Environment(\.dismiss) private var dismiss

  func makeCoordinator() -> Coordinator { Coordinator(onDone: { dismiss() }) }

  func makeUIViewController(context: Context) -> EKEventEditViewController {
    let editor = EKEventEditViewController()
    let store = EKEventStore()
    let event = EKEvent(eventStore: store)
    let due = DeadlineDateParser.safeParseOptional(item.endTime) ?? Date()
    let start = DeadlineDateParser.safeParseOptional(item.startTime) ?? due
    event.title = item.name
    event.notes = item.note
    event.startDate = min(start, due)
    event.endDate = max(due, event.startDate.addingTimeInterval(3600))
    editor.eventStore = store
    editor.event = event
    editor.editViewDelegate = context.coordinator
    return editor
  }

  func updateUIViewController(_ uiViewController: EKEventEditViewController, context: Context) {}

  final class Coordinator: NSObject, EKEventEditViewDelegate {
    private let onDone: () -> Void
    init(onDone: @escaping () -> Void) { self.onDone = onDone }
    func eventEditViewController(
      _ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction
    ) {
      onDone()
    }
  }
}
