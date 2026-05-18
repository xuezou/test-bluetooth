//
//  XiaomiBleProbeViewModel.swift
//  Test
//
//  Created by 原鸣清 on 2026/1/20.
//

import Foundation
import CoreBluetooth

@MainActor
final class XiaomiBleProbeViewModel: NSObject, ObservableObject {

    // MARK: - Public UI State
    @Published var logs: String = ""
    @Published var btStateText: String = "init"
    @Published var isScanning: Bool = false
    @Published var connectedName: String? = nil
    @Published var targetName: String? = "Xiaomi AI Glasses" // 你可以改成更精确
    @Published var probeWriteEnabled: Bool = false
    
    var isBluetoothReady: Bool { central?.state == .poweredOn }
    var isConnected: Bool { peripheral?.state == .connected }

    // MARK: - Private
    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    
    private var lastBLEPeripheralID: UUID? = nil
    private var didRegisterConnectionEvents = false

    // 你关心的服务 UUID
    private let targetServices: [CBUUID] = [
        CBUUID(string: "FE95"),
        CBUUID(string: "AF00"),
        CBUUID(string: "FD2D")
    ]

    // 你日志里出现的特征 UUID（可扩展）
    private let knownCharacteristicUUIDs: Set<CBUUID> = [
        CBUUID(string: "0050"),
        CBUUID(string: "005E"),
        CBUUID(string: "005F"),
        CBUUID(string: "AF07"),
        CBUUID(string: "AF08"),
        CBUUID(string: "FF11"),
        CBUUID(string: "FF12"),
        CBUUID(string: "FF13")
    ]

    // 订阅/读写探测队列
    private var probeQueue: [ProbeAction] = []
    private var isProbing: Bool = false
    
    @Published var autoProbeEnabled: Bool = true   // ✅ 默认保持原行为
    
    // ✅ 手动操作：缓存已发现的 characteristic（uuid -> characteristic）
    private var charMap: [CBUUID: CBCharacteristic] = [:]

    private func cacheCharacteristics(_ chars: [CBCharacteristic]) {
        for c in chars { charMap[c.uuid] = c }
    }

    private func ch(_ uuidString: String) -> CBCharacteristic? {
        charMap[CBUUID(string: uuidString)]
    }

