import Foundation
import Darwin
import os.log

enum FileJanitor {
    private static let log = OSLog(subsystem: "com.Loofa.DotZap", category: "FileJanitor")

    /// Paths inside any of these directory names are owned by root (or another uid)
    /// even on volumes where the rest of the tree is user-owned. We can't delete
    /// inside them without privilege escalation, so don't try.
    private static let protectedAncestors: [String] = [
        "/.TemporaryItems/",
        "/.Spotlight-V100/",
        "/.Trashes/",
        "/.fseventsd/",
        "/.DocumentRevisions-V100/",
    ]

    private static let skipLock = NSLock()
    private static var skippedPaths: Set<String> = []

    @discardableResult
    static func delete(path: String, rule: CleanRule, volume: Volume) -> DeletionEvent? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else { return nil }

        if isInProtectedAncestor(path) { return nil }
        if isSkipped(path) { return nil }
        if volume.whitelist.contains(where: { fnmatch($0, path, 0) == 0 }) { return nil }

        let size: Int
        if let attrs = try? fm.attributesOfItem(atPath: path),
           let n = attrs[.size] as? NSNumber {
            size = n.intValue
        } else {
            size = 0
        }

        do {
            try fm.removeItem(atPath: path)
            return DeletionEvent(
                path: path,
                ruleName: rule.name,
                bytes: size,
                volumeName: volume.name
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
        for needle in protectedAncestors where path.contains(needle) {
            return true
        }
        return false
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
