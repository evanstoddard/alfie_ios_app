//
//  MainView.swift
//  Alfie
//
//  Created by Evan Robert Stoddard on 2/18/26.
//

import SwiftUI

struct MainView: View {
    @Environment(MessageService.self) private var messageService

    private var totalUnread: Int {
        messageService.conversations.reduce(0) { $0 + $1.unreadCount }
    }

    var body: some View {
        TabView {
            Tab("Conversations", systemImage: "message") {
                MessagesView()
            }
            .badge(totalUnread)

            Tab("Contacts", systemImage: "person.crop.circle") {
                ContactsView()
            }

            Tab("Settings", systemImage: "gear") {
                SettingsView()
            }
        }
    }
}

#Preview {
    MainView()
        .environment(BLEManager())
        .environment(MessageService())
}
