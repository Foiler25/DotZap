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
import os.log

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    private static let log = OSLog(subsystem: "com.Loofa.DotZap", category: "AppState")

    /// Bumped when on-disk Codable shapes change in a backward-incompatible way.
    /// Currently informational; future migrations key off this.
    static let schemaVersion = 1

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

    /// Mount paths with a cleanup scan / xattr strip currently in flight.
    /// Runtime-only (never persisted) — the work runs in detached tasks that
    /// outlive any particular view, so progress indicators must live here
    /// rather than in view @State, which dies on panel close or tab switch.
    @Published var scanningVolumes: Set<String> = []
    @Published var strippingVolumes: Set<String> = []

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
            // Migrate before merge so the built-in `Apple Double` rule's
            // dedup key (now `._*|glob`) matches the new default and merge
            // doesn't append a duplicate.
            migrateLegacyPrefixRules()
            mergeMissingBuiltIns()
        }

        pruneStaleVolumes()
        pruneTransientVolumes()
        markVolumesEjectedAtStartup()
    }

    /// Drop create-dmg staging mounts registered by 1.3.0/1.3.1 (which
    /// didn't skip them yet). They're throwaway by construction — no point
    /// carrying them as ejected entries for a week.
    private func pruneTransientVolumes() {
        let before = volumes.count
        volumes.removeAll { $0.mountPath.hasPrefix("/Volumes/dmg.") }
        if volumes.count != before { persistVolumes() }
    }

    /// 1.2.6 changed `prefix` matching from "strip all `*`s then hasPrefix"
    /// to a literal hasPrefix. Any existing prefix rule containing `*` would
    /// now match nothing (or only literal-`*` filenames), so promote them to
    /// `.glob` — closest preservation of the original intent. Includes the
    /// built-in `Apple Double` rule (`._*` + prefix → `._*` + glob).
    private func migrateLegacyPrefixRules() {
        var changed = false
        for index in rules.indices {
            if rules[index].matchType == .prefix,
               rules[index].pattern.contains("*") {
                rules[index].matchType = .glob
                changed = true
                os_log("migrated legacy prefix rule %{public}@ to glob",
                       log: Self.log, type: .info, rules[index].pattern)
            }
        }
        if changed { persistRules() }
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
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            // Surface schema breakage — silent failure used to wipe user data
            // (rules, volumes, whitelists) on any incompatible model change.
            // Sidecar the bad blob so future migration code (or a worried
            // user) can recover it.
            os_log("decode failed for key %{public}@: %{public}@",
                   log: Self.log, type: .error, key, "\(error)")
            let sidecar = "\(key).corrupted-\(Int(Date().timeIntervalSince1970))"
            UserDefaults.standard.set(data, forKey: sidecar)
            return nil
        }
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
        // Sweep older ejected entries on every disappearance — without this,
        // the prune only ran at app launch, so a long-lived `.accessory`
        // process would accumulate dead volumes indefinitely.
        pruneStaleVolumes()
    }

    func setVolumeEnabled(mountPath: String, enabled: Bool) {
        guard let index = volumes.firstIndex(where: { $0.mountPath == mountPath }) else { return }
        volumes[index].isEnabled = enabled
        persistVolumes()
        if enabled {
            VolumeWatcher.shared.startMonitoring(mountPath: mountPath)
            // An interval timer's first fire is a full interval away and an
            // FSEvents stream only sees *new* files — without this kick, a
            // freshly enabled volume looks inert (junk already on it stays
            // put for up to the whole interval).
            if isWatching, volumes[index].cleanupMode != .manual {
                VolumeWatcher.shared.cleanNow(mountPath: mountPath)
            }
        } else {
            VolumeWatcher.shared.stopMonitoring(mountPath: mountPath)
        }
    }

    func setVolumeCleanupMode(mountPath: String, mode: Volume.CleanupMode) {
        guard let index = volumes.firstIndex(where: { $0.mountPath == mountPath }),
              volumes[index].cleanupMode != mode else { return }
        volumes[index].cleanupMode = mode
        persistVolumes()
        VolumeWatcher.shared.restartMonitoring(mountPath: mountPath)
        // Same reasoning as setVolumeEnabled: entering an active mode should
        // clean immediately, then keep to its schedule.
        if isWatching, mode != .manual, volumes[index].isEnabled, !volumes[index].isEjected {
            VolumeWatcher.shared.cleanNow(mountPath: mountPath)
        }
    }

    func setVolumeCleanupInterval(mountPath: String, minutes: Int) {
        let clamped = max(1, minutes)
        guard let index = volumes.firstIndex(where: { $0.mountPath == mountPath }),
              volumes[index].cleanupIntervalMinutes != clamped else { return }
        volumes[index].cleanupIntervalMinutes = clamped
        persistVolumes()
        if volumes[index].cleanupMode == .interval {
            VolumeWatcher.shared.restartMonitoring(mountPath: mountPath)
        }
    }

    /// Forget an ejected volume: drops it (and its whitelist, stats, and
    /// cleanup settings) from the list. Mounted volumes can't be removed —
    /// they'd just re-register on the next mount event anyway.
    func removeVolume(mountPath: String) {
        guard let index = volumes.firstIndex(where: { $0.mountPath == mountPath }),
              volumes[index].isEjected else { return }
        volumes.remove(at: index)
        persistVolumes()
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
        // Prefix mode is a literal hasPrefix check — `*` would silently mismatch
        // user expectations. The UI also guards this, but defend in depth.
        guard !(matchType == .prefix && cleanPattern.contains("*")) else { return }
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

            // Resolve each event to a volumes-array index up front, keyed by
            // mountPath when present (events from 1.2.6+) or falling back to
            // volumeName (events persisted by older versions). Aggregating by
            // index avoids the name-collision bug where two drives both named
            // "Untitled" had their stats merged onto the first one found.
            var volumeDeltas: [Int: (count: Int, bytes: Int)] = [:]
            for event in deletedEvents {
                let index: Int?
                if !event.volumeMountPath.isEmpty {
                    index = volumes.firstIndex { $0.mountPath == event.volumeMountPath }
                } else {
                    index = volumes.firstIndex { $0.name == event.volumeName }
                }
                guard let i = index else { continue }
                var d = volumeDeltas[i] ?? (0, 0)
                d.count += 1
                d.bytes += event.bytes
                volumeDeltas[i] = d
            }
            for (index, delta) in volumeDeltas {
                volumes[index].lifetimeFilesDeleted += delta.count
                volumes[index].lifetimeBytesFreed   += delta.bytes
            }
            if !volumeDeltas.isEmpty { markDirty(.volumes) }
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
