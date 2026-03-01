//
//  AlfieFrame.swift
//  Alfie
//

import Foundation

// MARK: - Alfie Header (10 bytes)

struct AlfieHeader: Sendable {
    let version: UInt8
    let endpointID: UInt8
    let sourceID: UInt32
    let destinationID: UInt32

    static let size = 10

    init(version: UInt8 = BLEConstants.protocolVersion, endpointID: UInt8 = 0, sourceID: UInt32, destinationID: UInt32) {
        self.version = version
        self.endpointID = endpointID
        self.sourceID = sourceID
        self.destinationID = destinationID
    }

    func serialize() -> Data {
        var data = Data(capacity: Self.size)
        data.append(version)
        data.append(endpointID)
        data.appendLittleEndian(sourceID)
        data.appendLittleEndian(destinationID)
        return data
    }

    static func deserialize(from data: Data) -> AlfieHeader? {
        guard data.count >= size else { return nil }
        let version = data[data.startIndex]
        let endpointID = data[data.startIndex + 1]
        let sourceID: UInt32 = data.readLittleEndian(at: data.startIndex + 2)
        let destinationID: UInt32 = data.readLittleEndian(at: data.startIndex + 6)
        return AlfieHeader(version: version, endpointID: endpointID, sourceID: sourceID, destinationID: destinationID)
    }
}

// MARK: - Text Message Frame

struct TextMessageFrame: Sendable {
    let header: AlfieHeader
    let messageUUID: UUID
    let text: String

    /// Maximum UTF-8 text bytes: 512 - 10 (header) - 1 (frame_type) - 16 (uuid) - 1 (null) = 484
    static let maxTextBytes = BLEConstants.maxMessagePayload - AlfieHeader.size - 1 - BLEConstants.uuidSize - 1

    func serialize() -> Data? {
        guard let textData = text.data(using: .utf8),
              textData.count <= Self.maxTextBytes else { return nil }

        var data = Data(capacity: AlfieHeader.size + 1 + BLEConstants.uuidSize + textData.count + 1)
        data.append(header.serialize())
        data.append(BLEConstants.messageFrameTypeText)
        data.append(messageUUID.dataRepresentation)
        data.append(textData)
        data.append(0x00) // null terminator
        return data
    }

    static func deserialize(from data: Data) -> TextMessageFrame? {
        let minSize = AlfieHeader.size + 1 + BLEConstants.uuidSize + 1 // header + type + uuid + null
        guard data.count >= minSize else { return nil }

        guard let header = AlfieHeader.deserialize(from: data) else { return nil }

        let frameType = data[data.startIndex + AlfieHeader.size]
        guard frameType == BLEConstants.messageFrameTypeText else { return nil }

        let uuidStart = data.startIndex + AlfieHeader.size + 1
        let uuidData = data[uuidStart..<(uuidStart + BLEConstants.uuidSize)]
        let messageUUID = UUID(dataRepresentation: uuidData)

        let textStart = uuidStart + BLEConstants.uuidSize
        var textEnd = textStart
        while textEnd < data.endIndex && data[textEnd] != 0x00 {
            textEnd += 1
        }

        let textData = data[textStart..<textEnd]
        guard let text = String(data: textData, encoding: .utf8) else { return nil }

        return TextMessageFrame(header: header, messageUUID: messageUUID, text: text)
    }
}

// MARK: - BLE Data Frames

struct DataFrame: Sendable {
    let version: UInt8
    let seqID: UInt16
    let totalSize: UInt16
    let fragIndex: UInt8
    let fragTotal: UInt8
    let payload: Data

    static let headerSize = BLEConstants.dataFrameHeaderSize

    func serialize() -> Data {
        var data = Data(capacity: Self.headerSize + payload.count)
        data.append(version)
        data.append(BLEConstants.frameTypeData)
        data.appendLittleEndian(seqID)
        data.appendLittleEndian(totalSize)
        data.append(fragIndex)
        data.append(fragTotal)
        data.append(payload)
        return data
    }

    static func deserialize(from data: Data) -> DataFrame? {
        guard data.count >= headerSize else { return nil }
        let base = data.startIndex
        let version = data[base]
        let frameType = data[base + 1]
        guard frameType == BLEConstants.frameTypeData else { return nil }
        let seqID: UInt16 = data.readLittleEndian(at: base + 2)
        let totalSize: UInt16 = data.readLittleEndian(at: base + 4)
        let fragIndex = data[base + 6]
        let fragTotal = data[base + 7]
        let payload = data[(base + headerSize)...]
        return DataFrame(version: version, seqID: seqID, totalSize: totalSize, fragIndex: fragIndex, fragTotal: fragTotal, payload: Data(payload))
    }
}

struct ACKFrame: Sendable {
    let version: UInt8
    let seqID: UInt16
    let fragIndex: UInt8

    func serialize() -> Data {
        var data = Data(capacity: BLEConstants.ackFrameSize)
        data.append(version)
        data.append(BLEConstants.frameTypeACK)
        data.appendLittleEndian(seqID)
        data.append(fragIndex)
        return data
    }

    static func deserialize(from data: Data) -> ACKFrame? {
        guard data.count >= BLEConstants.ackFrameSize else { return nil }
        let base = data.startIndex
        let version = data[base]
        let frameType = data[base + 1]
        guard frameType == BLEConstants.frameTypeACK else { return nil }
        let seqID: UInt16 = data.readLittleEndian(at: base + 2)
        let fragIndex = data[base + 4]
        return ACKFrame(version: version, seqID: seqID, fragIndex: fragIndex)
    }
}

// MARK: - Data Helpers

extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    func readLittleEndian<T: FixedWidthInteger>(at offset: Int) -> T {
        let size = MemoryLayout<T>.size
        guard offset + size <= count else { return 0 }
        return subdata(in: offset..<(offset + size)).withUnsafeBytes { $0.loadUnaligned(as: T.self) }.littleEndian
    }
}

extension UUID {
    var dataRepresentation: Data {
        withUnsafeBytes(of: uuid) { Data($0) }
    }

    init(dataRepresentation data: Data) {
        var uuid: uuid_t = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
        _ = withUnsafeMutableBytes(of: &uuid) { dest in
            data.copyBytes(to: dest)
        }
        self.init(uuid: uuid)
    }
}
