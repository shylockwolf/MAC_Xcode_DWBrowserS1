//
//  DWBrowserApp.swift
//  DWBrowser
//
//  Created by noone on 2025/11/17.
//

import SwiftUI
import AppKit

@main
struct DWBrowserApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 800, minHeight: 600)
        }
        .commands {
            CommandGroup(replacing: .help) {
                Button("About DWBrowser") {
                    showAboutDialog()
                }
                .keyboardShortcut("/")
            }
        }
    }
    
    private func showAboutDialog() {
        let alert = NSAlert()
        alert.messageText = "DWBrowser"
        alert.informativeText = "Version v1.0\n\nAuthor: Shylock Wolf\nCreation Date: 2025-11-17"
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
