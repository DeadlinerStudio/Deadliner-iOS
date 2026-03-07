//
//  LinearProgressView.swift
//  Deadliner
//
//  Created by Aritx 音唯 on 2026/3/6.
//

import SwiftUI


// Source - https://stackoverflow.com/a/79056508
// Posted by Mojtaba Hosseini, modified by community. See post 'Timeline' for change history
// Retrieved 2026-03-06, License - CC BY-SA 4.0

struct LinearProgressView<Shape: SwiftUI.Shape>: View {
    var value: Double
    var shape: Shape

    var body: some View {
        shape.fill(.foreground.quaternary)
             .overlay(alignment: .leading) {
                 GeometryReader { proxy in
                     shape.fill(.tint)
                          .frame(width: proxy.size.width * value)
                 }
             }
             .clipShape(shape)
    }
}
