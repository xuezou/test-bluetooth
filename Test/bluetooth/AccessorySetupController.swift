//
//  AccessorySetupController.swift
//  Test
//
//  Created by 原鸣清 on 2026/1/20.
//
/*
import Foundation
import AccessorySetupKit
import os
import CoreBluetooth

@MainActor
final class AccessorySetupController: ObservableObject {
    @Published var status: String = "AccessorySetupKit: idle"

    private let log = Logger(subsystem: "YourApp", category: "AccessorySetupKit")
    private var session: ASAccessorySession?   // <- 改成可选，不要启动就创建
    private let bt: BTDebugCentral

    init(bt: BTDebugCentral) {
        self.bt = bt
        status = "AccessorySetupKit: ready"
    }

    private func ensureSession() {
        if session != nil { return }
        let s = ASAccessorySession()
        session = s
        log.info("ASAccessorySession created")

        s.activate(on: .main) { [weak self] event in
            guard let self else { return }
            self.handle(event)
        }
    }

    func presentPicker() {
        ensureSession() // <- 只有点按钮才初始化/activate

        log.info("showPicker called")
        status = "showPicker…"

        let d = ASDiscoveryDescriptor()
        d.bluetoothServiceUUID = CBUUID(string: "FE95")

        let item = ASPickerDisplayItem(
            name: "XIAO MI",
            productImage: UIImage(systemName: "star")!,
            descriptor: d
        )

        let d1 = ASDiscoveryDescriptor()
        d1.bluetoothServiceUUID = CBUUID(string: "FFF7")

        let item1 = ASPickerDisplayItem(
            name: "loomos L1",
            productImage: UIImage(systemName: "moon")!,
            descriptor: d1
        )

        session?.showPicker(for: [item, item1]) { [weak self] error in
            guard let self else { return }
            if let error {
                self.log.error("showPicker error: \(error.localizedDescription, privacy: .public)")
                self.status = "showPicker error: \(error.localizedDescription)"
            } else {
                self.log.info("picker presented")
                self.status = "picker presented"
            }
        }
    }

    private func handle(_ event: ASAccessoryEvent) {
        bt.logs.add("AS", "event=\(event.eventType)")
        status = "event: \(event.eventType)"

        switch event.eventType {
        case .accessoryAdded, .accessoryChanged:
            guard let accessory = event.accessory else { return }
            guard let uuid = accessory.bluetoothIdentifier else {
                bt.logs.add("AS", "accessory has no bluetoothIdentifier")
                return
            }
            bt.logs.add("AS", "accessoryReady name=\(accessory.displayName ?? "-") uuid=\(uuid.uuidString)")
            bt.connectByIdentifier(uuid)

        case .pickerDidDismiss:
            bt.logs.add("AS", "picker dismissed")
        default:
            break
        }
    }
}
*/
