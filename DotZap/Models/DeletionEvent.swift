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
    enum Status: String, Codable {
        case deleted          // actual deletion (or trash)
        case skippedOversize  // matched a rule but exceeded the size cap
        case dryRun           // matched a rule but volume is in dry-run mode
        case xattrStripped    // one-shot xattr strip on a volume (system event)
    }

    var id: UUID
    var path: String
    var ruleName: String
    var bytes: Int
    var volumeName: String
    /// Mount path of the volume this event came from. Used as the stable key
    /// for per-volume stat attribution — `volumeName` collides between
    /// drives that share a name (e.g. two USB sticks both labeled "Untitled").
    /// Empty string in events persisted before 1.2.6 (back-compat decoder).
    var volumeMountPath: String
    var timestamp: Date
    var status: Status

    var fileName: String {
        (path as NSString).lastPathComponent
    }

    init(
        id: UUID = UUID(),
        path: String,
        ruleName: String,
        bytes: Int,
        volumeName: String,
        volumeMountPath: String = "",
        timestamp: Date = Date(),
        status: Status = .deleted
    ) {
        self.id = id
        self.path = path
        self.ruleName = ruleName
        self.bytes = bytes
        self.volumeName = volumeName
        self.volumeMountPath = volumeMountPath
        self.timestamp = timestamp
        self.status = status
    }

    // Decoder with back-compat defaults so events persisted by older
    // versions still load: `status` was added in 1.2.0, `volumeMountPath`
    // in 1.2.6.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id              = try c.decode(UUID.self,   forKey: .id)
        self.path            = try c.decode(String.self, forKey: .path)
        self.ruleName        = try c.decode(String.self, forKey: .ruleName)
        self.bytes           = try c.decode(Int.self,    forKey: .bytes)
        self.volumeName      = try c.decode(String.self, forKey: .volumeName)
        self.volumeMountPath = try c.decodeIfPresent(String.self, forKey: .volumeMountPath) ?? ""
        self.timestamp       = try c.decode(Date.self,   forKey: .timestamp)
        self.status          = try c.decodeIfPresent(Status.self, forKey: .status) ?? .deleted
    }
}
