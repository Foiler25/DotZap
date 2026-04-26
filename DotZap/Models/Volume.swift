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
        lastSeenAt: Date = Date()
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
    }
}
