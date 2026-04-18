//
//  finosWidgetBundle.swift
//  finosWidget
//
//  Created by FinOS on 4/18/26.
//

import WidgetKit
import SwiftUI

@main
struct finosWidgetBundle: WidgetBundle {
    var body: some Widget {
        finosWidget()
        finosWidgetControl()
        finosWidgetLiveActivity()
    }
}
