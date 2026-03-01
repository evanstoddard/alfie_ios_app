//
//  StoredMessage.swift
//  Alfie
//

import Foundation

struct StoredMessage: Identifiable, Codable, Sendable {
    let id: UUID
    let conversationDeviceID: UInt32
    let senderDeviceID: UInt32
    let text: String
    let timestamp: Date
    let isOutgoing: Bool
    var status: MessageStatus

    enum MessageStatus: String, Codable, Sendable {
        case sending
        case sent
        case failed
    }
}
