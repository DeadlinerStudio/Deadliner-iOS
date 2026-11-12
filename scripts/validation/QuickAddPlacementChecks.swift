import Foundation
import CoreGraphics

@main
struct QuickAddPlacementChecks {
    static func main() {
        var count = 0
        for size in [CGSize(width: 320, height: 480), CGSize(width: 390, height: 760),
                     CGSize(width: 700, height: 180), CGSize(width: 840, height: 600),
                     CGSize(width: 1024, height: 760), CGSize(width: 1366, height: 900)] {
            // Native dock, focus accessory, and side-toolbar layouts report different safe edges.
            for accessoryHeight: CGFloat in [0, 72, 136] {
                let boundary = size.height - accessoryHeight
                let region = QuickAddPanelPlacement(size: size, bottomBoundary: boundary).region
                precondition(region.width >= 0 && region.height >= 0, "Negative panel region")
                precondition(CGRect(origin: .zero, size: size).contains(region), "Panel leaves window")
                precondition(abs(region.maxY - (boundary - 26)) < 0.001, "AI composer clearance changed")
                precondition(region.minX == 16 && region.maxX == size.width - 16, "Horizontal clearance changed")
                count += 1
            }
        }
        // A stale page measurement during keyboard animation must not move the card below the keyboard.
        let keyboardWindow = CGSize(width: 390, height: 260)
        let stale = QuickAddPanelPlacement(size: keyboardWindow, bottomBoundary: 720)
        let fallback = QuickAddPanelPlacement(size: keyboardWindow, bottomBoundary: nil)
        precondition(stale.region == fallback.region, "Stale boundary escapes keyboard viewport")
        let tiny = QuickAddPanelPlacement(size: CGSize(width: 320, height: 20), bottomBoundary: 20)
        precondition(tiny.region.height == 0, "Tiny window produces a negative region")
        print("Passed \(count) dock clearance checks, keyboard fallback and tiny-window checks")
    }
}
