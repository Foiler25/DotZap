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

struct Volume: Codable, Identifiable, Hashable {
    /// How junk gets cleaned off this volume.
    ///
    /// `.realtime` uses FSEvents to delete files the moment they appear.
    /// On network volumes FSEvents only reports changes made *from this
    /// Mac* — remote writers are invisible — which is why network volumes
    /// default to `.interval` instead.
    enum CleanupMode: String, Codable, CaseIterable, Identifiable {
        case realtime   // FSEvents live watching
        case interval   // periodic full-volume scans
        case manual     // only when the user runs Clean Now

        var id: String { rawValue }

        var label: String {
            switch self {
            case .realtime: return "Live"
            case .interval: return "Interval"
            case .manual:   return "Manual"
            }
        }
    }

    static let defaultCleanupIntervalMinutes = 30

    var mountPath: String
    var name: String
    var filesystem: String
    var isEnabled: Bool
    var isEjected: Bool
    var isNetwork: Bool
    var whitelist: [String]
    var lifetimeFilesDeleted: Int
    var lifetimeBytesFreed: Int
    var lastSeenAt: Date
    var dryRun: Bool
    var cleanupMode: CleanupMode
    var cleanupIntervalMinutes: Int

    var id: String { mountPath }

    init(
        mountPath: String,
        name: String,
        filesystem: String,
        isEnabled: Bool = true,
        isEjected: Bool = false,
        isNetwork: Bool = false,
        whitelist: [String] = [],
        lifetimeFilesDeleted: Int = 0,
        lifetimeBytesFreed: Int = 0,
        lastSeenAt: Date = Date(),
        dryRun: Bool = false,
        cleanupMode: CleanupMode = .realtime,
        cleanupIntervalMinutes: Int = Volume.defaultCleanupIntervalMinutes
    ) {
        self.mountPath = mountPath
        self.name = name
        self.filesystem = filesystem
        self.isEnabled = isEnabled
        self.isEjected = isEjected
        self.isNetwork = isNetwork
        self.whitelist = whitelist
        self.lifetimeFilesDeleted = lifetimeFilesDeleted
        self.lifetimeBytesFreed = lifetimeBytesFreed
        self.lastSeenAt = lastSeenAt
        self.dryRun = dryRun
        self.cleanupMode = cleanupMode
        self.cleanupIntervalMinutes = cleanupIntervalMinutes
    }

    // Back-compat decoder so volumes persisted by 1.2.0 (no `dryRun` field)
    // and pre-1.3.0 (no cleanup mode fields) still load after upgrade.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.mountPath            = try c.decode(String.self,   forKey: .mountPath)
        self.name                 = try c.decode(String.self,   forKey: .name)
        self.filesystem           = try c.decode(String.self,   forKey: .filesystem)
        self.isEnabled            = try c.decode(Bool.self,     forKey: .isEnabled)
        self.isEjected            = try c.decode(Bool.self,     forKey: .isEjected)
        self.isNetwork            = try c.decode(Bool.self,     forKey: .isNetwork)
        self.whitelist            = try c.decode([String].self, forKey: .whitelist)
        self.lifetimeFilesDeleted = try c.decode(Int.self,      forKey: .lifetimeFilesDeleted)
        self.lifetimeBytesFreed   = try c.decode(Int.self,      forKey: .lifetimeBytesFreed)
        self.lastSeenAt           = try c.decode(Date.self,     forKey: .lastSeenAt)
        self.dryRun               = try c.decodeIfPresent(Bool.self, forKey: .dryRun) ?? false
        self.cleanupMode          = try c.decodeIfPresent(CleanupMode.self, forKey: .cleanupMode) ?? .realtime
        self.cleanupIntervalMinutes = try c.decodeIfPresent(Int.self, forKey: .cleanupIntervalMinutes)
            ?? Volume.defaultCleanupIntervalMinutes
    }
}
