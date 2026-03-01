//
//  MessagesView.swift
//  Alfie
//
//  Created by Evan Robert Stoddard on 2/18/26.
//

import SwiftUI

struct MessagesView: View {
    @Environment(MessageService.self) private var messageService

    @State private var showingNewConversation = false
    @State private var selectedConversation: Conversation?

    var body: some View {
        NavigationSplitView {
            List(messageService.conversations, selection: $selectedConversation) { conversation in
                NavigationLink(value: conversation) {
                    ConversationRow(conversation: conversation)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        if selectedConversation?.deviceID == conversation.deviceID {
                            selectedConversation = nil
                        }
                        messageService.deleteConversation(deviceID: conversation.deviceID)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Conversations")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingNewConversation = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
            .overlay {
                if messageService.conversations.isEmpty {
                    ContentUnavailableView(
                        "No Conversations",
                        systemImage: "message",
                        description: Text("Messages will appear here when you send or receive them.")
                    )
                }
            }
            .sheet(isPresented: $showingNewConversation) {
                NewConversationView()
            }
        } detail: {
            if let conversation = selectedConversation {
                ConversationDetailView(conversation: conversation)
            } else {
                ContentUnavailableView(
                    "No Conversation Selected",
                    systemImage: "message",
                    description: Text("Select a conversation from the sidebar.")
                )
            }
        }
    }
}

// MARK: - New Conversation

struct NewConversationView: View {
    @Environment(MessageService.self) private var messageService
    @Environment(\.dismiss) private var dismiss

    @State private var deviceIDString = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Enter Device ID") {
                    TextField("Device ID (decimal or 0x hex)", text: $deviceIDString)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit { startConversation(with: deviceIDString) }
                }

                if !messageService.contacts.isEmpty {
                    Section("Contacts") {
                        ForEach(messageService.contacts) { contact in
                            Button {
                                openConversation(for: contact.deviceID)
                            } label: {
                                HStack(spacing: 12) {
                                    Circle()
                                        .fill(Color.green.opacity(0.2))
                                        .frame(width: 36, height: 36)
                                        .overlay {
                                            Text(contact.name.prefix(1))
                                                .font(.subheadline.weight(.medium))
                                                .foregroundStyle(.green)
                                        }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(contact.name)
                                            .foregroundStyle(.primary)
                                        Text(contact.formattedDeviceID)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .monospaced()
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("New Conversation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Open") { startConversation(with: deviceIDString) }
                        .disabled(deviceIDString.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func startConversation(with input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        let deviceID: UInt32?
        if trimmed.hasPrefix("0x") || trimmed.hasPrefix("0X") {
            deviceID = UInt32(trimmed.dropFirst(2), radix: 16)
        } else {
            deviceID = UInt32(trimmed)
        }
        guard let id = deviceID else { return }
        openConversation(for: id)
    }

    private func openConversation(for deviceID: UInt32) {
        messageService.ensureConversation(for: deviceID)
        dismiss()
    }
}

struct ConversationRow: View {
    let conversation: Conversation

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.blue.opacity(0.2))
                .frame(width: 50, height: 50)
                .overlay {
                    Text(conversation.displayName.prefix(1))
                        .font(.title2)
                        .fontWeight(.medium)
                        .foregroundStyle(.blue)
                }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(conversation.displayName)
                        .font(.headline)

                    Spacer()

                    Text(conversation.lastMessageDate, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text(conversation.lastMessageText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer()

                    if conversation.unreadCount > 0 {
                        Text("\(conversation.unreadCount)")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.blue, in: Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    MessagesView()
        .environment(MessageService())
}
