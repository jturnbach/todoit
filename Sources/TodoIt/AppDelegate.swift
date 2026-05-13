import AppKit
import SwiftUI
import TodoItCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) weak var shared: AppDelegate?

    private var mainWindowController: NSWindowController?

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    @MainActor
    func showMainWindow() {
        if let wc = mainWindowController, let window = wc.window {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let rootView = MainWindowView()
            .environmentObject(TaskStore.shared)

        let hosting = NSHostingController(rootView: rootView)
        hosting.preferredContentSize = NSSize(width: 880, height: 600)

        let window = NSWindow(contentViewController: hosting)
        window.title = "TodoIt"
        window.setContentSize(NSSize(width: 880, height: 600))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = false
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 720, height: 480)

        let wc = NSWindowController(window: window)
        mainWindowController = wc

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(mainWindowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: window
        )

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        wc.showWindow(nil)
    }

    @objc private func mainWindowWillClose(_ note: Notification) {
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }
}
