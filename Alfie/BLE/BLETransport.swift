//
//  BLETransport.swift
//  Alfie
//

import CoreBluetooth
import Foundation
import os

private let logger = Logger(subsystem: "com.alfie", category: "BLETransport")

@Observable
final class BLETransport: NSObject, @unchecked Sendable {
    // MARK: - Public State

    private(set) var deviceID: UInt32?
    private(set) var isReady = false

    @ObservationIgnored
    var onPayloadReceived: (@Sendable (Data) -> Void)?

    // MARK: - Private

    private let peripheral: CBPeripheral
    private var dataCharacteristic: CBCharacteristic?
    private var deviceIDCharacteristic: CBCharacteristic?

    private var nextSeqID: UInt16 = 0
    private var maxFragmentPayload: Int = BLEConstants.maxFragmentPayload

    // Sending: pending ACK continuations keyed by (seqID, fragIndex)
    private var pendingACKs: [UInt32: CheckedContinuation<Void, any Error>] = [:]

    // Receiving: reassembly buffers keyed by seqID
    private var reassemblyBuffers: [UInt16: ReassemblyBuffer] = [:]

    // Service discovery
    private var discoveryCompletion: CheckedContinuation<Void, any Error>?
    private var pendingServiceDiscoveryCount = 0

    // Device ID read continuation
    private var deviceIDCompletion: CheckedContinuation<UInt32, any Error>?

    private struct ReassemblyBuffer {
        let totalSize: Int
        let fragTotal: Int
        var fragments: [UInt8: Data]

        var isComplete: Bool { fragments.count == fragTotal }

        func assemble() -> Data? {
            guard isComplete else { return nil }
            var result = Data(capacity: totalSize)
            for i in 0..<UInt8(fragTotal) {
                guard let frag = fragments[i] else { return nil }
                result.append(frag)
            }
            return result
        }
    }

    // MARK: - Init

    init(peripheral: CBPeripheral) {
        self.peripheral = peripheral
        super.init()
        self.peripheral.delegate = self
    }

    // MARK: - Setup

