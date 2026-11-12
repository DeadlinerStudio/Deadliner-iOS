import SwiftUI
import UIKit

/// UIKit exposes the menu-dismissal completion that SwiftUI Menu does not.
/// Sheet/alert actions are delivered only after that completion, once per selection.
struct TaskDetailMoreButton: UIViewRepresentable {
  let state: DDLState
  let hasDeadline: Bool
  let isEnabled: Bool
  let onPostpone: () -> Void
  let onGiveUp: () -> Void
  let onArchive: () -> Void
  let onCalendar: () -> Void
  let onDelete: () -> Void

  func makeUIView(context: Context) -> MenuButton {
    let button = MenuButton(type: .system)
    var configuration = UIButton.Configuration.plain()
    configuration.image = UIImage(systemName: "ellipsis")
    configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
      textStyle: .subheadline, scale: .medium)
    configuration.baseForegroundColor = .label
    configuration.contentInsets = .zero
    button.configuration = configuration
    button.tintColor = .label
    button.showsMenuAsPrimaryAction = true
    button.accessibilityLabel = "更多操作"
    button.accessibilityIdentifier = "detail.more"
    return button
  }

  func updateUIView(_ button: MenuButton, context: Context) {
    button.isEnabled = isEnabled
    // Replacing the menu during its dismissal can tear down the selected action.
    guard !button.isMenuVisible else { return }
    var actions: [UIMenuElement] = []
    if state.isActionable {
      actions.append(
        action(
          "延后…", image: "clock.arrow.trianglehead.2.counterclockwise.rotate.90",
          enabled: hasDeadline, button: button, handler: onPostpone))
      actions.append(action("放弃任务", image: "flag", button: button, handler: onGiveUp))
    }
    if state.canManualArchive {
      actions.append(action("归档任务", image: "archivebox", button: button, handler: onArchive))
    }
    actions.append(
      action(
        "保存到日历", image: "calendar.badge.plus",
        enabled: hasDeadline, button: button, handler: onCalendar))
    let deleteImage = UIImage(systemName: "trash")?.withTintColor(
      .systemRed, renderingMode: .alwaysOriginal)
    let delete = UIAction(title: "删除任务", image: deleteImage, attributes: .destructive) {
      [weak button] _ in
      button?.enqueue(onDelete)
    }
    actions.append(UIMenu(options: .displayInline, children: [delete]))
    button.menu = UIMenu(children: actions)
  }

  static func dismantleUIView(_ button: MenuButton, coordinator: ()) {
    button.cancelPendingAction()
  }

  private func action(
    _ title: String, image: String, enabled: Bool = true,
    button: MenuButton, handler: @escaping () -> Void
  ) -> UIAction {
    UIAction(
      title: title, image: UIImage(systemName: image),
      attributes: enabled ? [] : [.disabled]
    ) { [weak button] _ in
      button?.enqueue(handler)
    }
  }

  final class MenuButton: UIButton {
    private(set) var isMenuVisible = false
    private var pendingAction: (() -> Void)?

    func enqueue(_ action: @escaping () -> Void) {
      if isMenuVisible {
        pendingAction = action
      } else {
        // Also handle a UIKit action delivered after its dismissal completion.
        DispatchQueue.main.async(execute: action)
      }
    }

    func cancelPendingAction() { pendingAction = nil }

    override func contextMenuInteraction(
      _ interaction: UIContextMenuInteraction,
      willDisplayMenuFor configuration: UIContextMenuConfiguration,
      animator: (any UIContextMenuInteractionAnimating)?
    ) {
      super.contextMenuInteraction(
        interaction, willDisplayMenuFor: configuration, animator: animator)
      pendingAction = nil
      isMenuVisible = true
    }

    override func contextMenuInteraction(
      _ interaction: UIContextMenuInteraction,
      willEndFor configuration: UIContextMenuConfiguration,
      animator: (any UIContextMenuInteractionAnimating)?
    ) {
      super.contextMenuInteraction(interaction, willEndFor: configuration, animator: animator)
      let finish: () -> Void = { [weak self] in
        guard let self else { return }
        self.isMenuVisible = false
        let action = self.pendingAction
        self.pendingAction = nil
        action?()
      }
      if let animator {
        animator.addCompletion(finish)
      } else {
        DispatchQueue.main.async(execute: finish)
      }
    }
  }
}
