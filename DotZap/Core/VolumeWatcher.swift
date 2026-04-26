import Foundation
import DiskArbitration
import AppKit

@MainActor
final class VolumeWatcher {
    static let shared = VolumeWatcher()

    private var session: DASession?
    private var watchers: [String: FSEventsWatcher] = [:]

    private init() {}

    // MARK: - Lifecycle

    func start() {
        guard session == nil else { return }
        guard let newSession = DASessionCreate(kCFAllocatorDefault) else {
            NSLog("[DotZap] DASessionCreate failed")
            return
        }
        session = newSession

        DASessionScheduleWithRunLoop(newSession, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        let context = Unmanaged.passUnretained(self).toOpaque()
        DARegisterDiskAppearedCallback(newSession, nil, Self.appearedCallback, context)
        DARegisterDiskDisappearedCallback(newSession, nil, Self.disappearedCallback, context)
    }

    // MARK: - Public control

    func startWatching(mountPath: String) {
        guard AppState.shared.isWatching else { return }
        guard watchers[mountPath] == nil else { return }
        let watcher = FSEventsWatcher(mountPath: mountPath)
        watcher.start()
        watchers[mountPath] = watcher
    }

    func stopWatching(mountPath: String) {
        guard let watcher = watchers[mountPath] else { return }
        watcher.stop()
        watchers.removeValue(forKey: mountPath)
    }

    func pauseAll() {
        for (_, watcher) in watchers {
            watcher.stop()
        }
        watchers.removeAll()
    }

    func resumeAll() {
        for volume in AppState.shared.volumes
        where volume.isEnabled && !volume.isEjected && watchers[volume.mountPath] == nil {
            let watcher = FSEventsWatcher(mountPath: volume.mountPath)
            watcher.start()
            watchers[volume.mountPath] = watcher
        }
    }

    func cleanNow(mountPath: String) {
        if let watcher = watchers[mountPath] {
            watcher.cleanNow()
        } else {
            // Run a one-off scan even if not actively watching
            let oneShot = FSEventsWatcher(mountPath: mountPath)
            oneShot.cleanNow()
        }
    }

    // MARK: - Callback handling

    private static let appearedCallback: DADiskAppearedCallback = { disk, context in
        guard let context else { return }
        let me = Unmanaged<VolumeWatcher>.fromOpaque(context).takeUnretainedValue()
        // DA callbacks fire on the run loop thread (main, since we scheduled there).
        MainActor.assumeIsolated {
            me.handleAppeared(disk: disk)
        }
    }

    private static let disappearedCallback: DADiskDisappearedCallback = { disk, context in
        guard let context else { return }
        let me = Unmanaged<VolumeWatcher>.fromOpaque(context).takeUnretainedValue()
        MainActor.assumeIsolated {
            me.handleDisappeared(disk: disk)
        }
    }

    private func handleAppeared(disk: DADisk) {
        guard let info = describe(disk: disk) else { return }
        guard !shouldSkip(info: info) else { return }

        let volume = Volume(
            mountPath: info.mountPath,
            name: info.name,
            filesystem: info.filesystem,
            isEnabled: existingEnabledState(for: info.mountPath) ?? true,
            isEjected: false,
            isNetwork: info.isNetwork,
            whitelist: existingWhitelist(for: info.mountPath) ?? []
        )
        AppState.shared.upsertVolume(volume)

        if AppState.shared.isWatching, volume.isEnabled {
            startWatching(mountPath: volume.mountPath)
        }
    }

    private func handleDisappeared(disk: DADisk) {
        guard let info = describe(disk: disk) else { return }
        stopWatching(mountPath: info.mountPath)
        AppState.shared.markVolumeEjected(mountPath: info.mountPath)
    }

    // MARK: - Description parsing

    private struct DiskInfo {
        let mountPath: String
        let name: String
        let filesystem: String
        let isWritable: Bool
        let isNetwork: Bool
    }

    private func describe(disk: DADisk) -> DiskInfo? {
        guard let cfDesc = DADiskCopyDescription(disk) else { return nil }
        let desc = cfDesc as NSDictionary

        guard let pathURL = desc[kDADiskDescriptionVolumePathKey] as? URL else {
            return nil
        }
        let mountPath = pathURL.path
        guard !mountPath.isEmpty else { return nil }

        let fallbackName = pathURL.lastPathComponent.isEmpty ? "Volume" : pathURL.lastPathComponent
        let name = (desc[kDADiskDescriptionVolumeNameKey] as? String) ?? fallbackName
        let filesystem = (desc[kDADiskDescriptionVolumeKindKey] as? String) ?? "Unknown"
        let isWritable = (desc[kDADiskDescriptionMediaWritableKey] as? Bool) ?? true
        let isNetwork = (desc[kDADiskDescriptionVolumeNetworkKey] as? Bool) ?? false

        return DiskInfo(
            mountPath: mountPath,
            name: name,
            filesystem: filesystem.uppercased(),
            isWritable: isWritable,
            isNetwork: isNetwork
        )
    }

    private func shouldSkip(info: DiskInfo) -> Bool {
        let path = info.mountPath
        if path == "/" { return true }
        if path.contains("/System/") { return true }
        if path.hasPrefix("/private/") { return true }
        if !info.isWritable { return true }
        if info.isNetwork {
            // Only watch network volumes the user has previously enabled.
            let known = AppState.shared.volumes.contains { $0.mountPath == path }
            if !known { return true }
        }
        return false
    }

    private func existingEnabledState(for mountPath: String) -> Bool? {
        AppState.shared.volumes.first { $0.mountPath == mountPath }?.isEnabled
    }

    private func existingWhitelist(for mountPath: String) -> [String]? {
        AppState.shared.volumes.first { $0.mountPath == mountPath }?.whitelist
    }
}
