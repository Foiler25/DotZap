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

struct CleanRule: Codable, Identifiable, Hashable {
    enum MatchType: String, Codable, CaseIterable {
        case exact
        case prefix
        case glob

        var label: String {
            switch self {
            case .exact:  return "Exact"
            case .prefix: return "Prefix"
            case .glob:   return "Glob"
            }
        }
    }

    var id: UUID
    var name: String
    var pattern: String
    var matchType: MatchType
    var isEnabled: Bool
    var isBuiltIn: Bool

    init(
        id: UUID = UUID(),
        name: String,
        pattern: String,
        matchType: MatchType,
        isEnabled: Bool = true,
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.name = name
        self.pattern = pattern
        self.matchType = matchType
        self.isEnabled = isEnabled
        self.isBuiltIn = isBuiltIn
    }

    static let builtInDefaults: [CleanRule] = [
        CleanRule(name: "Apple Double",     pattern: "._*",             matchType: .prefix, isBuiltIn: true),
        CleanRule(name: "DS Store",         pattern: ".DS_Store",       matchType: .exact,  isBuiltIn: true),
        CleanRule(name: "Spotlight Index",  pattern: ".Spotlight-V100", matchType: .exact,  isBuiltIn: true),
        CleanRule(name: "Volume Trash",     pattern: ".Trashes",        matchType: .exact,  isBuiltIn: true),
        CleanRule(name: "FSEvents Journal", pattern: ".fseventsd",      matchType: .exact,  isBuiltIn: true),
        CleanRule(name: "Temporary Items",  pattern: ".TemporaryItems", matchType: .exact,  isBuiltIn: true),
        CleanRule(name: "Zip Mac Metadata", pattern: "__MACOSX",        matchType: .exact,  isBuiltIn: true),
        CleanRule(name: "Win Thumbnails",   pattern: "Thumbs.db",       matchType: .exact,  isBuiltIn: true),
        CleanRule(name: "Win Desktop.ini",  pattern: "desktop.ini",     matchType: .exact,  isBuiltIn: true),
    ]
}
