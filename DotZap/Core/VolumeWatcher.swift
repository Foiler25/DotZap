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

import Foundation
import DiskArbitration
import AppKit

@MainActor
final class VolumeWatcher {
    static let shared = VolumeWatcher()

    private var session: DASession?
    private var watchers: [String: FSEventsWatcher] = [:]      // .realtime volumes
    private var intervalTimers: [String: Timer] = [:]          // .interval volumes
    private var mountObservers: [NSObjectProtocol] = []

    /// Mount paths already processed since their most recent mount. Both
    /// DiskArbitration and NSWorkspace can report the same mount (and the
    /// startup mount-table scan overlaps DA's registration replay); this set
    /// makes registration — and especially the initial cleanup scan — fire
    /// once per mount instead of once per source.
    private var activeMounts: Set<String> = []

    private init() {}

    // VolumeWatcher is a singleton (`shared`) whose lifetime is the whole app,
    // so this deinit does not run in normal lifecycle. It exists as hygiene
    // for any future refactor that introduces explicit teardown — without it,
    // a recreated watcher would leave the previous session's callbacks
    // registered and dispatching to a half-deallocated instance.
    //
    // Note: DiskArbitration's C API does not expose retain/release callbacks
    // (unlike FSEventStreamContext), so the `passUnretained` below is *not*
    // upgraded to `passRetained` — there's no symmetric balance point.
    // Singleton lifetime makes this safe in practice today.
    deinit {
        if let session {
            DASessionSetDispatchQueue(session, nil)
            DAUnregisterCallback(
                session,
                unsafeBitCast(Self.appearedCallback, to: UnsafeMutableRawPointer.self),
                nil
            )
            DAUnregisterCallback(
                session,
                unsafeBitCast(Self.disappearedCallback, to: UnsafeMutableRawPointer.self),
                nil
            )
        }
        for (_, watcher) in watchers {
            watcher.stop()
        }
        for (_, timer) in intervalTimers {
            timer.invalidate()
        }
        for observer in mountObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    // MARK: - Lifecycle

    func start() {
        guard session == nil else { return }
        guard let newSession = DASessionCreate(kCFAllocatorDefault) else {
            NSLog("[DotZap] DASessionCreate failed")
            return
        }
        session = newSession

        DASessionScheduleWithRunLoop(newSession, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        // See deinit comment for why this stays passUnretained.
        let context = Unmanaged.passUnretained(self).toOpaque()
        DARegisterDiskAppearedCallback(newSession, nil, Self.appearedCallback, context)
        DARegisterDiskDisappearedCallback(newSession, nil, Self.disappearedCallback, context)

        installMountObservers()
        scanExistingMounts()
    }

    /// DiskArbitration doesn't reliably deliver appeared/disappeared callbacks
    /// for network filesystems (SMB/NFS/AFP mounts have no backing DADisk on
    /// some macOS versions). NSWorkspace's mount notifications cover exactly
    /// that gap; `activeMounts` dedups volumes both sources report.
    private func installMountObservers() {
        let center = NSWorkspace.shared.notificationCenter
        let mounted = center.addObserver(
            forName: NSWorkspace.didMountNotification, object: nil, queue: .main
        ) { note in
            guard let url = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
            Task { @MainActor in
                VolumeWatcher.shared.registerMount(at: url)
            }
        }
        let unmounted = center.addObserver(
            forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main
        ) { note in
            guard let url = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
            Task { @MainActor in
                VolumeWatcher.shared.unregisterMount(path: url.path)
            }
        }
        mountObservers = [mounted, unmounted]
    }

    /// Walk the mount table once at startup. DA replays "appeared" for local
    /// disks when callbacks register, but network volumes mounted before
    /// launch would otherwise never show up.
    private func scanExistingMounts() {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeIsLocalKey, .volumeIsReadOnlyKey]
        guard let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) else { return }
        for url in urls {
            registerMount(at: url)
        }
    }

    // MARK: - Public control

    /// Start whatever monitoring the volume's cleanup mode calls for:
    /// an FSEvents stream (`.realtime`), a repeating scan timer
    /// (`.interval`), or nothing (`.manual`).
    func startMonitoring(mountPath: String) {
        guard AppState.shared.isWatching else { return }
        guard let volume = AppState.shared.volumes.first(where: { $0.mountPath == mountPath }),
              volume.isEnabled, !volume.isEjected else { return }

        switch volume.cleanupMode {
        case .realtime:
            guard watchers[mountPath] == nil else { return }
            let watcher = FSEventsWatcher(mountPath: mountPath)
            watcher.start()
            watchers[mountPath] = watcher
        case .interval:
            guard intervalTimers[mountPath] == nil else { return }
            scheduleIntervalTimer(mountPath: mountPath, minutes: volume.cleanupIntervalMinutes)
        case .manual:
            break
        }
    }

    func stopMonitoring(mountPath: String) {
        watchers.removeValue(forKey: mountPath)?.stop()
        intervalTimers.removeValue(forKey: mountPath)?.invalidate()
    }

    /// Re-derive monitoring after a cleanup-mode or interval change.
    func restartMonitoring(mountPath: String) {
        stopMonitoring(mountPath: mountPath)
        startMonitoring(mountPath: mountPath)
    }

