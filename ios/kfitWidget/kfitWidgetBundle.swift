//
//  kfitWidgetBundle.swift
//  kfitWidget
//
//  Created by Kenichi Yoshida on 2026/05/12.
//

import WidgetKit
import SwiftUI

@main
struct kfitWidgetBundle: WidgetBundle {
    var body: some Widget {
        kfitWidget()
        kfitWidgetControl()
        kfitWidgetLiveActivity()
    }
}
