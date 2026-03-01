//
//  AlfieTransport.swift
//  Alfie
//

import Foundation
import os

private let logger = Logger(subsystem: "com.alfie", category: "AlfieTransport")

@Observable
final class AlfieTransport: @unchecked Sendable {
    private let bleTransport: BLETransport
    let localDeviceID: UInt32

    @ObservationIgnored
    var onMessageReceived: ((TextMessageFrame) -> Void)?

    init(bleTransport: BLETransport, localDeviceID: UInt32) {
        self.bleTransport = bleTransport
        self.localDeviceID = localDeviceID

        bleTransport.onPayloadReceived = { @Sendable [weak self] data in
            guard let self else { return }
            Task { @MainActor in
                self.handlePayload(data)
            }
        }
    }

    func sendTextMessage(to destinationID: UInt32, text: String, messageID: UUID = UUID()) async throws {
        let header = AlfieHeader(sourceID: localDeviceID, destinationID: destinationID)
        let frame = TextMessageFrame(header: header, messageUUID: messageID, text: text)

        guard let data = frame.serialize() else {
            throw AlfieTransportError.serializationFailed
        }

        try await bleTransport.send(data: data)
        logger.info("Sent message \(messageID) to \(destinationID)")
    }

    private func handlePayload(_ data: Data) {
        guard let frame = TextMessageFrame.deserialize(from: data) else {
            logger.warning("Failed to deserialize incoming payload (\(data.count) bytes)")
            return
        }
        logger.info("Received message \(frame.messageUUID) from \(frame.header.sourceID)")
        onMessageReceived?(frame)
    }
}

enum AlfieTransportError: Error {
    case serializationFailed
}
