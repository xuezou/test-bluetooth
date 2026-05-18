//
//  BTDebugCentral.swift
//  Test
//
//  Created by 原鸣清 on 2026/1/30.
//

import Foundation
import CoreBluetooth

final class BTDebugCentral: NSObject, ObservableObject {

    @Published private(set) var state: CBManagerState = .unknown
    @Published private(set) var devices: [UUID: CBPeripheral] = [:]
    @Published private(set) var advData: [UUID: [String: Any]] = [:]
    @Published private(set) var rssi: [UUID: NSNumber] = [:]
    @Published private(set) var connectedID: UUID?

    private(set) var central: CBCentralManager!
    let logs: BTLogStore

    // 连接后缓存：service -> characteristics
    @Published private(set) var services: [CBService] = []
    @Published private(set) var charsByService: [CBUUID: [CBCharacteristic]] = [:]

    init(logs: BTLogStore) {
        self.logs = logs
        super.init()
        
        print("bundleID:", Bundle.main.bundleIdentifier ?? "nil")
        print("exe:", Bundle.main.executableURL?.path ?? "nil")
        print("appPath:", Bundle.main.bundleURL.path)
        // 恢复标识符建议带上（后台/杀进程后恢复更像“调试工具”）
        central = CBCentralManager(delegate: self, queue: .main, options: [
            CBCentralManagerOptionShowPowerAlertKey: true,
            CBCentralManagerOptionRestoreIdentifierKey: "bt.debug.central"
        ])
    }

    // MARK: Scan
    func startScan(serviceUUIDs: [CBUUID]? = nil) {
        print("NSBluetoothAlwaysUsageDescription =",
              Bundle.main.object(forInfoDictionaryKey: "NSBluetoothAlwaysUsageDescription") ?? "nil")

        print("NSBluetoothPeripheralUsageDescription =",
              Bundle.main.object(forInfoDictionaryKey: "NSBluetoothPeripheralUsageDescription") ?? "nil")
        guard central.state == .poweredOn else {
            print(" ----- \(central.state.rawValue)")
            logs.add("CB", "startScan blocked: state=\(central.state.rawValue)")
            return
        }
        logs.add("CB", "scan start serviceUUIDs=\(serviceUUIDs?.map{$0.uuidString} ?? [])")
        central.scanForPeripherals(withServices: serviceUUIDs, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: true
        ])
    }

    func stopScan() {
        central.stopScan()
        logs.add("CB", "scan stop")
    }

    // MARK: Connect
    func connect(_ id: UUID) {
        guard let p = devices[id] else { return }
        logs.add("CB", "connect -> \(p.name ?? "-") \(id)")
        p.delegate = self
        central.connect(p, options: nil)
    }

    func disconnect() {
        guard let id = connectedID, let p = devices[id] else { return }
        logs.add("CB", "disconnect -> \(p.name ?? "-") \(id)")
        central.cancelPeripheralConnection(p)
    }
    
    /// 不扫描，直接用 UUID 拿 CBPeripheral 并连接
    func connectByIdentifier(_ uuid: UUID) {
        guard central.state == .poweredOn else {
            logs.add("CB", "connectByIdentifier blocked: state=\(central.state.rawValue)")
            return
        }
        
        let ps = central.retrievePeripherals(withIdentifiers: [uuid])
        guard let p = ps.first else {
            logs.add("CB", "retrievePeripherals empty for \(uuid.uuidString)")
            return
        }
        
        devices[p.identifier] = p
        p.delegate = self
        logs.add("CB", "retrieve ✅ \(p.name ?? "-") \(p.identifier) -> connect")
        central.connect(p, options: nil)
    }

    // MARK: Discover
    func discoverAll() {
        guard let id = connectedID, let p = devices[id] else { return }
        logs.add("CB", "discoverServices(nil)")
        p.discoverServices(nil)
    }

    // MARK: Read/Write/Notify
    func setNotify(_ on: Bool, for c: CBCharacteristic) {
        guard let id = connectedID, let p = devices[id] else { return }
        logs.add("CB", "setNotify \(on) char=\(c.uuid.uuidString)")
        p.setNotifyValue(on, for: c)
    }

    func read(_ c: CBCharacteristic) {
        guard let id = connectedID, let p = devices[id] else { return }
        logs.add("CB", "read char=\(c.uuid.uuidString)")
        p.readValue(for: c)
    }

    func write(_ data: Data, to c: CBCharacteristic, withResponse: Bool) {
        guard let id = connectedID, let p = devices[id] else { return }
        let type: CBCharacteristicWriteType = withResponse ? .withResponse : .withoutResponse
        logs.add("CB", "write(\(data.count)) type=\(withResponse ? "rsp" : "no_rsp") char=\(c.uuid.uuidString)")
        p.writeValue(data, for: c, type: type)
    }

    func readRSSI() {
        guard let id = connectedID, let p = devices[id] else { return }
        p.readRSSI()
    }
}

