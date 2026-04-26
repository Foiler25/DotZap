import Foundation
import Darwin

enum RuleEngine {
    static func evaluate(path: String, rules: [CleanRule]) -> CleanRule? {
        let filename = (path as NSString).lastPathComponent
        guard !filename.isEmpty else { return nil }

        for rule in rules where rule.isEnabled {
            if matches(filename: filename, rule: rule) {
                return rule
            }
        }
        return nil
    }

    static func matches(filename: String, rule: CleanRule) -> Bool {
        switch rule.matchType {
        case .exact:
            return filename == rule.pattern
        case .prefix:
            let prefix = rule.pattern.replacingOccurrences(of: "*", with: "")
            return !prefix.isEmpty && filename.hasPrefix(prefix)
        case .glob:
            return fnmatch(rule.pattern, filename, 0) == 0
        }
    }
}
