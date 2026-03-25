//
//  ColorExtension.swift
//  Deadliner
//
//  Created by Aritx 音唯 on 2026/2/20.
//

import SwiftUI
import UIKit

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }

        // 支持 RGB(6) 或 ARGB(8)
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)

        let a, r, g, b: Double
        switch s.count {
        case 6: // RRGGBB
            a = 1.0
            r = Double((value >> 16) & 0xFF) / 255.0
            g = Double((value >> 8) & 0xFF) / 255.0
            b = Double(value & 0xFF) / 255.0
        case 8: // AARRGGBB
            a = Double((value >> 24) & 0xFF) / 255.0
            r = Double((value >> 16) & 0xFF) / 255.0
            g = Double((value >> 8) & 0xFF) / 255.0
            b = Double(value & 0xFF) / 255.0
        default:
            a = 1.0; r = 0; g = 0; b = 0 // 非法输入就回退黑色
        }

        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    func adjusted(hueBy: CGFloat = 0, saturationBy: CGFloat = 0, brightnessBy: CGFloat = 0, opacityBy: CGFloat = 0) -> Color {
        let uiColor = UIColor(self)

        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var opacity: CGFloat = 0

        guard uiColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &opacity) else {
            return self
        }

        let wrappedHue = (hue + hueBy).truncatingRemainder(dividingBy: 1)
        let finalHue = wrappedHue < 0 ? wrappedHue + 1 : wrappedHue

        return Color(
            uiColor: UIColor(
                hue: finalHue,
                saturation: min(max(saturation + saturationBy, 0), 1),
                brightness: min(max(brightness + brightnessBy, 0), 1),
                alpha: min(max(opacity + opacityBy, 0), 1)
            )
        )
    }

    func vividBlend(with other: Color, ratio: CGFloat, saturationFloor: CGFloat = 0.72, brightnessFloor: CGFloat = 0.82) -> Color {
        let clampedRatio = min(max(ratio, 0), 1)

        let lhs = UIColor(self)
        let rhs = UIColor(other)

        var lh: CGFloat = 0
        var ls: CGFloat = 0
        var lb: CGFloat = 0
        var la: CGFloat = 0
        var rh: CGFloat = 0
        var rs: CGFloat = 0
        var rb: CGFloat = 0
        var ra: CGFloat = 0

        guard lhs.getHue(&lh, saturation: &ls, brightness: &lb, alpha: &la),
              rhs.getHue(&rh, saturation: &rs, brightness: &rb, alpha: &ra) else {
            return self
        }

        let hueDelta = colorShortestHueDelta(from: lh, to: rh)
        let mixedHue = colorNormalizedHue(lh + hueDelta * clampedRatio)
        let mixedSaturation = max(saturationFloor, ls + (rs - ls) * clampedRatio)
        let mixedBrightness = max(brightnessFloor, lb + (rb - lb) * clampedRatio)
        let mixedOpacity = la + (ra - la) * clampedRatio

        return Color(
            uiColor: UIColor(
                hue: mixedHue,
                saturation: min(max(mixedSaturation, 0), 1),
                brightness: min(max(mixedBrightness, 0), 1),
                alpha: min(max(mixedOpacity, 0), 1)
            )
        )
    }

}

private func colorShortestHueDelta(from start: CGFloat, to end: CGFloat) -> CGFloat {
    var delta = end - start
    if delta > 0.5 { delta -= 1 }
    if delta < -0.5 { delta += 1 }
    return delta
}

private func colorNormalizedHue(_ hue: CGFloat) -> CGFloat {
    let wrapped = hue.truncatingRemainder(dividingBy: 1)
    return wrapped < 0 ? wrapped + 1 : wrapped
}
