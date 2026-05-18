//
//  BluetoothContentView.swift
//  Test
//
//  Created by 原鸣清 on 2026/1/12.
//

import SwiftUI

struct BluetoothContentView: View {
    @StateObject private var logs = BTLogStore()
    @StateObject private var bt: BTDebugCentral
//    @StateObject private var setup: AccessorySetupController

    init() {
        let logs = BTLogStore()
        let bt = BTDebugCentral(logs: logs)
        _logs = StateObject(wrappedValue: logs)
        _bt = StateObject(wrappedValue: bt)
//        _setup = StateObject(wrappedValue: AccessorySetupController(bt: bt))
    }

    var body: some View {
        VStack(spacing: 12) {
//            Text(setup.status).font(.footnote)

            HStack {
//                Button("Accessory Picker") { setup.presentPicker() }
                Button("Scan") { bt.startScan(serviceUUIDs: nil) }
                Button("Stop") { bt.stopScan() }
            }

            // 设备列表（scan 的结果）
            List(bt.devices.keys.sorted(by: { $0.uuidString < $1.uuidString }), id: \.self) { id in
                let p = bt.devices[id]!
                Button {
                    bt.connect(id)
                } label: {
                    VStack(alignment: .leading) {
                        Text(p.name ?? "Unnamed")
                        Text(id.uuidString).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            // 日志窗口
            List(logs.lines) { line in
                Text("[\(line.tag)] \(line.text)")
                    .font(.caption2)
            }
        }
        .padding()
    }
}
