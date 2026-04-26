import SwiftUI
import AppKit

@main
struct DotZapApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        AppState.shared.loadPersisted()
        StatusBarController.shared.setup()
        VolumeWatcher.shared.start()
        AppState.shared.startWatchingIfEnabled()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
