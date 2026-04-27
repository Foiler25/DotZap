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
import AppIntents

/// AppIntents-facing representation of a watched volume. Identifier is the
/// mount path (stable, unique, matches `Volume.mountPath` in the model). The
/// display title is the human-readable volume name.
struct VolumeEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Volume")
    }

    static var defaultQuery = VolumeEntityQuery()

    let id: String      // mount path
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

/// Returns the set of currently-known DotZap volumes for the Shortcuts.app
/// volume picker. Excludes ejected volumes — there's no point letting a
/// shortcut target a drive that isn't mounted.
struct VolumeEntityQuery: EntityQuery {
    func entities(for identifiers: [VolumeEntity.ID]) async throws -> [VolumeEntity] {
        let volumes = await MainActor.run { AppState.shared.volumes }
        return volumes
            .filter { identifiers.contains($0.mountPath) }
            .map { VolumeEntity(id: $0.mountPath, name: $0.name) }
    }

    func suggestedEntities() async throws -> [VolumeEntity] {
        let volumes = await MainActor.run {
            AppState.shared.volumes.filter { !$0.isEjected }
        }
        return volumes.map { VolumeEntity(id: $0.mountPath, name: $0.name) }
    }
}