    func discoverAndSubscribe() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            discoveryCompletion = continuation
            peripheral.discoverServices(nil) // discover all services
        }

        // Adapt fragment size to peripheral's actual MTU
        let writeLen = peripheral.maximumWriteValueLength(for: .withResponse)
        if writeLen > DataFrame.headerSize {
            maxFragmentPayload = writeLen - DataFrame.headerSize
        }

        // Read device ID if control service was found
        if deviceIDCharacteristic != nil {
            let id = try await readDeviceID()
            deviceID = id
            logger.info("BLETransport ready, deviceID=\(id)")
        } else {
            logger.info("BLETransport ready (no control service, deviceID unknown)")
        }

        isReady = true
    }

    private func readDeviceID() async throws -> UInt32 {
        guard let char = deviceIDCharacteristic else {
            throw BLETransportError.characteristicNotFound
        }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UInt32, any Error>) in
            deviceIDCompletion = continuation
            peripheral.readValue(for: char)
        }
    }

    // MARK: - Send

    func send(data: Data) async throws {
        guard let char = dataCharacteristic else {
            throw BLETransportError.notReady
        }

        let seqID = nextSeqID
        nextSeqID &+= 1

        let fragments = fragment(data: data, seqID: seqID)

        for frame in fragments {
            try await sendFragmentWithRetry(frame: frame, characteristic: char)
        }
    }

    private func fragment(data: Data, seqID: UInt16) -> [DataFrame] {
        let totalSize = UInt16(data.count)
        let fragSize = maxFragmentPayload
        let fragCount = max(1, (data.count + fragSize - 1) / fragSize)
        var frames: [DataFrame] = []

        for i in 0..<fragCount {
            let start = i * fragSize
            let end = min(start + fragSize, data.count)
            let payload = data[start..<end]
            let frame = DataFrame(
                version: BLEConstants.protocolVersion,
                seqID: seqID,
                totalSize: totalSize,
                fragIndex: UInt8(i),
                fragTotal: UInt8(fragCount),
                payload: Data(payload)
            )
            frames.append(frame)
        }
        return frames
    }

    private func sendFragmentWithRetry(frame: DataFrame, characteristic: CBCharacteristic) async throws {
        let frameData = frame.serialize()
        let ackKey = Self.ackKey(seqID: frame.seqID, fragIndex: frame.fragIndex)

        for attempt in 0...BLEConstants.maxRetries {
            if attempt > 0 {
                logger.debug("Retry \(attempt) for seq=\(frame.seqID) frag=\(frame.fragIndex)")
            }

            peripheral.writeValue(frameData, for: characteristic, type: .withResponse)

            do {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask { @MainActor in
                        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                            self.pendingACKs[ackKey] = continuation
                        }
                    }
                    group.addTask {
                        try await Task.sleep(for: .seconds(BLEConstants.ackTimeoutSeconds))
                        throw BLETransportError.ackTimeout
                    }
                    // Wait for whichever finishes first
                    try await group.next()
                    group.cancelAll()
                }
                return // ACK received
            } catch is CancellationError {
                pendingACKs.removeValue(forKey: ackKey)
                throw CancellationError()
            } catch let error as BLETransportError where error == .ackTimeout {
                pendingACKs.removeValue(forKey: ackKey)
                if attempt == BLEConstants.maxRetries {
                    throw BLETransportError.maxRetriesExceeded
                }
                continue
            } catch {
                pendingACKs.removeValue(forKey: ackKey)
                throw error
            }
        }
    }

    // MARK: - Receive

    private func handleNotification(data: Data) {
        guard data.count >= 2 else {
            logger.warning("Notification too short: \(data.count) bytes")
            return
        }
        let frameType = data[data.startIndex + 1]
        logger.debug("handleNotification: frameType=\(frameType), \(data.count) bytes")

        switch frameType {
        case BLEConstants.frameTypeACK:
            handleACK(data: data)
        case BLEConstants.frameTypeData:
            handleDataFrame(data: data)
        default:
            logger.warning("Unknown frame type: \(frameType)")
        }
    }

    private func handleACK(data: Data) {
        guard let ack = ACKFrame.deserialize(from: data) else { return }
        let key = Self.ackKey(seqID: ack.seqID, fragIndex: ack.fragIndex)
        if let continuation = pendingACKs.removeValue(forKey: key) {
            continuation.resume()
        }
    }

    private func handleDataFrame(data: Data) {
        guard let frame = DataFrame.deserialize(from: data) else {
            logger.warning("Failed to deserialize DataFrame from \(data.count) bytes")
            return
        }

        logger.debug("DataFrame: seq=\(frame.seqID) frag=\(frame.fragIndex)/\(frame.fragTotal) payload=\(frame.payload.count) bytes")

        // Send ACK back
        sendACK(seqID: frame.seqID, fragIndex: frame.fragIndex)

        // Single fragment message
        if frame.fragTotal == 1 {
            logger.debug("Single fragment, delivering \(frame.payload.count) bytes, callback=\(self.onPayloadReceived != nil)")
            onPayloadReceived?(frame.payload)
            return
        }

        // Multi-fragment reassembly
        var buffer = reassemblyBuffers[frame.seqID] ?? ReassemblyBuffer(
            totalSize: Int(frame.totalSize),
            fragTotal: Int(frame.fragTotal),
            fragments: [:]
        )
        buffer.fragments[frame.fragIndex] = frame.payload
        reassemblyBuffers[frame.seqID] = buffer

        if buffer.isComplete, let assembled = buffer.assemble() {
            reassemblyBuffers.removeValue(forKey: frame.seqID)
            onPayloadReceived?(assembled)
        }
    }

    private func sendACK(seqID: UInt16, fragIndex: UInt8) {
        guard let char = dataCharacteristic else { return }
        let ack = ACKFrame(version: BLEConstants.protocolVersion, seqID: seqID, fragIndex: fragIndex)
        peripheral.writeValue(ack.serialize(), for: char, type: .withResponse)
    }

    // MARK: - Helpers

    private static func ackKey(seqID: UInt16, fragIndex: UInt8) -> UInt32 {
        UInt32(seqID) << 8 | UInt32(fragIndex)
    }
}

