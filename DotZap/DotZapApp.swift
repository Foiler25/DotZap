import SwiftUI
import AppKit
import Sparkle

@main
struct DotZapApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    lazy var updaterController: SPUStandardUpdaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        AppState.shared.loadPersisted()
        UpdaterModel.shared.attach(updaterController.updater)
        StatusBarController.shared.setup()
        VolumeWatcher.shared.start()
        AppState.shared.startWatchingIfEnabled()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
