import AppKit
import Combine

@MainActor
final class StatusBarController: NSObject {
    static let shared = StatusBarController()

    private var statusItem: NSStatusItem?
    private var panel: SettingsPanel?
    private var globalClickMonitor: Any?
    private var cancellables: Set<AnyCancellable> = []

    private override init() { super.init() }

    func setup() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item

        if let button = item.button {
            button.target = self
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageOnly
        }
        refreshIcon()

        AppState.shared.$isWatching
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshIcon() }
            .store(in: &cancellables)
    }

    func refreshIcon() {
        guard let button = statusItem?.button else { return }

        let symbol = AppState.shared.isWatching
            ? "sparkles.rectangle.stack"
            : "sparkles.rectangle.stack.fill"
        let description = AppState.shared.isWatching ? "DotZap (active)" : "DotZap (paused)"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)
        image?.isTemplate = true
        button.image = image
        button.appearsDisabled = !AppState.shared.isWatching
        button.toolTip = AppState.shared.isWatching
            ? "DotZap — watching"
            : "DotZap — paused"
    }

    func flash() {
        guard let button = statusItem?.button else { return }
        button.highlight(true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak button] in
            button?.highlight(false)
        }
    }

    // MARK: - Click handling

    @objc private func handleClick(_ sender: Any?) {
        guard let event = NSApp.currentEvent else { return }
        let isRight = event.type == .rightMouseUp
            || (event.type == .leftMouseUp && event.modifierFlags.contains(.control))
        if isRight {
            togglePanel()
        } else {
            AppState.shared.toggle()
        }
    }

    // MARK: - Panel

    func togglePanel() {
        if let panel, panel.isVisible {
            closePanel()
        } else {
            openPanel()
        }
    }

    private func openPanel() {
        let panel = panel ?? SettingsPanel()
        self.panel = panel

        positionPanelBelowStatusItem(panel)
        panel.orderFrontRegardless()

        installGlobalClickMonitor()
    }

    private func closePanel() {
        panel?.orderOut(nil)
        removeGlobalClickMonitor()
    }

    private func positionPanelBelowStatusItem(_ panel: NSPanel) {
        guard let button = statusItem?.button,
              let buttonWindow = button.window else { return }

        let buttonFrame = buttonWindow.frame
        let panelSize = panel.frame.size
        let originX = buttonFrame.midX - (panelSize.width / 2)
        let originY = buttonFrame.minY - panelSize.height - 8

        // Clamp to visible screen
        if let screen = buttonWindow.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            let clampedX = max(visible.minX + 8,
                               min(originX, visible.maxX - panelSize.width - 8))
            panel.setFrameOrigin(NSPoint(x: clampedX, y: originY))
        } else {
            panel.setFrameOrigin(NSPoint(x: originX, y: originY))
        }
    }

    private func installGlobalClickMonitor() {
        guard globalClickMonitor == nil else { return }
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            DispatchQueue.main.async { self?.closePanel() }
        }
    }

    private func removeGlobalClickMonitor() {
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
            globalClickMonitor = nil
        }
    }
}
