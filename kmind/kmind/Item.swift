//
//  Item.swift
//  kmind
//
//  Created by Kenichi Yoshida on 2026/06/27.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
