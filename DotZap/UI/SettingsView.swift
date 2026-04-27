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

import SwiftUI

struct SettingsView: View {
    @ObservedObject private var state = AppState.shared
    @State private var tab: Tab = .volumes
    /// Owned here (not in ActivityView) so the query survives a tab switch.
    /// SwiftUI tears down each tab's view on switch, but SettingsView itself
    /// stays alive for the lifetime of the panel.
    @State private var activitySearchQuery: String = ""

    enum Tab: String, CaseIterable, Identifiable {
        case volumes  = "Volumes"
        case rules    = "Rules"
        case activity = "Activity"
        case about    = "About"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()
                .frame(height: 0.5)
                .overlay(Color.white.opacity(0.12))

            ZStack {
                switch tab {
                case .volumes:  VolumeListView()
                case .rules:    RuleListView()
                case .activity: ActivityView(searchQuery: $activitySearchQuery)
                case .about:    AboutView()
                }
            }
            .animation(.easeInOut(duration: 0.15), value: tab)
        }
        .frame(width: 360, height: 480)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        )
        .preferredColorScheme(nil)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles.rectangle.stack.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            Text("DotZap")
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .labelsHidden()
            .frame(maxWidth: 220)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}
