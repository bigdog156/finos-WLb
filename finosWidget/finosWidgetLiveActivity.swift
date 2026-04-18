//
//  finosWidgetLiveActivity.swift
//  finosWidget
//
//  Created by FinOS on 4/18/26.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct finosWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct finosWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: finosWidgetAttributes.self) { context in
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

extension finosWidgetAttributes {
    fileprivate static var preview: finosWidgetAttributes {
        finosWidgetAttributes(name: "World")
    }
}

extension finosWidgetAttributes.ContentState {
    fileprivate static var smiley: finosWidgetAttributes.ContentState {
        finosWidgetAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: finosWidgetAttributes.ContentState {
         finosWidgetAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: finosWidgetAttributes.preview) {
   finosWidgetLiveActivity()
} contentStates: {
    finosWidgetAttributes.ContentState.smiley
    finosWidgetAttributes.ContentState.starEyes
}
