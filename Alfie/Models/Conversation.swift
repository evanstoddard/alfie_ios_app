//
//  Conversation.swift
//  Alfie
//

import Foundation

struct Conversation: Identifiable, Hashable, Codable, Sendable {
    var id: UInt32 { deviceID }
    let deviceID: UInt32
    var lastMessageText: String
    var lastMessageDate: Date
    var unreadCount: Int
    var displayName: String

    var formattedDeviceID: String {
        String(format: "0x%08X", deviceID)
    }
}
