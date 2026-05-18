//
//  XiaomiBleProbeView.swift
//  Test
//
//  Created by 原鸣清 on 2026/1/20.
//

import SwiftUI

struct XiaomiBleProbeView: View {
    @StateObject private var vm = XiaomiBleProbeViewModel()

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Xiaomi BLE Probe")
                    .font(.headline)
                Spacer()
                Text(vm.btStateText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button(vm.isScanning ? "Scanning..." : "Start Scan") {
                    vm.startScan()
                }
                .buttonStyle(.borderedProminent)
                .disabled(vm.isScanning == true || !vm.isBluetoothReady)

                Button("Stop") { vm.stopAll() }
                    .buttonStyle(.bordered)

                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Target: \(vm.targetName ?? "-")")
                Text("Connected: \(vm.connectedName ?? "-")")
            }
            .font(.system(size: 14))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.white.opacity(0.06))
            .cornerRadius(12)

            HStack(spacing: 10) {
                Button("Discover + Probe") {
                    vm.discoverAndProbe()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!vm.isConnected)

                Toggle("Probe Write", isOn: $vm.probeWriteEnabled)
                    .toggleStyle(.switch)
                    .disabled(!vm.isConnected)
            }

            Divider().opacity(0.3)
            
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Button("Manual Discover") { vm.manualDiscoverServices() }
                        .buttonStyle(.bordered)
                        .disabled(!vm.isConnected)

                    Button("Dump Chars") { vm.manualDumpChars() }
                        .buttonStyle(.bordered)
                        .disabled(!vm.isConnected)
                }

                HStack(spacing: 10) {
                    Button("Read 0050") { vm.manualRead("0050") }
                        .buttonStyle(.bordered)
                        .disabled(!vm.isConnected)

                    Button("Notify 005E") { vm.manualNotify("005E", on: true) }
                        .buttonStyle(.bordered)
                        .disabled(!vm.isConnected)

                    Button("Write 00→005E") { vm.manualWrite("005E", hex: "00", withResponse: false) }
                        .buttonStyle(.bordered)
                        .disabled(!vm.isConnected)
                }

                HStack(spacing: 10) {
                    Button("Notify 005F") { vm.manualNotify("005F", on: true) }
                        .buttonStyle(.bordered)
                        .disabled(!vm.isConnected)

                    Button("Write 00→005F") { vm.manualWrite("005F", hex: "00", withResponse: false) }
                        .buttonStyle(.bordered)
                        .disabled(!vm.isConnected)

                    Button("Recipe") { vm.manualRecipe_DefaultProbe() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!vm.isConnected)
                }
            }

            ScrollView {
                Text(vm.logs)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            }
        }
        .padding()
        .onAppear {
            vm.setup()
        }
    }
}
