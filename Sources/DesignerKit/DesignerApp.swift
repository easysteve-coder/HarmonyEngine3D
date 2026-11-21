import SwiftUI
import AppKit

// MARK: – AppDelegate
// Sorgt dafür dass die App beim Start sofort aktiv wird
// und Tastatureingaben (⌘E, Tab, etc.) empfangen kann.

class DesignerAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        print("✅ [Designer] App aktiviert – Tastatur bereit")
    }
}

// MARK: – Entry Point

@main
struct DesignerApp: App {

    @NSApplicationDelegateAdaptor(DesignerAppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup("Harmony Designer Kit") {
            DesignerCanvasView()
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1200, height: 820)
    }
}
