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
import Combine
import AppKit

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    private enum Keys {
        static let isWatching          = "DotZap.isWatching"
        static let volumes             = "DotZap.volumes"
        static let rules               = "DotZap.rules"
        static let recentEvents        = "DotZap.recentEvents"
        static let lifetimeFilesDeleted = "DotZap.lifetimeFilesDeleted"
        static let lifetimeBytesFreed  = "DotZap.lifetimeBytesFreed"
        static let didSeedBuiltIns     = "DotZap.didSeedBuiltIns"
        static let launchAtLogin       = "DotZap.launchAtLogin"
        static let moveToTrash         = "DotZap.moveToTrash"
        static let maxFileSizeBytes    = "DotZap.maxFileSizeBytes"
    }

    private static let maxEvents = 500
    private static let ejectedPruneInterval: TimeInterval = 60 * 60 * 24 * 7
    private static let persistDebounce: TimeInterval = 0.75
    static let defaultMaxFileSizeBytes: Int = 50 * 1024 * 1024  // 50 MB

    @Published var isWatching: Bool = true
    @Published var volumes: [Volume] = []
    @Published var rules: [CleanRule] = []
    @Published var recentEvents: [DeletionEvent] = []
    @Published var lifetimeFilesDeleted: Int = 0
    @Published var lifetimeBytesFreed: Int = 0
    @Published var moveToTrash: Bool = true
    @Published var maxFileSizeBytes: Int = AppState.defaultMaxFileSizeBytes

    private var hasLoaded = false

    private struct DirtyBits: OptionSet {
        let rawValue: Int
        static let events    = DirtyBits(rawValue: 1 << 0)
        static let volumes   = DirtyBits(rawValue: 1 << 1)
        static let stats     = DirtyBits(rawValue: 1 << 2)
        static let rules     = DirtyBits(rawValue: 1 << 3)
        static let watching  = DirtyBits(rawValue: 1 << 4)
        static let settings  = DirtyBits(rawValue: 1 << 5)
    }
    private var dirty: DirtyBits = []
    private var flushTimer: Timer?

    private init() {}

    // MARK: - Persistence

    func loadPersisted() {
        guard !hasLoaded else { return }
        hasLoaded = true

        let defaults = UserDefaults.standard

        if defaults.object(forKey: Keys.isWatching) != nil {
            isWatching = defaults.bool(forKey: Keys.isWatching)
        }
        if defaults.object(forKey: Keys.moveToTrash) != nil {
            moveToTrash = defaults.bool(forKey: Keys.moveToTrash)
        }
        if defaults.object(forKey: Keys.maxFileSizeBytes) != nil {
            let stored = defaults.integer(forKey: Keys.maxFileSizeBytes)
            // Treat zero/negative as "unbounded" by clamping to a very large value.
            maxFileSizeBytes = stored > 0 ? stored : Int.max
        }
        lifetimeFilesDeleted = defaults.integer(forKey: Keys.lifetimeFilesDeleted)
        lifetimeBytesFreed   = defaults.integer(forKey: Keys.lifetimeBytesFreed)
        volumes      = decode([Volume].self, key: Keys.volumes) ?? []
        recentEvents = decode([DeletionEvent].self, key: Keys.recentEvents) ?? []
        rules        = decode([CleanRule].self, key: Keys.rules) ?? []

        if !defaults.bool(forKey: Keys.didSeedBuiltIns) {
            rules = CleanRule.builtInDefaults
            defaults.set(true, forKey: Keys.didSeedBuiltIns)
            persistRules()
        } else {
            mergeMissingBuiltIns()
        }

        pruneStaleVolumes()
        markVolumesEjectedAtStartup()
    }

    private func mergeMissingBuiltIns() {
        let existingPatterns = Set(rules.filter(\.isBuiltIn).map { "\($0.pattern)|\($0.matchType.rawValue)" })
        var added = false
        for builtIn in CleanRule.builtInDefaults {
            let key = "\(builtIn.pattern)|\(builtIn.matchType.rawValue)"
            if !existingPatterns.contains(key) {
                rules.append(builtIn)
                added = true
            }
        }
        if added { persistRules() }
    }

    private func pruneStaleVolumes() {
        let cutoff = Date().addingTimeInterval(-Self.ejectedPruneInterval)
        let before = volumes.count
        volumes.removeAll { $0.isEjected && $0.lastSeenAt < cutoff }
        if volumes.count != before { persistVolumes() }
    }

    private func markVolumesEjectedAtStartup() {
        for index in volumes.indices {
            volumes[index].isEjected = true
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func encode<T: Encodable>(_ value: T) -> Data? {
        try? JSONEncoder().encode(value)
    }

    func persistVolumes()       { markDirty(.volumes) }
    func persistRules()         { markDirty(.rules) }
    func persistEvents()        { markDirty(.events) }
    func persistLifetimeStats() { markDirty(.stats) }
    func persistIsWatching()    { markDirty(.watching) }
    func persistSettings()      { markDirty(.settings) }

    /// Coalesce UserDefaults writes onto a debounce timer so high-frequency
    /// FSEvents-driven deletions don't generate a write storm. Calls that
    /// happen within `persistDebounce` collapse into a single flush.
    private func markDirty(_ bits: DirtyBits) {
        dirty.formUnion(bits)
        guard flushTimer == nil else { return }
        flushTimer = Timer.scheduledTimer(
            withTimeInterval: Self.persistDebounce, repeats: false
        ) { [weak self] _ in
            Task { @MainActor in self?.flushDirty() }
        }
    }

    private func flushDirty() {
        flushTimer?.invalidate()
        flushTimer = nil
        let bits = dirty
        dirty = []
        let defaults = UserDefaults.standard
        if bits.contains(.events), let data = encode(recentEvents) {
            defaults.set(data, forKey: Keys.recentEvents)
        }
        if bits.contains(.volumes), let data = encode(volumes) {
            defaults.set(data, forKey: Keys.volumes)
        }
        if bits.contains(.rules), let data = encode(rules) {
            defaults.set(data, forKey: Keys.rules)
        }
        if bits.contains(.stats) {
            defaults.set(lifetimeFilesDeleted, forKey: Keys.lifetimeFilesDeleted)
            defaults.set(lifetimeBytesFreed, forKey: Keys.lifetimeBytesFreed)
        }
        if bits.contains(.watching) {
            defaults.set(isWatching, forKey: Keys.isWatching)
        }
        if bits.contains(.settings) {
            defaults.set(moveToTrash, forKey: Keys.moveToTrash)
            defaults.set(maxFileSizeBytes, forKey: Keys.maxFileSizeBytes)
        }
    }

    /// Force-flush any pending debounced writes immediately. Call before quit
    /// or for actions where the user expects state to be persisted right away.
    func flushPendingWrites() {
        guard !dirty.isEmpty else { return }
        flushDirty()
    }

    // MARK: - Mutations

    func toggle() {
        isWatching.toggle()
        persistIsWatching()
        if isWatching {
            VolumeWatcher.shared.resumeAll()
        } else {
            VolumeWatcher.shared.pauseAll()
        }
        StatusBarController.shared.refreshIcon()
    }

    func startWatchingIfEnabled() {
        if isWatching {
            VolumeWatcher.shared.resumeAll()
        }
    }

    func upsertVolume(_ volume: Volume) {
        if let index = volumes.firstIndex(where: { $0.mountPath == volume.mountPath }) {
            var preserved = volumes[index]
            preserved.name        = volume.name
            preserved.filesystem  = volume.filesystem
            preserved.isNetwork   = volume.isNetwork
            preserved.isEjected   = false
            preserved.lastSeenAt  = Date()
            volumes[index] = preserved
        } else {
            volumes.append(volume)
        }
        persistVolumes()
    }

    func markVolumeEjected(mountPath: String) {
        guard let index = volumes.firstIndex(where: { $0.mountPath == mountPath }) else { return }
        volumes[index].isEjected = true
        volumes[index].lastSeenAt = Date()
        persistVolumes()
    }

    func setVolumeEnabled(mountPath: String, enabled: Bool) {
        guard let index = volumes.firstIndex(where: { $0.mountPath == mountPath }) else { return }
        volumes[index].isEnabled = enabled
        persistVolumes()
        if enabled {
            VolumeWatcher.shared.startWatching(mountPath: mountPath)
        } else {
            VolumeWatcher.shared.stopWatching(mountPath: mountPath)
        }
    }

    func setVolumeDryRun(mountPath: String, dryRun: Bool) {
        guard let index = volumes.firstIndex(where: { $0.mountPath == mountPath }) else { return }
        volumes[index].dryRun = dryRun
        persistVolumes()
    }

    func addWhitelistEntry(mountPath: String, pattern: String) {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = volumes.firstIndex(where: { $0.mountPath == mountPath }) else { return }
        if !volumes[index].whitelist.contains(trimmed) {
            volumes[index].whitelist.append(trimmed)
            persistVolumes()
        }
    }

    func removeWhitelistEntry(mountPath: String, pattern: String) {
        guard let index = volumes.firstIndex(where: { $0.mountPath == mountPath }) else { return }
        volumes[index].whitelist.removeAll { $0 == pattern }
        persistVolumes()
    }

    func addCustomRule(name: String, pattern: String, matchType: CleanRule.MatchType) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPattern = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, !cleanPattern.isEmpty else { return }
        rules.append(CleanRule(name: cleanName, pattern: cleanPattern, matchType: matchType, isBuiltIn: false))
        persistRules()
    }

    func deleteRule(id: UUID) {
        rules.removeAll { $0.id == id && !$0.isBuiltIn }
        persistRules()
    }

    func setRuleEnabled(id: UUID, enabled: Bool) {
        guard let index = rules.firstIndex(where: { $0.id == id }) else { return }
        rules[index].isEnabled = enabled
        persistRules()
    }

    func record(_ event: DeletionEvent) {
        recordBatch([event])
    }

    /// Ingest a batch of deletions in a single state mutation. Cheaper than
    /// calling `record(_:)` per item: SwiftUI invalidates once, the dirty-bit
    /// timer is armed once, and `volumes` mutates once even when many events
    /// share the same volume.
    ///
    /// Lifetime stats only count events whose `status == .deleted`. Skipped
    /// (e.g. oversize) events still appear in the Activity log so the user
    /// can see what was held back.
    func recordBatch(_ events: [DeletionEvent]) {
        guard !events.isEmpty else { return }

        recentEvents.insert(contentsOf: events, at: 0)
        if recentEvents.count > Self.maxEvents {
            recentEvents.removeLast(recentEvents.count - Self.maxEvents)
        }

        let deletedEvents = events.filter { $0.status == .deleted }
        if !deletedEvents.isEmpty {
            lifetimeFilesDeleted += deletedEvents.count
            lifetimeBytesFreed   += deletedEvents.reduce(0) { $0 + $1.bytes }

            var volumeTouched = false
            var volumeDeltas: [String: (count: Int, bytes: Int)] = [:]
            for event in deletedEvents {
                var d = volumeDeltas[event.volumeName] ?? (0, 0)
                d.count += 1
                d.bytes += event.bytes
                volumeDeltas[event.volumeName] = d
            }
            for (volumeName, delta) in volumeDeltas {
                if let index = volumes.firstIndex(where: { $0.name == volumeName }) {
                    volumes[index].lifetimeFilesDeleted += delta.count
                    volumes[index].lifetimeBytesFreed   += delta.bytes
                    volumeTouched = true
                }
            }
            if volumeTouched { markDirty(.volumes) }
            markDirty(.stats)
        }
        markDirty(.events)
    }

    func clearActivity() {
        recentEvents.removeAll()
        lifetimeFilesDeleted = 0
        lifetimeBytesFreed   = 0
        for index in volumes.indices {
            volumes[index].lifetimeFilesDeleted = 0
            volumes[index].lifetimeBytesFreed   = 0
        }
        persistEvents()
        persistLifetimeStats()
        persistVolumes()
    }

    // MARK: - UI helpers

    func flashStatusIcon() {
        StatusBarController.shared.flash()
    }
}
