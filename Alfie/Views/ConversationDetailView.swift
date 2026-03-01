//
//  ConversationDetailView.swift
//  Alfie
//
//  Created by Evan Robert Stoddard on 2/18/26.
//

import SwiftUI
import ExyteChat

struct ConversationDetailView: View {
    let conversation: Conversation

    @Environment(MessageService.self) private var messageService

    private var currentUser: User {
        User(id: "local", name: "Me", avatarURL: nil, isCurrentUser: true)
    }

    private var chatMessages: [Message] {
        let stored = messageService.messagesByConversation[conversation.deviceID] ?? []
        return stored.map { msg in
            let user: User
            if msg.isOutgoing {
                user = currentUser
            } else {
                user = User(
                    id: String(msg.senderDeviceID),
                    name: conversation.displayName,
                    avatarURL: nil,
                    isCurrentUser: false
                )
            }

            let status: Message.Status
            switch msg.status {
            case .sending: status = .sending
            case .sent: status = .sent
            case .failed: status = .error(DraftMessage(text: msg.text, medias: [], giphyMedia: nil, recording: nil, replyMessage: nil, createdAt: msg.timestamp))
            }

            return Message(
                id: msg.id.uuidString,
                user: user,
                status: status,
                createdAt: msg.timestamp,
                text: msg.text
            )
        }
    }

    var body: some View {
        ChatView(messages: chatMessages) { draft in
            Task {
                await messageService.sendMessage(to: conversation.deviceID, text: draft.text)
            }
        }
        .setAvailableInputs([.text])
        .showMessageMenuOnLongPress(false)
        .navigationTitle(conversation.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.hidden, for: .tabBar)
        .onAppear {
            messageService.markConversationRead(deviceID: conversation.deviceID)
        }
    }
}

#Preview {
    NavigationStack {
        ConversationDetailView(
            conversation: Conversation(
                deviceID: 1,
                lastMessageText: "Hello",
                lastMessageDate: Date(),
                unreadCount: 0,
                displayName: "Test Device"
            )
        )
        .environment(MessageService())
    }
}
