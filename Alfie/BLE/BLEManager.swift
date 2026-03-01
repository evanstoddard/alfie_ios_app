//
//  BLEManager.swift
//  Alfie
//

import CoreBluetooth
import Foundation
import os

private let logger = Logger(subsystem: "com.alfie", category: "BLEManager")

struct DiscoveredDevice: Identifiable, Sendable {
    let id: UUID  // CBPeripheral identifier
    let name: String
    let peripheral: CBPeripheral
    var rssi: Int
}

@Observable
final class BLEManager: NSObject, @unchecked Sendable {
    // MARK: - Public State

    private(set) var isBluetoothAvailable = false
    private(set) var isScanning = false
    private(set) var discoveredDevices: [DiscoveredDevice] = []

    private(set) var connectedDevice: DiscoveredDevice?
    private(set) var transport: BLETransport?
    private(set) var isConnecting = false

    // MARK: - Private

    private var centralManager: CBCentralManager!
    private var connectContinuation: CheckedContinuation<CBPeripheral, any Error>?
    private var poweredOnContinuation: CheckedContinuation<Void, Never>?

    // MARK: - Init

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: - Scanning

    func startScan() {
        guard isBluetoothAvailable, !isScanning else { return }
        discoveredDevices = []
        isScanning = true
        centralManager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        logger.info("Started scanning for Alfie devices")
    }

    func stopScan() {
        guard isScanning else { return }
        centralManager.stopScan()
        isScanning = false
        logger.info("Stopped scanning")
    }

    // MARK: - Connect / Disconnect

    func connect(to device: DiscoveredDevice) async throws {
        stopScan()
        isConnecting = true

        do {
            let peripheral = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CBPeripheral, any Error>) in
                connectContinuation = continuation
                centralManager.connect(device.peripheral, options: nil)
            }

            let bleTransport = BLETransport(peripheral: peripheral)
            try await bleTransport.discoverAndSubscribe()

            transport = bleTransport
            connectedDevice = device
            isConnecting = false
            logger.info("Connected to \(device.name), deviceID=\(bleTransport.deviceID ?? 0)")
        } catch {
            isConnecting = false
            throw error
        }
    }

    func disconnect() {
        if let peripheral = connectedDevice?.peripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        cleanupConnection()
    }

    private func cleanupConnection() {
        transport = nil
        connectedDevice = nil
        isConnecting = false
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated {
            let available = central.state == .poweredOn
            isBluetoothAvailable = available
            logger.info("Bluetooth state: \(String(describing: central.state.rawValue)), available=\(available)")

            if let continuation = poweredOnContinuation {
                poweredOnContinuation = nil
                continuation.resume()
            }

            if !available {
                stopScan()
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        MainActor.assumeIsolated {
            let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? "Unknown Device"
            let rssi = RSSI.intValue

            guard name.localizedCaseInsensitiveContains("Alfie") else { return }

            if let idx = discoveredDevices.firstIndex(where: { $0.id == peripheral.identifier }) {
                discoveredDevices[idx].rssi = rssi
            } else {
                let device = DiscoveredDevice(id: peripheral.identifier, name: name, peripheral: peripheral, rssi: rssi)
                discoveredDevices.append(device)
                logger.info("Discovered: \(name) (\(peripheral.identifier))")
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated {
            logger.info("Peripheral connected: \(peripheral.identifier)")
            connectContinuation?.resume(returning: peripheral)
            connectContinuation = nil
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: (any Error)?) {
        MainActor.assumeIsolated {
            let err = error ?? BLEManagerError.connectionFailed
            logger.error("Failed to connect: \(String(describing: err))")
            connectContinuation?.resume(throwing: err)
            connectContinuation = nil
            isConnecting = false
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: (any Error)?) {
        MainActor.assumeIsolated {
            logger.info("Peripheral disconnected: \(peripheral.identifier)")
            cleanupConnection()
        }
    }
}

enum BLEManagerError: Error {
    case connectionFailed
    case bluetoothNotAvailable
}
