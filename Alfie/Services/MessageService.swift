//
//  MessageService.swift
//  Alfie
//

import Foundation
import os

private let logger = Logger(subsystem: "com.alfie", category: "MessageService")

@Observable
final class MessageService: @unchecked Sendable {
    // MARK: - Public State

    private(set) var conversations: [Conversation] = []
    private(set) var contacts: [Contact] = []
    private(set) var messagesByConversation: [UInt32: [StoredMessage]] = [:]

    private(set) var localDeviceID: UInt32?

    // MARK: - Private

    private var alfieTransport: AlfieTransport?

    private let documentsURL: URL = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }()

    // MARK: - Init

    init() {
        loadAll()
    }

    // MARK: - BLE Lifecycle

    func didConnect(transport: AlfieTransport, deviceID: UInt32) {
        alfieTransport = transport
        localDeviceID = deviceID

        transport.onMessageReceived = { [weak self] frame in
            self?.handleIncomingMessage(frame: frame)
        }

        logger.info("MessageService connected, localDeviceID=\(deviceID)")
    }

    func didDisconnect() {
        alfieTransport = nil
        localDeviceID = nil
        logger.info("MessageService disconnected")
    }

    // MARK: - Send Message

    func sendMessage(to deviceID: UInt32, text: String) async {
        let messageID = UUID()
        let message = StoredMessage(
            id: messageID,
            conversationDeviceID: deviceID,
            senderDeviceID: localDeviceID ?? 0,
            text: text,
            timestamp: Date(),
            isOutgoing: true,
            status: .sending
        )

        appendMessage(message, for: deviceID)
        updateConversation(for: deviceID, text: text, date: message.timestamp)

        guard let transport = alfieTransport else {
            updateMessageStatus(id: messageID, deviceID: deviceID, status: .failed)
            return
        }

        do {
            try await transport.sendTextMessage(to: deviceID, text: text, messageID: messageID)
            updateMessageStatus(id: messageID, deviceID: deviceID, status: .sent)
        } catch {
            logger.error("Failed to send message: \(error)")
            updateMessageStatus(id: messageID, deviceID: deviceID, status: .failed)
        }
    }

    // MARK: - Incoming Messages

    private func handleIncomingMessage(frame: TextMessageFrame) {
        let senderID = frame.header.sourceID

        let message = StoredMessage(
            id: frame.messageUUID,
            conversationDeviceID: senderID,
            senderDeviceID: senderID,
            text: frame.text,
            timestamp: Date(),
            isOutgoing: false,
            status: .sent
        )

        appendMessage(message, for: senderID)
        updateConversation(for: senderID, text: frame.text, date: message.timestamp, incrementUnread: true)
    }

    func ensureConversation(for deviceID: UInt32) {
        guard !conversations.contains(where: { $0.deviceID == deviceID }) else { return }
        let conv = Conversation(
            deviceID: deviceID,
            lastMessageText: "",
            lastMessageDate: Date(),
            unreadCount: 0,
            displayName: displayName(for: deviceID)
        )
        conversations.insert(conv, at: 0)
        saveConversations()
    }

    func deleteConversation(deviceID: UInt32) {
        conversations.removeAll { $0.deviceID == deviceID }
        messagesByConversation.removeValue(forKey: deviceID)
        saveConversations()
        let url = documentsURL.appendingPathComponent("messages_\(deviceID).json")
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Conversation / Message Management

    private func appendMessage(_ message: StoredMessage, for deviceID: UInt32) {
        var messages = messagesByConversation[deviceID] ?? []
        messages.append(message)
        messagesByConversation[deviceID] = messages
        saveMessages(for: deviceID)
    }

    private func updateMessageStatus(id: UUID, deviceID: UInt32, status: StoredMessage.MessageStatus) {
        guard var messages = messagesByConversation[deviceID],
              let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[idx].status = status
        messagesByConversation[deviceID] = messages
        saveMessages(for: deviceID)
    }

    private func updateConversation(for deviceID: UInt32, text: String, date: Date, incrementUnread: Bool = false) {
        if let idx = conversations.firstIndex(where: { $0.deviceID == deviceID }) {
            var conv = conversations[idx]
            conv.lastMessageText = text
            conv.lastMessageDate = date
            if incrementUnread {
                conv.unreadCount += 1
            }
            conversations[idx] = conv
        } else {
            let conv = Conversation(
                deviceID: deviceID,
                lastMessageText: text,
                lastMessageDate: date,
                unreadCount: incrementUnread ? 1 : 0,
                displayName: displayName(for: deviceID)
            )
            conversations.append(conv)
        }
        conversations.sort { $0.lastMessageDate > $1.lastMessageDate }
        saveConversations()
    }

    func markConversationRead(deviceID: UInt32) {
        guard let idx = conversations.firstIndex(where: { $0.deviceID == deviceID }) else { return }
        var conv = conversations[idx]
        conv.unreadCount = 0
        conversations[idx] = conv
        saveConversations()
    }

    // MARK: - Contacts

    func addContact(deviceID: UInt32, name: String) {
        guard !contacts.contains(where: { $0.deviceID == deviceID }) else { return }
        let contact = Contact(deviceID: deviceID, name: name)
        contacts.append(contact)
        contacts.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        if let idx = conversations.firstIndex(where: { $0.deviceID == deviceID }) {
            conversations[idx].displayName = name
        }

        saveContacts()
        saveConversations()
    }

    func removeContact(deviceID: UInt32) {
        contacts.removeAll { $0.deviceID == deviceID }

        if let idx = conversations.firstIndex(where: { $0.deviceID == deviceID }) {
            conversations[idx].displayName = Contact.defaultName(for: deviceID)
        }

        saveContacts()
        saveConversations()
    }

    func displayName(for deviceID: UInt32) -> String {
        contacts.first(where: { $0.deviceID == deviceID })?.name ?? Contact.defaultName(for: deviceID)
    }

    // MARK: - Persistence

    private func saveConversations() {
        save(conversations, to: "conversations.json")
    }

    private func saveContacts() {
        save(contacts, to: "contacts.json")
    }

    private func saveMessages(for deviceID: UInt32) {
        let messages = messagesByConversation[deviceID] ?? []
        save(messages, to: "messages_\(deviceID).json")
    }

    private func loadAll() {
        conversations = load([Conversation].self, from: "conversations.json") ?? []
        contacts = load([Contact].self, from: "contacts.json") ?? []

        for conv in conversations {
            let messages = load([StoredMessage].self, from: "messages_\(conv.deviceID).json") ?? []
            messagesByConversation[conv.deviceID] = messages
        }
    }

    private func save<T: Encodable>(_ value: T, to filename: String) {
        let url = documentsURL.appendingPathComponent(filename)
        do {
            let data = try JSONEncoder().encode(value)
            try data.write(to: url, options: .atomic)
        } catch {
            logger.error("Failed to save \(filename): \(error)")
        }
    }

    private func load<T: Decodable>(_ type: T.Type, from filename: String) -> T? {
        let url = documentsURL.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
