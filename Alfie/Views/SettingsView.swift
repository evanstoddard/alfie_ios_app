//
//  SettingsView.swift
//  Alfie
//
//  Created by Evan Robert Stoddard on 2/18/26.
//

import SwiftUI

struct SettingsView: View {
    @Environment(BLEManager.self) private var bleManager
    @Environment(MessageService.self) private var messageService

    var body: some View {
        NavigationStack {
            List {
                Section("Device") {
                    if let device = bleManager.connectedDevice {
                        HStack {
                            Text("Status")
                            Spacer()
                            Text("Connected")
                                .foregroundStyle(.green)
                        }

                        HStack {
                            Text("Device Name")
                            Spacer()
                            Text(device.name)
                                .foregroundStyle(.secondary)
                        }

                        if let deviceID = bleManager.transport?.deviceID {
                            HStack {
                                Text("Device ID")
                                Spacer()
                                Text(String(format: "0x%08X", deviceID))
                                    .foregroundStyle(.secondary)
                                    .monospaced()
                            }
                        }

                        Button("Disconnect", role: .destructive) {
                            bleManager.disconnect()
                            messageService.didDisconnect()
                        }
                    } else {
                        HStack {
                            Text("Status")
                            Spacer()
                            if bleManager.isConnecting {
                                ProgressView()
                                    .padding(.trailing, 4)
                                Text("Connecting...")
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Not Connected")
                                    .foregroundStyle(.secondary)
                            }
                        }

                        NavigationLink("Scan for Devices") {
                            DeviceScannerView()
                        }
                        .disabled(!bleManager.isBluetoothAvailable || bleManager.isConnecting)
                    }
                }

                if !bleManager.isBluetoothAvailable {
                    Section {
                        Label("Bluetooth is not available. Please enable Bluetooth in Settings.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView()
        .environment(BLEManager())
        .environment(MessageService())
}