extension BTDebugCentral: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        logs.add("CB", "state=\(central.state.rawValue) \(central.state)")
        logs.add("CB", "authorization=\(CBManager.authorization.rawValue) \(CBManager.authorization)")
        self.state = central.state

        switch central.state {
        case .poweredOn:
            logs.add("CB", "✅ poweredOn")
        case .poweredOff:
            logs.add("CB", "❌ poweredOff (系统层认为蓝牙不可用)")
        case .unauthorized:
            logs.add("CB", "❌ unauthorized (被系统/限制策略禁用)")
        case .unsupported:
            logs.add("CB", "❌ unsupported (此环境不支持 CoreBluetooth)")
        case .resetting:
            logs.add("CB", "⏳ resetting")
        case .unknown:
            logs.add("CB", "⏳ unknown")
        @unknown default:
            logs.add("CB", "???")
        }
    }
    
    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any],
                        rssi RSSI: NSNumber) {

        // 过滤 “Unnamed” / 没名字的设备
        let advName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = (peripheral.name ?? advName)?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let n = name, !n.isEmpty, n != "Unnamed" else {
            return
        }

        self.devices[peripheral.identifier] = peripheral
        self.advData[peripheral.identifier] = advertisementData
        self.rssi[peripheral.identifier] = RSSI
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        self.connectedID = peripheral.identifier
        self.services = []
        self.charsByService = [:]
        self.logs.add("CB", "connected ✅ \(peripheral.name ?? "-") \(peripheral.identifier)")
        
        peripheral.delegate = self
        peripheral.discoverServices(nil)
    }
    
    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        self.logs.add("CB", "disconnected \(peripheral.identifier) err=\(error?.localizedDescription ?? "-")")
        if self.connectedID == peripheral.identifier { self.connectedID = nil }
    }
    
    nonisolated func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
        logs.add("CB", "willRestoreState \(dict.keys)")
    }
    
    @available(iOS 13.0, *)
    func centralManager(_ central: CBCentralManager,
                        connectionEventDidOccur event: CBConnectionEvent,
                        for peripheral: CBPeripheral) {
        logs.add("CB", "connectionEvent=\(event.rawValue) for \(peripheral.name ?? "-") \(peripheral.identifier)")
    }
}

extension BTDebugCentral: CBPeripheralDelegate {
     func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
            if let e = error {
                self.logs.add("CB", "discoverServices error \(e.localizedDescription)")
                return
            }
            self.services = peripheral.services ?? []
            self.logs.add("CB", "services=\(self.services.count)")
            for s in self.services { peripheral.discoverCharacteristics(nil, for: s) }
    }
    
    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let e = error {
            self.logs.add("CB", "didUpdateValue error \(e.localizedDescription)")
            return
        }
        let data = characteristic.value ?? Data()
        self.logs.add("CB", "notify/read char=\(characteristic.uuid.uuidString) bytes=\(data.count)")
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        logs.add("CB", "didWrite char=\(characteristic.uuid.uuidString) err=\(error?.localizedDescription ?? "nil")")
    }
    
    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        logs.add("CB", "RSSI=\(RSSI) err=\(error?.localizedDescription ?? "nil")")
    }
}

@MainActor
extension BTDebugCentral {

    func applyConnectionEventMatching(serviceUUIDStrings: [String], peripheralUUIDStrings: [String]) {
        guard #available(iOS 13.0, *) else {
            logs.add("CB", "registerForConnectionEvents requires iOS 13+")
            return
        }

        let serviceUUIDs = serviceUUIDStrings
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { CBUUID(string: $0) }

        let peripheralUUIDs = peripheralUUIDStrings
            .compactMap { UUID(uuidString: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }

        var options: [CBConnectionEventMatchingOption: Any] = [:]
        if !serviceUUIDs.isEmpty { options[.serviceUUIDs] = serviceUUIDs }
        if !peripheralUUIDs.isEmpty { options[.peripheralUUIDs] = peripheralUUIDs }

        logs.add("CB", "registerForConnectionEvents options service=\(serviceUUIDs.map{$0.uuidString}) peripheral=\(peripheralUUIDs)")
        central.registerForConnectionEvents(options: options.isEmpty ? nil : options)
    }
}
