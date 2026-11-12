import SwiftUI
import UIKit

/// Detects the device capability, independently of its current fold angle or width.
struct HingedDeviceObserver: UIViewRepresentable {
    @Binding var hasHinge: Bool

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        if #available(iOS 27.1, *) {
            view.addInteraction(UIHingeInteraction { _, update in
                let hasHinge = update.hinge != nil
                Task { @MainActor in
                    self.hasHinge = hasHinge
                }
            })
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
