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
