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

struct ActivityView: View {
    @ObservedObject private var state = AppState.shared
    @State private var pendingClear: Bool = false

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    private var bytesString: String {
        ByteCountFormatter.string(fromByteCount: Int64(state.lifetimeBytesFreed),
                                  countStyle: .file)
    }

    var body: some View {
        VStack(spacing: 0) {
            statsHeader
            Divider().overlay(Color.white.opacity(0.1))

            if pendingClear {
                clearConfirm
                    .transition(.opacity)
            }

            if state.recentEvents.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(state.recentEvents) { event in
                            DeletionEventRow(event: event)
                                .padding(.horizontal, 10)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private var statsHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Activity")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(state.lifetimeFilesDeleted)")
                        .font(.system(size: 17, weight: .bold))
                    Text("files")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(bytesString)
                        .font(.system(size: 13, weight: .semibold))
                    Text("freed")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Clear") {
                withAnimation(.easeInOut(duration: 0.15)) {
                    pendingClear.toggle()
                }
            }
            .buttonStyle(GlassButtonStyle())
            .disabled(state.recentEvents.isEmpty && state.lifetimeFilesDeleted == 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var clearConfirm: some View {
        HStack {
            Text("Clear all activity and reset lifetime stats?")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Cancel") {
                withAnimation(.easeInOut(duration: 0.15)) { pendingClear = false }
            }
            .buttonStyle(GlassButtonStyle())
            Button("Clear") {
                withAnimation(.easeInOut(duration: 0.2)) {
                    state.clearActivity()
                    pendingClear = false
                }
            }
            .buttonStyle(GlassButtonStyle(prominent: true))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.05))
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
            Text("No deletions yet")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text("DotZap will log files it deletes here.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }
}

private struct DeletionEventRow: View {
    let event: DeletionEvent

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    private var sizeString: String {
        ByteCountFormatter.string(fromByteCount: Int64(event.bytes), countStyle: .file)
    }

    private var timeString: String {
        let interval = -event.timestamp.timeIntervalSinceNow
        if interval < 30 { return "just now" }
        return Self.relative.localizedString(for: event.timestamp, relativeTo: Date())
    }

    private var isDeleted: Bool { event.status == .deleted }
    private var badge: (label: String, color: Color)? {
        switch event.status {
        case .deleted:         return nil
        case .skippedOversize: return ("SKIPPED", .orange)
        case .dryRun:          return ("DRY RUN", .blue)
        }
    }

    private var helpText: String {
        switch event.status {
        case .deleted:         return ""
        case .skippedOversize: return "Matched “\(event.ruleName)” but exceeded the file-size cap"
        case .dryRun:          return "Matched “\(event.ruleName)” — would have been deleted (dry-run mode)"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(event.fileName)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 130, alignment: .leading)
                .foregroundStyle(isDeleted ? .primary : .secondary)

            if let badge {
                Text(badge.label)
                    .font(.system(size: 8, weight: .bold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(
                        Capsule().fill(badge.color.opacity(0.25))
                    )
                    .foregroundStyle(badge.color)
            } else {
                Text(event.ruleName)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(sizeString)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)

            Text(event.volumeName)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: 60, alignment: .trailing)

            Text(timeString)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .frame(width: 60, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(isDeleted ? 0.04 : 0.02))
        )
        .help(helpText)
    }
}
