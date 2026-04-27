// DotZap — auto-deletes Apple metadata junk on every mounted volume.
// Copyright (C) 2026 Brandon Villar
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

import AppKit
import Combine

@MainActor
final class StatusBarController: NSObject {
    static let shared = StatusBarController()

    private var statusItem: NSStatusItem?
    private var panel: SettingsPanel?
    private var globalClickMonitor: Any?
    private var localRightClickMonitor: Any?
    private var cancellables: Set<AnyCancellable> = []

    private override init() { super.init() }

    deinit {
        if let monitor = localRightClickMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    func setup() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item

        if let button = item.button {
            button.target = self
            button.action = #selector(handleLeftClick(_:))
            button.sendAction(on: [.leftMouseDown])
            button.imagePosition = .imageOnly
        }
        installRightClickMonitor()
        refreshIcon()

        AppState.shared.$isWatching
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshIcon() }
            .store(in: &cancellables)
    }

    /// Right-click and Ctrl-Left-Click on `NSStatusBarButton` are not delivered
    /// to the action target on macOS Tahoe (26) — the system consumes them
    /// unless a `menu` is assigned. Catch them via a local event monitor before
    /// the system can swallow them.
    private func installRightClickMonitor() {
        guard localRightClickMonitor == nil else { return }
        localRightClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.rightMouseDown, .leftMouseDown]
        ) { [weak self] event in
            guard let self = self,
                  let buttonWindow = self.statusItem?.button?.window,
                  event.window === buttonWindow else {
                return event
            }
            let isContextual = event.type == .rightMouseDown
                || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
            guard isContextual else { return event }
            DispatchQueue.main.async { self.togglePanel() }
            return nil
        }
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

    @objc private func handleLeftClick(_ sender: Any?) {
        AppState.shared.toggle()
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
