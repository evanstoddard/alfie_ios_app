//
//  ContactsView.swift
//  Alfie
//
//  Created by Evan Robert Stoddard on 2/18/26.
//

import SwiftUI

struct ContactsView: View {
    @Environment(MessageService.self) private var messageService
    @State private var showingAddContact = false
    @State private var navigateToConversation: Conversation?

    var body: some View {
        NavigationStack {
            List {
                ForEach(messageService.contacts) { contact in
                    Button {
                        messageService.ensureConversation(for: contact.deviceID)
                        if let conv = messageService.conversations.first(where: { $0.deviceID == contact.deviceID }) {
                            navigateToConversation = conv
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Color.green.opacity(0.2))
                                .frame(width: 40, height: 40)
                                .overlay {
                                    Text(contact.name.prefix(1))
                                        .font(.headline)
                                        .foregroundStyle(.green)
                                }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(contact.name)
                                    .font(.body)
                                    .foregroundStyle(.primary)

                                Text(contact.formattedDeviceID)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .monospaced()
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        let contact = messageService.contacts[index]
                        messageService.removeContact(deviceID: contact.deviceID)
                    }
                }
            }
            .navigationTitle("Contacts")
            .navigationDestination(item: $navigateToConversation) { conversation in
                ConversationDetailView(conversation: conversation)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddContact = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .overlay {
                if messageService.contacts.isEmpty {
                    ContentUnavailableView(
                        "No Contacts",
                        systemImage: "person.crop.circle",
                        description: Text("Add contacts with their Alfie device ID.")
                    )
                }
            }
            .sheet(isPresented: $showingAddContact) {
                AddContactView()
            }
        }
    }
}

// MARK: - Add Contact Sheet

struct AddContactView: View {
    @Environment(MessageService.self) private var messageService
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var deviceIDString = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Contact Info") {
                    TextField("Name", text: $name)
                    TextField("Device ID (decimal or 0x hex)", text: $deviceIDString)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Add Contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveContact() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || deviceIDString.isEmpty)
                }
            }
        }
    }

    private func saveContact() {
        let trimmed = deviceIDString.trimmingCharacters(in: .whitespaces)
        let deviceID: UInt32?

        if trimmed.hasPrefix("0x") || trimmed.hasPrefix("0X") {
            deviceID = UInt32(trimmed.dropFirst(2), radix: 16)
        } else {
            deviceID = UInt32(trimmed)
        }

        guard let id = deviceID else {
            errorMessage = "Invalid device ID. Enter a decimal number or hex value (e.g., 0x0001A3F4)."
            return
        }

        messageService.addContact(deviceID: id, name: name.trimmingCharacters(in: .whitespaces))
        dismiss()
    }
}

#Preview {
    ContactsView()
        .environment(MessageService())
}
