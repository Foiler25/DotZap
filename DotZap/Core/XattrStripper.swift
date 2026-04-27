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

/// Walks a directory and clears every extended attribute it finds. Called from
/// the UI's "Strip extended attributes…" button on a volume row. Synchronous
/// — invoke from a background queue for any non-trivial volume.
///
/// The reason this exists: macOS re-creates `._*` AppleDouble sidecars on
/// non-APFS filesystems (exFAT, FAT32, NTFS) every time a file with extended
/// attributes is written. Cleaning the sidecars only treats the symptom.
/// Stripping the source xattrs is the durable fix.
enum XattrStripper {
    private static let log = OSLog(subsystem: "com.Loofa.DotZap", category: "XattrStripper")

    struct Result {
        let filesProcessed: Int
        let filesModified: Int   // files where at least one xattr was removed
        let xattrsRemoved: Int
        let errors: Int
    }

    /// Strip all extended attributes from every regular file under `root`.
    /// Returns counts for the post-run summary. Errors are tallied but do
    /// not abort the walk — best-effort is the right semantics here.
    static func strip(at root: String) -> Result {
        var processed = 0
        var modified = 0
        var removed = 0
        var errors = 0

        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: root) else {
            return Result(filesProcessed: 0, filesModified: 0,
                          xattrsRemoved: 0, errors: 1)
        }

        while let relPath = enumerator.nextObject() as? String {
            let fullPath = (root as NSString).appendingPathComponent(relPath)
            processed += 1

            // listxattr with NULL/0 returns the size needed to hold all names.
            let needed = listxattr(fullPath, nil, 0, XATTR_NOFOLLOW)
            if needed <= 0 { continue }   // 0 = no xattrs, <0 = error (skip)

            var buffer = [CChar](repeating: 0, count: needed)
            let actual = listxattr(fullPath, &buffer, needed, XATTR_NOFOLLOW)
            if actual <= 0 { continue }

            // The buffer is a sequence of NUL-terminated names. Split.
            let data = Data(bytes: buffer, count: actual)
            let names = data.split(separator: 0).compactMap {
                String(data: Data($0), encoding: .utf8)
            }
            guard !names.isEmpty else { continue }

            var anyRemoved = false
            for name in names {
                if removexattr(fullPath, name, XATTR_NOFOLLOW) == 0 {
                    removed += 1
                    anyRemoved = true
                } else {
                    errors += 1
                }
            }
            if anyRemoved { modified += 1 }
        }

        os_log("xattr strip on %{public}@: processed=%d modified=%d removed=%d errors=%d",
               log: log, type: .info, root, processed, modified, removed, errors)

        return Result(filesProcessed: processed, filesModified: modified,
                      xattrsRemoved: removed, errors: errors)
    }
}
