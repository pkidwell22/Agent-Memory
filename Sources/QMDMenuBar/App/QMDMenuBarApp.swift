import AppKit
import SwiftUI

@main
struct QMDMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = QMDStore()

    var body: some Scene {
        MenuBarExtra("QMD", systemImage: store.menuBarSystemImage) {
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