    func setup() {
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main)
            log("setup central")
        }
    }

    func startScan() {
        guard let central else { return }
        guard central.state == .poweredOn else {
            log("Bluetooth not poweredOn (state=\(central.state.rawValue))")
            return
        }

        logs = ""
        isScanning = true
        log("Start scanning…")

        // 你可以只扫目标 service，提高命中率；也可以扫 nil 以拿到更多信息（但耗电）
        central.scanForPeripherals(withServices: nil,
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    func stopAll() {
        isScanning = false
        isProbing = false
        probeQueue.removeAll()
        charMap.removeAll()   // ✅

        if let central {
            central.stopScan()
        }
        if let p = peripheral, let central {
            central.cancelPeripheralConnection(p)
        }
        log("Stop all")
    }

    func discoverAndProbe() {
        guard let p = peripheral else { return }
        autoProbeEnabled = true          // ✅ 一键模式开启自动探测
        probeQueue.removeAll()
        isProbing = false
        log("Discover services \(targetServices.map{$0.uuidString})")
        p.discoverServices(targetServices)
    }

    // MARK: - Logging
    private func log(_ s: String) {
        let t = Self.ts()
        logs += "[\(t)] \(s)\n"
        print("[Probe] \(s)")
    }

    private static func ts() -> String {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss.SSS"
        return df.string(from: Date())
    }
    
    @MainActor
    func enableConnectionEventMonitoring() {
        guard #available(iOS 13.0, *) else { return }
        guard let central else { return }
        guard !didRegisterConnectionEvents else { return }
        didRegisterConnectionEvents = true

        // 先用 serviceUUIDs 提高匹配概率；不确定也可以传 nil
        let options: [CBConnectionEventMatchingOption: Any] = [
            .serviceUUIDs: [CBUUID(string: "FE95")]
        ]

        central.registerForConnectionEvents(options: options)
        log("CB registerForConnectionEvents ✅ serviceUUIDs=[FE95]")
    }
}

// MARK: - CBCentralManagerDelegate
extension XiaomiBleProbeViewModel: @MainActor CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        btStateText = "state=\(central.state.rawValue)"
        switch central.state {
        case .poweredOn:
            log("Bluetooth poweredOn")
        case .unauthorized:
            log("Bluetooth unauthorized (check permission & Settings)")
        case .poweredOff:
            log("Bluetooth poweredOff")
        default:
            
            log("Bluetooth state=\(central.state.rawValue)")
        }
        if #available(iOS 13.0, *), central.state == .poweredOn {
            enableConnectionEventMonitoring()
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover p: CBPeripheral,
                        advertisementData: [String : Any],
                        rssi RSSI: NSNumber) {

        let name = p.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? "Unknown"
        // 粗匹配：你也可以改成更严格：完全相等、包含、或者匹配 manufacturer data
        if let target = targetName, !target.isEmpty {
            let ok = name.localizedCaseInsensitiveContains(target)
                || target.localizedCaseInsensitiveContains(name)
                || name.localizedCaseInsensitiveContains("Xiaomi")
                || name.localizedCaseInsensitiveContains("Glasses")
            if !ok { return }
        }

        log("Found: \(name) rssi=\(RSSI)")
        isScanning = false
        central.stopScan()

        peripheral = p
        connectedName = name
        p.delegate = self

        log("Connecting…")
        let options: [String: Any] = [
            CBConnectPeripheralOptionEnableTransportBridgingKey: true,
            CBConnectPeripheralOptionNotifyOnConnectionKey: true
        ]
        central.connect(p, options: options)
    }

    func centralManager(_ central: CBCentralManager, didConnect p: CBPeripheral) {
        log("Connected ✅ name=\(p.name ?? "-") mtu=\(p.maximumWriteValueLength(for: .withResponse))")
        connectedName = p.name
        // 不自动 discover，交给按钮；你也可以自动跑：
        // discoverAndProbe()
    }
    

    func centralManager(_ central: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        log("Connect failed ❌ \(error?.localizedDescription ?? "")")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        log("Disconnected \(error?.localizedDescription ?? "")")
        connectedName = nil
        peripheral = nil
        isProbing = false
        probeQueue.removeAll()
        
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.startScan()
        }
    }
    
    @available(iOS 13.0, *)
    func centralManager(_ central: CBCentralManager,
                        connectionEventDidOccur event: CBConnectionEvent,
                        for peripheral: CBPeripheral) {

        log("CB connectionEventDidOccur event=\(event.rawValue) p=\(peripheral.name ?? "-") \(peripheral.identifier)")

        switch event {
        case .peerConnected:
            // ✅ 这里把它当作 “BT/系统层已连上” 的信号，然后去重连 BLE
            // 方式 A：如果这个 identifier 就是 BLE 的（很多双模设备会复用/桥接），直接 retrieve+connect
            connectBLEAfterBTConnected(peripheralIDFromEvent: peripheral.identifier)

        case .peerDisconnected:
            // 可选：BT 断开后，你要不要也断开 BLE / 或者保留 BLE
            // disconnectBLEIfNeeded()
            break

        @unknown default:
            break
        }
    }
    
    @MainActor
    private func connectBLEAfterBTConnected(peripheralIDFromEvent: UUID) {
        guard let central else { return }

        // 1) BLE 已经连着就不管
        if let p = peripheral, p.state == .connected {
            log("CB BLE already connected, skip")
            return
        }

        // 2) 优先用我们自己记录的 BLE peripheral UUID（更靠谱）
        let candidateID = lastBLEPeripheralID ?? peripheralIDFromEvent

        let ps = central.retrievePeripherals(withIdentifiers: [candidateID])
        if let p = ps.first {
            log("CB BT connected -> retrieve BLE ✅ \(p.name ?? "-") \(p.identifier) -> connect")
            peripheral = p
            connectedName = p.name
            p.delegate = self

            central.connect(p, options: [
                CBConnectPeripheralOptionNotifyOnConnectionKey: true,
                CBConnectPeripheralOptionEnableTransportBridgingKey: true
            ])
            return
        }

        // 3) retrieve 失败，fallback：扫描 10 秒再按你现有逻辑命中并连接
        log("CB retrieve empty, fallback to scan for BLE (10s)")
        startScan()

        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.central?.stopScan()
            self?.isScanning = false
            self?.log("Stop scan (fallback timeout)")
        }
    }
    
    // MARK: - Manual Step Actions (按钮触发)
    func manualDiscoverServices() {
        guard let p = peripheral else { return }
        log("Manual: discoverServices \(targetServices.map{$0.uuidString})")

        // ✅ 手动模式：只 discover，不要自动 probe
        autoProbeEnabled = false

        charMap.removeAll()
        probeQueue.removeAll()
        isProbing = false

        p.discoverServices(targetServices)
    }

    /// 手动读
    func manualRead(_ uuid: String) {
        guard let p = peripheral else { return }
        guard let c = ch(uuid) else {
            log("❌ ManualRead: char not found \(uuid) (did you discover?)")
            return
        }
        log("Manual → read char=\(uuid)")
        p.readValue(for: c)
    }

    /// 手动 notify
    func manualNotify(_ uuid: String, on: Bool = true) {
        guard let p = peripheral else { return }
        guard let c = ch(uuid) else {
            log("❌ ManualNotify: char not found \(uuid) (did you discover?)")
            return
        }
        log("Manual → setNotify(\(on)) char=\(uuid)")
        p.setNotifyValue(on, for: c)
    }

    /// 手动写（hex 字符串：比如 "00" / "AABB" / "01 02" 都支持）
    func manualWrite(_ uuid: String, hex: String, withResponse: Bool) {
        guard let p = peripheral else { return }
        guard let c = ch(uuid) else {
            log("❌ ManualWrite: char not found \(uuid) (did you discover?)")
            return
        }
        let data = Data(hexString: hex)
        let type: CBCharacteristicWriteType = withResponse ? .withResponse : .withoutResponse
        log("Manual → write(\(withResponse ? "withResp" : "noResp")) char=\(uuid) data=\(data.map{String(format:"%02X",$0)}.joined())")
        p.writeValue(data, for: c, type: type)
    }

    /// 手动：discover descriptors（看 2902）
    func manualDiscoverDescriptors(_ uuid: String) {
        guard let p = peripheral else { return }
        guard let c = ch(uuid) else {
            log("❌ ManualDesc: char not found \(uuid)")
            return
        }
        log("Manual → discoverDescriptors char=\(uuid)")
        p.discoverDescriptors(for: c)
    }

    /// 快捷：复现你日志那套
    func manualRecipe_DefaultProbe() {
        // 你日志顺序：read 0050 -> setNotify 005E -> write00 005E -> setNotify 005F -> write00 005F
        manualRead("0050")
        manualNotify("005E", on: true)
        manualWrite("005E", hex: "00", withResponse: false)
        manualNotify("005F", on: true)
        manualWrite("005F", hex: "00", withResponse: false)
    }

    /// 打印当前已缓存的 chars
    func manualDumpChars() {
        if charMap.isEmpty {
            log("ManualDump: charMap empty (did you discover?)")
            return
        }
        let list = charMap.values
            .sorted { $0.uuid.uuidString < $1.uuid.uuidString }
            .map { "  - \($0.uuid.uuidString) props=\(describeProps($0.properties))" }
            .joined(separator: "\n")
        log("ManualDump chars:\n\(list)")
    }
}

