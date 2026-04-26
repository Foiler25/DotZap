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
    }

    private static let maxEvents = 500
    private static let ejectedPruneInterval: TimeInterval = 60 * 60 * 24 * 7

    @Published var isWatching: Bool = true
    @Published var volumes: [Volume] = []
    @Published var rules: [CleanRule] = []
    @Published var recentEvents: [DeletionEvent] = []
    @Published var lifetimeFilesDeleted: Int = 0
    @Published var lifetimeBytesFreed: Int = 0

    private var hasLoaded = false

    private init() {}

    // MARK: - Persistence

    func loadPersisted() {
        guard !hasLoaded else { return }
        hasLoaded = true

        let defaults = UserDefaults.standard

        if defaults.object(forKey: Keys.isWatching) != nil {
            isWatching = defaults.bool(forKey: Keys.isWatching)
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

    func persistVolumes() {
        if let data = encode(volumes) {
            UserDefaults.standard.set(data, forKey: Keys.volumes)
        }
    }

    func persistRules() {
        if let data = encode(rules) {
            UserDefaults.standard.set(data, forKey: Keys.rules)
        }
    }

    func persistEvents() {
        if let data = encode(recentEvents) {
            UserDefaults.standard.set(data, forKey: Keys.recentEvents)
        }
    }

    func persistLifetimeStats() {
        let defaults = UserDefaults.standard
        defaults.set(lifetimeFilesDeleted, forKey: Keys.lifetimeFilesDeleted)
        defaults.set(lifetimeBytesFreed, forKey: Keys.lifetimeBytesFreed)
    }

    func persistIsWatching() {
        UserDefaults.standard.set(isWatching, forKey: Keys.isWatching)
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
        recentEvents.insert(event, at: 0)
        if recentEvents.count > Self.maxEvents {
            recentEvents.removeLast(recentEvents.count - Self.maxEvents)
        }
        lifetimeFilesDeleted += 1
        lifetimeBytesFreed   += event.bytes

        if let index = volumes.firstIndex(where: { $0.name == event.volumeName }) {
            volumes[index].lifetimeFilesDeleted += 1
            volumes[index].lifetimeBytesFreed   += event.bytes
            persistVolumes()
        }

        persistEvents()
        persistLifetimeStats()
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