// MARK: - CBPeripheralDelegate

extension BLETransport: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        MainActor.assumeIsolated {
            if let error {
                discoveryCompletion?.resume(throwing: error)
                discoveryCompletion = nil
                return
            }

            guard let services = peripheral.services, !services.isEmpty else {
                discoveryCompletion?.resume(throwing: BLETransportError.serviceNotFound)
                discoveryCompletion = nil
                return
            }

            logger.info("Discovered \(services.count) services:")
            for service in services {
                logger.info("  Service: \(service.uuid.uuidString)")
            }

            pendingServiceDiscoveryCount = 0
            for service in services {
                if service.uuid == BLEConstants.alfieServiceUUID {
                    pendingServiceDiscoveryCount += 1
                    peripheral.discoverCharacteristics(nil, for: service)
                } else if service.uuid == BLEConstants.controlServiceUUID {
                    pendingServiceDiscoveryCount += 1
                    peripheral.discoverCharacteristics(nil, for: service)
                }
            }

            if pendingServiceDiscoveryCount == 0 {
                let uuids = services.map { $0.uuid.uuidString }.joined(separator: ", ")
                logger.error("No Alfie or Control service found. Available: \(uuids)")
                discoveryCompletion?.resume(throwing: BLETransportError.serviceNotFound)
                discoveryCompletion = nil
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: (any Error)?) {
        MainActor.assumeIsolated {
            if let error {
                logger.error("Characteristic discovery error for \(service.uuid): \(error)")
            }

            logger.info("Characteristics for \(service.uuid.uuidString):")
            for characteristic in service.characteristics ?? [] {
                logger.info("  Char: \(characteristic.uuid.uuidString) props: \(characteristic.properties.rawValue)")
                if characteristic.uuid == BLEConstants.alfieDataCharacteristicUUID {
                    dataCharacteristic = characteristic
                    peripheral.setNotifyValue(true, for: characteristic)
                } else if characteristic.uuid == BLEConstants.deviceIDCharacteristicUUID {
                    deviceIDCharacteristic = characteristic
                }
            }

            pendingServiceDiscoveryCount -= 1

            if pendingServiceDiscoveryCount <= 0 {
                if dataCharacteristic != nil {
                    discoveryCompletion?.resume()
                    discoveryCompletion = nil
                } else {
                    logger.error("Alfie data characteristic not found")
                    discoveryCompletion?.resume(throwing: BLETransportError.characteristicNotFound)
                    discoveryCompletion = nil
                }
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        MainActor.assumeIsolated {
            logger.debug("didUpdateValueFor: \(characteristic.uuid.uuidString), \(characteristic.value?.count ?? 0) bytes")

            if characteristic.uuid == BLEConstants.deviceIDCharacteristicUUID {
                if let error {
                    deviceIDCompletion?.resume(throwing: error)
                    deviceIDCompletion = nil
                    return
                }
                guard let data = characteristic.value, data.count >= 4 else {
                    deviceIDCompletion?.resume(throwing: BLETransportError.invalidDeviceID)
                    deviceIDCompletion = nil
                    return
                }
                let id: UInt32 = data.readLittleEndian(at: 0)
                deviceIDCompletion?.resume(returning: id)
                deviceIDCompletion = nil
                return
            }

            if characteristic.uuid == BLEConstants.alfieDataCharacteristicUUID {
                guard let data = characteristic.value else { return }
                handleNotification(data: data)
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: (any Error)?) {
        MainActor.assumeIsolated {
            if let error {
                logger.error("Notification subscription failed for \(characteristic.uuid): \(error)")
                return
            }
            logger.info("Notification subscription active for \(characteristic.uuid): isNotifying=\(characteristic.isNotifying)")
        }
    }
}

// MARK: - Errors

enum BLETransportError: Error, Equatable {
    case notReady
    case serviceNotFound
    case characteristicNotFound
    case invalidDeviceID
    case ackTimeout
    case maxRetriesExceeded
}
