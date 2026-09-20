//
//  fitpicApp.swift
//  fitpic
//
//  Created by Paul Garell on 9/20/26.
//

import SwiftUI

@main
struct fitpicApp: App {
    var body: some Scene {
        WindowGroup {
            MainTabView()
                .preferredColorScheme(.none) // Respect system appearance
        }
    }
}
