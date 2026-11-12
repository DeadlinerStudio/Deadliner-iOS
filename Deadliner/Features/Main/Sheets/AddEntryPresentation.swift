import SwiftUI

struct QuickAddFloatingAction {
    let tint: Color
    let bottomInset: CGFloat
    let onTap: () -> Void
}

/// Native FAB metrics feed a single continuously sized card surface; toolbars use a bottom slide.
private struct AddEntryPresentation: ViewModifier {
    @Binding var isPresented: Bool
    let selection: TaskSegment
    let bottomBoundary: CGFloat?
    let floatingAction: QuickAddFloatingAction?
    @AppStorage("quick_add_enabled") private var quickAddEnabled = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var fabFrame: CGRect = .zero

    private var showsQuickAdd: Bool { isPresented && quickAddEnabled }
    private var showsFullEditor: Binding<Bool> {
        Binding(get: { isPresented && !quickAddEnabled }, set: { isPresented = $0 })
    }
    private var transition: AnyTransition {
        if reduceMotion { return .opacity }
        return floatingAction == nil ? .move(edge: .bottom).combined(with: .opacity) : .identity
    }

    func body(content: Content) -> some View {
        content
            .accessibilityHidden(showsQuickAdd)
            .allowsHitTesting(!showsQuickAdd)
            .overlay {
                GlassEffectContainer(spacing: 12) {
                    ZStack(alignment: .bottom) {
                        if let floatingAction, !showsQuickAdd {
                            floatingButton(floatingAction)
                                .padding(.bottom, floatingAction.bottomInset)
                                .transition(reduceMotion ? .opacity : .identity)
                        }
                        if showsQuickAdd {
                            QuickAddEntrySheetView(
                                repository: PersistenceStores.tasks,
                                initialKind: selection == .habits ? "HABIT" : "TASK",
                                bottomBoundary: bottomBoundary,
                                morphSource: !reduceMotion && !fabFrame.isEmpty
                                ? floatingAction.map { QuickAddMorphSource(frame: fabFrame, tint: $0.tint) } : nil,
                                onDone: { isPresented = false }
                            )
                            .accessibilityAddTraits(.isModal)
                            .transition(transition)
                        }
                    }
                    // The outer frame must also align at the bottom: its default center
                    // overrides the intrinsic ZStack's alignment when only the FAB exists.
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
                .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.5, dampingFraction: 0.9),
                           value: showsQuickAdd)
        }
        .sheet(isPresented: showsFullEditor) {
            AddEntrySheetView(repository: PersistenceStores.tasks, initialSelection: selection)
                .presentationDetents([.large])
        }
    }

    private func floatingButton(_ action: QuickAddFloatingAction) -> some View {
        // Preserve the original FAB verbatim: 48pt is the label, not the outer
        // diameter. The native style owns the padding, glass and press response.
        Button(action: action.onTap) {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .semibold))
                .frame(width: 48, height: 48)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .tint(action.tint)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { fabFrame = $0 }
        .accessibilityLabel("添加")
        .accessibilityIdentifier("home.add")
    }

}

extension View {
    func addEntryPresentation(isPresented: Binding<Bool>, selection: TaskSegment,
                              bottomBoundary: CGFloat?, floatingAction: QuickAddFloatingAction? = nil) -> some View {
        modifier(AddEntryPresentation(isPresented: isPresented, selection: selection,
                                      bottomBoundary: bottomBoundary, floatingAction: floatingAction))
    }
}
