//
//  TestApp.swift
//  Test
//
//  Created by 原鸣清 on 2024/9/4.
//

import SwiftUI

@main
struct TestApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                XiaomiBleProbeView()
                    .tabItem { Label("Xiaomi", systemImage: "dot.radiowaves.left.and.right") }

                BluetoothContentView()
                    .tabItem { Label("BT Debug", systemImage: "bolt.horizontal.circle") }
            }
        }
    }
}


import Foundation
import os


final class BTLogStore: ObservableObject {
    struct Line: Identifiable {
        let id = UUID()
        let ts: Date
        let tag: String
        let text: String
    }

    @Published private(set) var lines: [Line] = []

    func add(_ tag: String, _ text: String) {
        print("\(Date()) , tag: \(tag) , TEXT: \(text)")
        lines.append(.init(ts: Date(), tag: tag, text: text))
        if lines.count > 2000 { lines.removeFirst(lines.count - 2000) }
    }
}
