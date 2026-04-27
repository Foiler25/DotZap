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

// MARK: - Global toggles

struct PauseDotZapIntent: AppIntent {
    static var title: LocalizedStringResource = "Pause DotZap"
    static var description = IntentDescription(
        "Stops DotZap from cleaning files on any volume until resumed."
    )

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            if AppState.shared.isWatching {
                AppState.shared.toggle()
            }
        }
        return .result()
    }
}

struct ResumeDotZapIntent: AppIntent {
    static var title: LocalizedStringResource = "Resume DotZap"
    static var description = IntentDescription(
        "Resumes cleaning on every enabled volume."
    )

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            if !AppState.shared.isWatching {
                AppState.shared.toggle()
            }
        }
        return .result()
    }
}

struct ToggleDotZapIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle DotZap"
    static var description = IntentDescription(
        "Pauses if running, resumes if paused."
    )

    func perform() async throws -> some IntentResult {
        await MainActor.run { AppState.shared.toggle() }
        return .result()
    }
}

// MARK: - Volume actions

struct CleanVolumeIntent: AppIntent {
    static var title: LocalizedStringResource = "Clean Volume"
    static var description = IntentDescription(
        "Runs a one-shot cleanup scan on a chosen volume."
    )

    @Parameter(title: "Volume")
    var volume: VolumeEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Clean \(\.$volume)")
    }

    func perform() async throws -> some IntentResult {
        let mountPath = volume.id
        await MainActor.run {
            VolumeWatcher.shared.cleanNow(mountPath: mountPath)
        }
        return .result()
    }
}

struct StripXattrsIntent: AppIntent {
    static var title: LocalizedStringResource = "Strip Extended Attributes"
    static var description = IntentDescription(
        "Clears every extended attribute from every file on a volume. Stops `._*` files from regenerating on exFAT/FAT32. Removes Finder color tags, comments, and com.apple.metadata:* entries."
    )

    @Parameter(title: "Volume")
    var volume: VolumeEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Strip extended attributes on \(\.$volume)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let mountPath = volume.id
        let volumeName = volume.name
        let result = await Task.detached(priority: .userInitiated) {
            XattrStripper.strip(at: mountPath)
        }.value

        let summary: String
        if result.filesModified == 0 {
            summary = result.errors > 0
                ? "No xattrs cleared (\(result.errors) errors)"
                : "No extended attributes found"
        } else {
            summary = "Stripped xattrs from \(result.filesModified) "
                + (result.filesModified == 1 ? "file" : "files")
                + (result.errors > 0 ? " (\(result.errors) errors)" : "")
        }

        await MainActor.run {
            let event = DeletionEvent(
                path: mountPath,
                ruleName: summary,
                bytes: 0,
                volumeName: volumeName,
                status: .xattrStripped
            )
            AppState.shared.recordBatch([event])
        }

        return .result(value: summary)
    }
}

struct SetVolumeEnabledIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Volume Enabled"
    static var description = IntentDescription(
        "Enable or disable cleaning on a single volume without changing the global state."
    )

    @Parameter(title: "Volume")
    var volume: VolumeEntity

    @Parameter(title: "Enabled", default: true)
    var enabled: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Set \(\.$volume) cleaning to \(\.$enabled)")
    }

    func perform() async throws -> some IntentResult {
        let mountPath = volume.id
        let isEnabled = enabled
        await MainActor.run {
            AppState.shared.setVolumeEnabled(mountPath: mountPath, enabled: isEnabled)
        }
        return .result()
    }
}

// MARK: - Read-only

struct GetStatsIntent: AppIntent {
    static var title: LocalizedStringResource = "Get DotZap Stats"
    static var description = IntentDescription(
        "Returns the lifetime files cleaned and bytes freed as a formatted string."
    )

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let summary = await MainActor.run { () -> String in
            let files = AppState.shared.lifetimeFilesDeleted
            let bytes = AppState.shared.lifetimeBytesFreed
            let bytesString = ByteCountFormatter.string(
                fromByteCount: Int64(bytes), countStyle: .file
            )
            let filesString = files.formatted(.number)
            let suffix = files == 1 ? "file" : "files"
            return "\(filesString) \(suffix) cleaned, \(bytesString) freed"
        }
        return .result(value: summary)
    }
}

struct ListVolumesIntent: AppIntent {
    static var title: LocalizedStringResource = "List DotZap Volumes"
    static var description = IntentDescription(
        "Returns the names of currently-detected volumes, one per line. Ejected volumes are excluded."
    )

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let listing = await MainActor.run { () -> String in
            let volumes = AppState.shared.volumes.filter { !$0.isEjected }
            if volumes.isEmpty { return "No volumes detected" }
            return volumes.map(\.name).joined(separator: "\n")
        }
        return .result(value: listing)
    }
}
