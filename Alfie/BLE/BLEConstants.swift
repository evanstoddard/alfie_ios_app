//
//  BLEConstants.swift
//  Alfie
//

import CoreBluetooth

enum BLEConstants {
    // MARK: - Alfie Service
    static let alfieServiceUUID = CBUUID(string: "C1534FA3-5211-4E32-A176-D1AF04513305")
    static let alfieDataCharacteristicUUID = CBUUID(string: "C1534FA4-5211-4E32-A176-D1AF04513305")

    // MARK: - Control Service
    static let controlServiceUUID = CBUUID(string: "7928884E-01E6-4137-86D3-ADEFD8AFE21D")
    static let deviceIDCharacteristicUUID = CBUUID(string: "7928884F-01E6-4137-86D3-ADEFD8AFE21D")

    // MARK: - Frame Constants
    static let protocolVersion: UInt8 = 0x01
    static let frameTypeData: UInt8 = 0x00
    static let frameTypeACK: UInt8 = 0x01
    static let dataFrameHeaderSize = 8
    static let ackFrameSize = 5

    // MARK: - Alfie Message Constants
    static let alfieHeaderSize = 10
    static let messageFrameTypeText: UInt8 = 0x00
    static let maxMessagePayload = 512
    static let uuidSize = 16

    // MARK: - MTU / Fragmentation
    static let defaultMTU = 251
    static let maxFragmentPayload = 243  // defaultMTU - dataFrameHeaderSize

    // MARK: - Reliability
    static let ackTimeoutSeconds: TimeInterval = 2.5
    static let maxRetries = 4
}
