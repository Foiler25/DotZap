import Foundation
import Darwin
import os.log

enum FileJanitor {
    private static let log = OSLog(subsystem: "com.Loofa.DotZap", category: "FileJanitor")

    @discardableResult
    static func delete(path: String, rule: CleanRule, volume: Volume) -> DeletionEvent? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else { return nil }

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
        } catch {
            os_log("delete failed for %{public}@: %{public}@",
                   log: log, type: .error, path, error.localizedDescription)
            return nil
        }
    }
}
