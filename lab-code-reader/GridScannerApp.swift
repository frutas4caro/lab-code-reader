//
//  GridScannerApp.swift
//  lab-code-reader
//
//  Created by Carolyn Aquino on 11/12/25.
//

import SwiftUI
import SwiftData

@main
struct GridScannerApp: App {
    var body: some Scene {
        WindowGroup {
            HomeView()
        }
        .modelContainer(for: ScanSession.self)
    }
}