// MARK: - CBPeripheralDelegate
extension XiaomiBleProbeViewModel: @MainActor CBPeripheralDelegate {

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        if let e = error {
            log("didDiscoverServices error: \(e.localizedDescription)")
            return
        }
        let svcs = p.services ?? []
        log("Services discovered: \(svcs.map{$0.uuid.uuidString}.joined(separator: ","))")

        // 只对目标 services discover characteristics
        for s in svcs where targetServices.contains(s.uuid) {
            log("Discover characteristics for service \(s.uuid.uuidString)")
            p.discoverCharacteristics(nil, for: s) // nil = all
        }
    }
    
    func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let e = error as NSError? {
            log("NotifyState FAILED char=\(characteristic.uuid.uuidString) err=\(e.domain) code=\(e.code) \(e.localizedDescription)")
        } else {
            log("NotifyState OK char=\(characteristic.uuid.uuidString) isNotifying=\(characteristic.isNotifying)")
        }
        stepProbe()
    }

    func peripheral(_ p: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        if let e = error {
            log("didDiscoverCharacteristics error: \(e.localizedDescription) service=\(service.uuid.uuidString)")
            return
        }
        let chars = service.characteristics ?? []
        log("Chars discovered for \(service.uuid.uuidString): \(chars.map{$0.uuid.uuidString}.joined(separator: ","))")

        // ✅ 缓存，给“分步按钮”用
        cacheCharacteristics(chars)

        // 打印属性
        for c in chars {
            let props = describeProps(c.properties)
            log("  - char \(c.uuid.uuidString) props=\(props)")
        }

        // discover descriptors
        for c in chars { p.discoverDescriptors(for: c) }

        // ✅ 仍保留一键探测逻辑
        if autoProbeEnabled {
            enqueueProbeActions(from: chars)
            runProbeIfNeeded()
        } else {
            log("AutoProbe disabled: skip enqueue/runProbe")
        }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverDescriptorsFor characteristic: CBCharacteristic, error: Error?) {
        if let e = error {
            log("didDiscoverDescriptors error: \(e.localizedDescription) char=\(characteristic.uuid.uuidString)")
            return
        }
        let ds = characteristic.descriptors ?? []
        let dnames = ds.map { $0.uuid.uuidString }.joined(separator: ",")
        log("Descriptors for \(characteristic.uuid.uuidString): \(dnames)")
    }


    // read 结果
    func peripheral(_ p: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let e = error {
            log("Read/Notify update FAILED char=\(characteristic.uuid.uuidString) err=\(e.localizedDescription)")
        } else {
            let data = characteristic.value ?? Data()
            log("Value update char=\(characteristic.uuid.uuidString) len=\(data.count) hex=\(data.prefix(32).map{String(format:"%02X",$0)}.joined())")
        }

        // 如果这是 read 行为的回调，就继续 probe（notify 更新也会走这里，但没关系）
        if isProbing {
            stepProbe()
        }
    }

    // write withResponse 结果
    func peripheral(_ p: CBPeripheral,
                    didWriteValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let e = error {
            log("Write FAILED char=\(characteristic.uuid.uuidString) err=\(e.localizedDescription)")
        } else {
            log("Write OK char=\(characteristic.uuid.uuidString)")
        }
        stepProbe()
    }
}

