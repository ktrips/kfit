//
//  kfitWidgetLiveActivity.swift
//  kfitWidget
//
//  Created by Kenichi Yoshida on 2026/05/12.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct kfitWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct kfitWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: kfitWidgetAttributes.self) { context in
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

extension kfitWidgetAttributes {
    fileprivate static var preview: kfitWidgetAttributes {
        kfitWidgetAttributes(name: "World")
    }
}

extension kfitWidgetAttributes.ContentState {
    fileprivate static var smiley: kfitWidgetAttributes.ContentState {
        kfitWidgetAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: kfitWidgetAttributes.ContentState {
         kfitWidgetAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: kfitWidgetAttributes.preview) {
   kfitWidgetLiveActivity()
} contentStates: {
    kfitWidgetAttributes.ContentState.smiley
    kfitWidgetAttributes.ContentState.starEyes
}
