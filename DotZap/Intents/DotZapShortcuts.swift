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

import AppIntents

/// Promotes a curated subset of DotZap's intents to Spotlight + Siri.
///
/// All eight intents in `DotZapIntents.swift` automatically appear in
/// Shortcuts.app on first launch — that's a Shortcuts.app feature, not
/// something this provider does. What `appShortcuts` adds is voice / Spotlight
/// invocation: the listed intents become typeable in Spotlight ("Toggle
/// DotZap") and speakable to Siri without the user wiring a Shortcut first.
///
/// Limited to the highest-leverage actions to avoid cluttering Spotlight.
struct DotZapShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ToggleDotZapIntent(),
            phrases: [
                "Toggle \(.applicationName)",
                "Pause \(.applicationName)",
                "Resume \(.applicationName)",
            ],
            shortTitle: "Toggle DotZap",
            systemImageName: "sparkles.rectangle.stack"
        )
        AppShortcut(
            intent: CleanVolumeIntent(),
            phrases: [
                "Clean a volume with \(.applicationName)",
                "Run \(.applicationName) on a drive",
            ],
            shortTitle: "Clean Volume",
            systemImageName: "trash.circle"
        )
        AppShortcut(
            intent: GetStatsIntent(),
            phrases: [
                "How many files has \(.applicationName) cleaned",
                "Get \(.applicationName) stats",
            ],
            shortTitle: "Get Stats",
            systemImageName: "chart.bar"
        )
    }
}
