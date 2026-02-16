//
//  Subscription_TrackerApp.swift
//  Subscription Tracker
//
//  Created by Oleksandr Klosovych on 11.02.2026.
//

import SwiftUI

@main
struct Subscription_TrackerApp: App {
    init() {
        #if DEBUG
        URLProtocol.registerClass(NetworkLogger.self)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
