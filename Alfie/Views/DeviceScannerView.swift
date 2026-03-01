//
//  DeviceScannerView.swift
//  Alfie
//

import SwiftUI

struct DeviceScannerView: View {
    @Environment(BLEManager.self) private var bleManager
    @Environment(MessageService.self) private var messageService
    @Environment(\.dismiss) private var dismiss

    @State private var connectionError: String?

    var body: some View {
        List {
            if bleManager.isScanning {
                Section {
                    HStack {
                        ProgressView()
                            .padding(.trailing, 8)
                        Text("Scanning for Alfie devices...")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Discovered Devices") {
                if bleManager.discoveredDevices.isEmpty {
                    Text("No devices found")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(bleManager.discoveredDevices) { device in
                        Button {
                            connectToDevice(device)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(device.name)
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                    Text(device.id.uuidString)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .monospaced()
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                Spacer()
                                Text("\(device.rssi) dBm")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .disabled(bleManager.isConnecting)
                    }
                }
            }

            if let error = connectionError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Scan")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            bleManager.startScan()
        }
        .onDisappear {
            bleManager.stopScan()
        }
    }

    private func connectToDevice(_ device: DiscoveredDevice) {
        connectionError = nil
        Task {
            do {
                try await bleManager.connect(to: device)
                if let transport = bleManager.transport,
                   let deviceID = transport.deviceID {
                    let alfie = AlfieTransport(bleTransport: transport, localDeviceID: deviceID)
                    messageService.didConnect(transport: alfie, deviceID: deviceID)
                }
                dismiss()
            } catch {
                connectionError = "Connection failed: \(error.localizedDescription)"
            }
        }
    }
}

#Preview {
    NavigationStack {
        DeviceScannerView()
            .environment(BLEManager())
            .environment(MessageService())
    }
}