    func pauseAll() {
        for (_, watcher) in watchers {
            watcher.stop()
        }
        watchers.removeAll()
        for (_, timer) in intervalTimers {
            timer.invalidate()
        }
        intervalTimers.removeAll()
    }

    func resumeAll() {
        for volume in AppState.shared.volumes
        where volume.isEnabled && !volume.isEjected {
            startMonitoring(mountPath: volume.mountPath)
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

    private func scheduleIntervalTimer(mountPath: String, minutes: Int) {
        let seconds = TimeInterval(max(1, minutes)) * 60
        let timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: true) { _ in
            Task { @MainActor in
                VolumeWatcher.shared.cleanNow(mountPath: mountPath)
            }
        }
        // Scans are whole-volume sweeps; exact firing time doesn't matter.
        // Tolerance lets the system coalesce wakeups.
        timer.tolerance = seconds * 0.1
        intervalTimers[mountPath] = timer
    }

    // MARK: - Callback handling

    private nonisolated static let appearedCallback: DADiskAppearedCallback = { disk, context in
        guard let context else { return }
        let me = Unmanaged<VolumeWatcher>.fromOpaque(context).takeUnretainedValue()
        // DA callbacks fire on the run loop thread (main, since we scheduled there).
        MainActor.assumeIsolated {
            me.handleAppeared(disk: disk)
        }
    }

    private nonisolated static let disappearedCallback: DADiskDisappearedCallback = { disk, context in
        guard let context else { return }
        let me = Unmanaged<VolumeWatcher>.fromOpaque(context).takeUnretainedValue()
        MainActor.assumeIsolated {
            me.handleDisappeared(disk: disk)
        }
    }

    private func handleAppeared(disk: DADisk) {
        guard let info = describe(disk: disk) else { return }
        register(info: info)
    }

    private func handleDisappeared(disk: DADisk) {
        guard let info = describe(disk: disk) else { return }
        unregisterMount(path: info.mountPath)
    }

    private func registerMount(at url: URL) {
        guard let info = describe(volumeURL: url) else { return }
        register(info: info)
    }

    private func unregisterMount(path: String) {
        activeMounts.remove(path)
        stopMonitoring(mountPath: path)
        AppState.shared.markVolumeEjected(mountPath: path)
    }

    /// Single funnel for both discovery sources (DiskArbitration +
    /// NSWorkspace/mount-table).
    private func register(info: DiskInfo) {
        guard !shouldSkip(info: info) else { return }
        guard !activeMounts.contains(info.mountPath) else { return }
        activeMounts.insert(info.mountPath)

        let existing = AppState.shared.volumes.first { $0.mountPath == info.mountPath }
        let volume = Volume(
            mountPath: info.mountPath,
            name: info.name,
            filesystem: info.filesystem,
            // Network volumes are opt-in: never auto-enable one the user
            // hasn't explicitly turned on.
            isEnabled: existing?.isEnabled ?? !info.isNetwork,
            isEjected: false,
            isNetwork: info.isNetwork,
            whitelist: existing?.whitelist ?? [],
            // FSEvents can't see remote writers on a network share, so
            // interval scanning is the honest default there.
            cleanupMode: existing?.cleanupMode ?? (info.isNetwork ? .interval : .realtime),
            cleanupIntervalMinutes: existing?.cleanupIntervalMinutes
                ?? Volume.defaultCleanupIntervalMinutes
        )
        AppState.shared.upsertVolume(volume)

        if AppState.shared.isWatching, volume.isEnabled {
            startMonitoring(mountPath: volume.mountPath)
            // Kick off an initial one-shot scan. FSEventStreamCreate doesn't do
            // any I/O, so without this the TCC "Removable Volumes" prompt only
            // fires on the user's first manual action. Scanning here triggers
            // the prompt at app launch / drive mount and also cleans any junk
            // that accumulated while the volume was untracked. Manual-mode
            // volumes are exempt — nothing runs until the user asks.
            if volume.cleanupMode != .manual {
                cleanNow(mountPath: volume.mountPath)
            }
        }
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

    /// DiskInfo from a bare volume URL (NSWorkspace notifications and the
    /// startup mount-table scan have no DADisk to describe).
    private func describe(volumeURL url: URL) -> DiskInfo? {
        let mountPath = url.path
        guard !mountPath.isEmpty else { return nil }

        let keys: Set<URLResourceKey> = [.volumeNameKey, .volumeIsLocalKey, .volumeIsReadOnlyKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return nil }

        var fs = statfs()
        let filesystem: String = statfs(mountPath, &fs) == 0
            ? withUnsafeBytes(of: fs.f_fstypename) { raw in
                String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
            }
            : "Unknown"

        let fallbackName = url.lastPathComponent.isEmpty ? "Volume" : url.lastPathComponent
        return DiskInfo(
            mountPath: mountPath,
            name: values.volumeName ?? fallbackName,
            filesystem: filesystem.uppercased(),
            isWritable: !(values.volumeIsReadOnly ?? false),
            isNetwork: !(values.volumeIsLocal ?? true)
        )
    }

    private func shouldSkip(info: DiskInfo) -> Bool {
        let path = info.mountPath
        if path == "/" { return true }
        if path.contains("/System/") { return true }
        if path.hasPrefix("/private/") { return true }
        if !info.isWritable { return true }
        return false
    }
}
