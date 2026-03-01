//
//  AlfieApp.swift
//  Alfie
//
//  Created by Evan Robert Stoddard on 2/18/26.
//

import SwiftUI

@main
struct AlfieApp: App {
    @State private var bleManager = BLEManager()
    @State private var messageService = MessageService()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environment(bleManager)
                .environment(messageService)
        }
    }
}
