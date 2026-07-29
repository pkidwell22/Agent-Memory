import AppKit
import SwiftUI

@main
struct QMDMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = QMDStore()
    private let menuBarIcon: NSImage = {
        let resourceURL = Bundle.main.url(forResource: "QMDAperture", withExtension: "svg")
            ?? Bundle.module.url(forResource: "QMDAperture", withExtension: "svg")
        let image = resourceURL
            .flatMap(NSImage.init(contentsOf:))
            ?? NSImage(
                systemSymbolName: "externaldrive.connected.to.line.below",
                accessibilityDescription: "Agent Memory"
            )!
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }()

    var body: some Scene {
        // Keep the status-item label stable while the popover is open. Rebuilding the
        // MenuBarExtra label in response to activeCommand changes can make macOS
        // re-anchor the window-style menu extra and lay its first row out over the
        // rest of the popover.
        MenuBarExtra {
            MenuBarContentView(store: store)
                .frame(width: 340)
        } label: {
            Image(nsImage: menuBarIcon)
                .accessibilityLabel("Agent Memory")
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
