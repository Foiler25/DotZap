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
import Darwin
import os.log

enum FileJanitor {
    private static let log = OSLog(subsystem: "com.Loofa.DotZap", category: "FileJanitor")

    /// Snapshot of mutable user settings read on the main actor before
    /// dispatching deletion work to a background queue. Pass-by-value so the
    /// background worker doesn't have to hop back to MainActor for each file.
    struct DeletionSettings: Sendable {
        let moveToTrash: Bool
        let maxFileSizeBytes: Int

        static let permissive = DeletionSettings(moveToTrash: false,
                                                  maxFileSizeBytes: .max)
    }

    /// Paths whose path *components* include any of these directory names are
    /// owned by root (or another uid) even on volumes where the rest of the
    /// tree is user-owned. We can't delete inside them without privilege
    /// escalation, so don't try.
    ///
    /// Compared component-wise (not as substrings) so that paths like
    /// `/Volumes/USB/.Spotlight-V100-backup/x` aren't falsely protected, and
    /// volumes mounted at `/Volumes/.Spotlight-V100/...` aren't catastrophically
    /// treated as entirely protected.
    private static let protectedAncestors: Set<String> = [
        ".TemporaryItems",
        ".Spotlight-V100",
        ".Trashes",
        ".fseventsd",
        ".DocumentRevisions-V100",
    ]

    private static let skipLock = NSLock()
    private static var skippedPaths: Set<String> = []

    @discardableResult
    static func delete(
        path: String,
        rule: CleanRule,
        volume: Volume,
        settings: DeletionSettings
    ) -> DeletionEvent? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else { return nil }

        if isInProtectedAncestor(path) { return nil }
        if isSkipped(path) { return nil }
        if volume.whitelist.contains(where: { fnmatch($0, path, 0) == 0 }) { return nil }

        // lstat (does NOT follow symlinks) — used both to detect symlinks and
        // to read size without invoking Foundation's symlink-following
        // attributesOfItem(atPath:).
        var statBuf = stat()
        guard lstat(path, &statBuf) == 0 else {
            // Path vanished between fileExists and lstat. Quiet exit.
            return nil
        }
        let isSymlink = (statBuf.st_mode & S_IFMT) == S_IFLNK
        let size: Int = isSymlink ? 0 : Int(statBuf.st_size)

        // Size cap — emit a skipped event so the user can see what was held
        // back, but don't actually delete or trash. Lifetime stats ignore
        // skipped events (filtered in AppState.recordBatch). Symlinks are
        // tiny inodes; the cap doesn't apply.
        if !isSymlink && size > settings.maxFileSizeBytes {
            return DeletionEvent(
                path: path,
                ruleName: rule.name,
                bytes: size,
                volumeName: volume.name,
                volumeMountPath: volume.mountPath,
                status: .skippedOversize
            )
        }

        // Dry-run mode — emit an event showing what *would* have been deleted,
        // but leave the file in place. Lifetime stats also ignore these.
        if volume.dryRun {
            return DeletionEvent(
                path: path,
                ruleName: rule.name,
                bytes: size,
                volumeName: volume.name,
                volumeMountPath: volume.mountPath,
                status: .dryRun
            )
        }

        // Symlinks: unlink the link itself, never resolve to its target.
        // FileManager.trashItem and removeItem follow symlinks; with FDA we
        // would otherwise trash an attacker-chosen target.
        if isSymlink {
            if unlink(path) == 0 {
                return DeletionEvent(
                    path: path,
                    ruleName: rule.name,
                    bytes: 0,
                    volumeName: volume.name,
                    volumeMountPath: volume.mountPath,
                    status: .deleted
                )
            }
            let err = errno
            if err == EACCES || err == EPERM {
                markSkipped(path)
                os_log("skipping protected symlink: %{public}@",
                       log: log, type: .info, path)
            } else {
                os_log("unlink failed for symlink %{public}@: errno=%d",
                       log: log, type: .error, path, err)
            }
            return nil
        }

        // Regular file: resolve and verify the resolved path is still inside
        // the watched volume. This narrows the symlink-swap TOCTOU window
        // without fully closing it (a fully race-free fix would require
        // openat(O_NOFOLLOW)+funlinkat, which Foundation doesn't expose).
        guard let resolvedC = realpath(path, nil) else {
            os_log("realpath failed for %{public}@: errno=%d",
                   log: log, type: .error, path, errno)
            return nil
        }
        let resolvedPath = String(cString: resolvedC)
        free(resolvedC)
        let mountPrefix = volume.mountPath.hasSuffix("/")
            ? volume.mountPath
            : volume.mountPath + "/"
        guard resolvedPath == volume.mountPath
              || resolvedPath.hasPrefix(mountPrefix) else {
            os_log("refusing delete: %{public}@ resolved to %{public}@ outside volume %{public}@",
                   log: log, type: .error, path, resolvedPath, volume.mountPath)
            return nil
        }

        do {
            if settings.moveToTrash {
                do {
                    try fm.trashItem(at: URL(fileURLWithPath: path),
                                     resultingItemURL: nil)
                } catch let error as NSError
                    where error.domain == NSCocoaErrorDomain
                       && error.code == CocoaError.featureUnsupported.rawValue {
                    // Network shares (and some FAT volumes) have no per-user
                    // .Trashes, so trashItem always throws 3328 there. Finder
                    // deletes immediately on such volumes; do the same instead
                    // of silently failing on every file.
                    try fm.removeItem(atPath: path)
                }
            } else {
                try fm.removeItem(atPath: path)
            }
            return DeletionEvent(
                path: path,
                ruleName: rule.name,
                bytes: size,
                volumeName: volume.name,
                volumeMountPath: volume.mountPath,
                status: .deleted
            )
        } catch let error as NSError {
            if isPermissionError(error) {
                markSkipped(path)
                os_log("skipping protected path: %{public}@",
                       log: log, type: .info, path)
            } else {
                os_log("delete failed for %{public}@: %{public}@",
                       log: log, type: .error, path, error.localizedDescription)
            }
            return nil
        }
    }

    static func resetSkipSet() {
        skipLock.lock(); defer { skipLock.unlock() }
        skippedPaths.removeAll()
    }

    // MARK: - Helpers

    private static func isInProtectedAncestor(_ path: String) -> Bool {
        let components = (path as NSString).pathComponents
        return components.contains(where: protectedAncestors.contains)
    }

    private static func isSkipped(_ path: String) -> Bool {
        skipLock.lock(); defer { skipLock.unlock() }
        return skippedPaths.contains(path)
    }

    private static func markSkipped(_ path: String) {
        skipLock.lock(); defer { skipLock.unlock() }
        skippedPaths.insert(path)
    }

    private static func isPermissionError(_ error: NSError) -> Bool {
        // NSFileWriteNoPermissionError = 513, NSFileReadNoPermissionError = 257
        if error.domain == NSCocoaErrorDomain, error.code == 513 || error.code == 257 {
            return true
        }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError,
           underlying.domain == NSPOSIXErrorDomain {
            return underlying.code == Int(EACCES) || underlying.code == Int(EPERM)
        }
        if error.domain == NSPOSIXErrorDomain {
            return error.code == Int(EACCES) || error.code == Int(EPERM)
        }
        return false
    }
}