// MARK: - Probe Engine
private extension XiaomiBleProbeViewModel {

    enum ProbeAction {
        case setNotify(CBCharacteristic)
        case read(CBCharacteristic)
        case write(CBCharacteristic, Data, CBCharacteristicWriteType)
    }

    func enqueueProbeActions(from chars: [CBCharacteristic]) {
        // 只探测一次（你也可以改成每次都重建）
        guard probeQueue.isEmpty else { return }

        // 排序：known UUID 优先；notify > read > write
        let sorted = chars.sorted { a, b in
            let ak = knownCharacteristicUUIDs.contains(a.uuid) ? 0 : 1
            let bk = knownCharacteristicUUIDs.contains(b.uuid) ? 0 : 1
            if ak != bk { return ak < bk }
            return a.uuid.uuidString < b.uuid.uuidString
        }

        for c in sorted {
            // 1) notify 优先：这最容易触发配对（写 CCCD）
            if c.properties.contains(.notify) || c.properties.contains(.indicate) {
                probeQueue.append(.setNotify(c))
            }
            // 2) read
            if c.properties.contains(.read) {
                probeQueue.append(.read(c))
            }
            // 3) write（可选）
            if probeWriteEnabled {
                if c.properties.contains(.write) {
                    probeQueue.append(.write(c, Data([0x00]), .withResponse))
                } else if c.properties.contains(.writeWithoutResponse) {
                    probeQueue.append(.write(c, Data([0x00]), .withoutResponse))
                }
            }
        }

        log("ProbeQueue size=\(probeQueue.count) (writeProbe=\(probeWriteEnabled))")
    }

    func runProbeIfNeeded() {
        guard !isProbing else { return }
        guard let _ = peripheral else { return }
        guard !probeQueue.isEmpty else { return }

        isProbing = true
        log("Start probing…")
        stepProbe()
    }

    func stepProbe() {
        guard isProbing else { return }
        guard let p = peripheral else { isProbing = false; return }

        guard !probeQueue.isEmpty else {
            log("Probing finished ✅")
            isProbing = false
            return
        }

        let action = probeQueue.removeFirst()

        switch action {
        case .setNotify(let c):
            log("→ setNotify(true) char=\(c.uuid.uuidString)")
            p.setNotifyValue(true, for: c)

        case .read(let c):
            log("→ read char=\(c.uuid.uuidString)")
            p.readValue(for: c)

        case .write(let c, let data, let type):
            log("→ write(\(type == .withResponse ? "withResp" : "noResp")) char=\(c.uuid.uuidString) data=\(data.map{String(format:"%02X",$0)}.joined())")
            p.writeValue(data, for: c, type: type)
            if type == .withoutResponse {
                // withoutResponse 没回调，给个短延迟再继续
                Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    await MainActor.run { self?.stepProbe() }
                }
            }
        }
    }

    func describeProps(_ p: CBCharacteristicProperties) -> String {
        var a: [String] = []
        if p.contains(.read) { a.append("read") }
        if p.contains(.write) { a.append("write") }
        if p.contains(.writeWithoutResponse) { a.append("writeNoResp") }
        if p.contains(.notify) { a.append("notify") }
        if p.contains(.indicate) { a.append("indicate") }
        if p.contains(.authenticatedSignedWrites) { a.append("signedWrite") }
        if p.contains(.extendedProperties) { a.append("extended") }
        return a.joined(separator: "|")
    }
}

private extension Data {
    init(hexString: String) {
        self.init()
        let s = hexString.replacingOccurrences(of: " ", with: "")
        var i = s.startIndex
        while i < s.endIndex {
            let j = s.index(i, offsetBy: 2, limitedBy: s.endIndex) ?? s.endIndex
            if j <= s.endIndex, i < j {
                let byteStr = String(s[i..<j])
                if let b = UInt8(byteStr, radix: 16) { append(b) }
            }
            i = j
        }
    }
}
