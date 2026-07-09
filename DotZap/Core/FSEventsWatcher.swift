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
import CoreServices

final class FSEventsWatcher {
    let mountPath: String
    private var stream: FSEventStreamRef?
    private let queue: DispatchQueue
    private var isStarted = false

    init(mountPath: String) {
        self.mountPath = mountPath
        let safeLabel = mountPath
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        self.queue = DispatchQueue(label: "com.dotzap.fsevents\(safeLabel)", qos: .utility)
    }

    deinit {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }

    func start() {
        guard !isStarted else { return }

        // passRetained + matching retain/release callbacks: the stream owns a
        // +1 reference for its lifetime, and CF balances it on every internal
        // copy. This makes deinit-during-callback safe — previously the
        // stream held a raw pointer with no lifecycle hooks, and `stop()`
        // could race with an in-flight callback dispatched on the queue.
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passRetained(self).toOpaque(),
            retain: { ptr in
                guard let ptr else { return nil }
                _ = Unmanaged<FSEventsWatcher>.fromOpaque(ptr).retain()
                return ptr
            },
            release: { ptr in
                guard let ptr else { return }
                Unmanaged<FSEventsWatcher>.fromOpaque(ptr).release()
            },
            copyDescription: nil
        )

        let pathsToWatch = [mountPath] as CFArray
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagUseCFTypes |
            kFSEventStreamCreateFlagNoDefer
        )

        guard let newStream = FSEventStreamCreate(
            kCFAllocatorDefault,
            Self.eventCallback,
            &context,
            pathsToWatch,
            FSEventsGetCurrentEventId(),
            0.25,
            flags
        ) else { return }

        FSEventStreamSetDispatchQueue(newStream, queue)
        FSEventStreamStart(newStream)

        stream = newStream
        isStarted = true
    }

    func stop() {
        guard isStarted, let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        isStarted = false
    }

    func cleanNow() {
        let mountPath = self.mountPath
        Task { @MainActor in
            let state = AppState.shared
            guard let volume = state.volumes.first(where: { $0.mountPath == mountPath }) else { return }
            // One scan per volume at a time. Long crawls (network mounts)
            // could otherwise stack up when an interval timer fires or the
            // user mashes Clean Now while a scan is still running.
            guard !state.scanningVolumes.contains(mountPath) else { return }
            state.scanningVolumes.insert(mountPath)
            let rules = state.rules
            let settings = FileJanitor.DeletionSettings(
                moveToTrash: state.moveToTrash,
                maxFileSizeBytes: state.maxFileSizeBytes
            )

            Task.detached(priority: .userInitiated) {
                Self.scan(mountPath: mountPath, rules: rules, volume: volume, settings: settings)
                await MainActor.run {
                    AppState.shared.scanningVolumes.remove(mountPath)
                }
            }
        }
    }

    /// Full-volume sweep. Events are flushed to AppState in chunks as the
    /// walk progresses — a scan of a large volume (especially over a network
    /// mount) can run for a long time, and reporting only at the end makes
    /// the app look idle for the whole crawl.
    private static func scan(
        mountPath: String,
        rules: [CleanRule],
        volume: Volume,
        settings: FileJanitor.DeletionSettings
    ) {
        let flushThreshold = 25
        var pending: [DeletionEvent] = []

        func flush() {
            guard !pending.isEmpty else { return }
            let batch = pending
            pending.removeAll()
            Task { @MainActor in
                AppState.shared.recordBatch(batch)
                if batch.contains(where: { $0.status == .deleted }) {
                    AppState.shared.flashStatusIcon()
                }
            }
        }

        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: mountPath) else { return }

        while let relPath = enumerator.nextObject() as? String {
            let fullPath = (mountPath as NSString).appendingPathComponent(relPath)
            if let rule = RuleEngine.evaluate(path: fullPath, rules: rules),
               let event = FileJanitor.delete(path: fullPath, rule: rule,
                                              volume: volume, settings: settings) {
                pending.append(event)
                if event.status == .deleted {
                    enumerator.skipDescendants()
                }
                if pending.count >= flushThreshold { flush() }
            }
        }
        flush()
    }

    // MARK: - Callback

    private static let eventCallback: FSEventStreamCallback = { (
        _: ConstFSEventStreamRef,
        info: UnsafeMutableRawPointer?,
        numEvents: Int,
        eventPaths: UnsafeMutableRawPointer,
        eventFlags: UnsafePointer<FSEventStreamEventFlags>,
        _: UnsafePointer<FSEventStreamEventId>
    ) in
        guard let info else { return }
        let watcher = Unmanaged<FSEventsWatcher>.fromOpaque(info).takeUnretainedValue()

        let cfPaths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue()
        guard let paths = cfPaths as? [String] else { return }
        let flagsBuf = UnsafeBufferPointer(start: eventFlags, count: numEvents)

        let relevantMask =
            FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated) |
            FSEventStreamEventFlags(kFSEventStreamEventFlagItemRenamed) |
            FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified)

        var candidates: [String] = []
        candidates.reserveCapacity(min(numEvents, paths.count))
        for i in 0..<min(numEvents, paths.count) {
            if flagsBuf[i] & relevantMask != 0 {
                candidates.append(paths[i])
            }
        }
        if candidates.isEmpty { return }

        let mountPath = watcher.mountPath
        Task { @MainActor in
            FSEventsWatcher.processLiveEvents(candidates: candidates, mountPath: mountPath)
        }
    }

    @MainActor
    private static func processLiveEvents(candidates: [String], mountPath: String) {
        let state = AppState.shared
        guard state.isWatching else { return }
        guard let volume = state.volumes.first(where: { $0.mountPath == mountPath }),
              volume.isEnabled, !volume.isEjected else { return }

        // Snapshot rules + settings on the main actor, then do the actual
        // filesystem work on a background queue so the UI thread isn't blocked
        // by removeItem syscalls during high-volume FSEvents bursts.
        let rules = state.rules
        let settings = FileJanitor.DeletionSettings(
            moveToTrash: state.moveToTrash,
            maxFileSizeBytes: state.maxFileSizeBytes
        )
        Task.detached(priority: .utility) {
            var collected: [DeletionEvent] = []
            for path in candidates {
                if let rule = RuleEngine.evaluate(path: path, rules: rules),
                   let event = FileJanitor.delete(path: path, rule: rule,
                                                  volume: volume, settings: settings) {
                    collected.append(event)
                }
            }
            guard !collected.isEmpty else { return }
            let finalEvents = collected
            await MainActor.run {
                AppState.shared.recordBatch(finalEvents)
                if finalEvents.contains(where: { $0.status == .deleted }) {
                    AppState.shared.flashStatusIcon()
                }
            }
        }
    }
}
