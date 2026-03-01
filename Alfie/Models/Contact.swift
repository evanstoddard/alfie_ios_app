//
//  Contact.swift
//  Alfie
//

import Foundation

struct Contact: Identifiable, Hashable, Codable, Sendable {
    var id: UInt32 { deviceID }
    let deviceID: UInt32
    var name: String

    var formattedDeviceID: String {
        String(format: "0x%08X", deviceID)
    }

    static func defaultName(for deviceID: UInt32) -> String {
        "Alfie-\(deviceID)"
    }
}
