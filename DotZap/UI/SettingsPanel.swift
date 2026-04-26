import AppKit
import SwiftUI

final class SettingsPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 480),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        isMovableByWindowBackground = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        animationBehavior = .utilityWindow
        hidesOnDeactivate = false

        let bounds = NSRect(x: 0, y: 0, width: 360, height: 480)
        let blur = NSVisualEffectView(frame: bounds)
        blur.autoresizingMask = [.width, .height]
        blur.blendingMode = .behindWindow
        blur.material = .sidebar
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 14
        blur.layer?.masksToBounds = true
        blur.layer?.cornerCurve = .continuous

        let host = NSHostingView(rootView: SettingsView())
        host.frame = blur.bounds
        host.autoresizingMask = [.width, .height]
        blur.addSubview(host)

        contentView = blur
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
