//
//  DeadlinerWidgetLiveActivity.swift
//  DeadlinerWidget
//
//  Created by Aritx 音唯 on 2026/3/6.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct DeadlinerWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct DeadlinerWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DeadlinerWidgetAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension DeadlinerWidgetAttributes {
    fileprivate static var preview: DeadlinerWidgetAttributes {
        DeadlinerWidgetAttributes(name: "World")
    }
}

extension DeadlinerWidgetAttributes.ContentState {
    fileprivate static var smiley: DeadlinerWidgetAttributes.ContentState {
        DeadlinerWidgetAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: DeadlinerWidgetAttributes.ContentState {
         DeadlinerWidgetAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: DeadlinerWidgetAttributes.preview) {
   DeadlinerWidgetLiveActivity()
} contentStates: {
    DeadlinerWidgetAttributes.ContentState.smiley
    DeadlinerWidgetAttributes.ContentState.starEyes
}
