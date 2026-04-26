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

struct DeletionEvent: Codable, Identifiable, Hashable {
    var id: UUID
    var path: String
    var ruleName: String
    var bytes: Int
    var volumeName: String
    var timestamp: Date

    var fileName: String {
        (path as NSString).lastPathComponent
    }

    init(
        id: UUID = UUID(),
        path: String,
        ruleName: String,
        bytes: Int,
        volumeName: String,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.path = path
        self.ruleName = ruleName
        self.bytes = bytes
        self.volumeName = volumeName
        self.timestamp = timestamp
    }
}
