import AppKit
import SwiftUI

@main
struct QMDMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = QMDStore()
    private let menuBarIcon = "externaldrive.connected.to.line.below"

    var body: some Scene {
        // Keep the status-item label stable while the popover is open. Rebuilding the
        // MenuBarExtra label in response to activeCommand changes can make macOS
        // re-anchor the window-style menu extra and lay its first row out over the
        // rest of the popover.
        MenuBarExtra("QMD", systemImage: menuBarIcon) {
            MenuBarContentView(store: store)
                .frame(width: 340)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(store: store)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
