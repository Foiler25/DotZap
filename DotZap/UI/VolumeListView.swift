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
import AppKit

/// Cache `NSWorkspace.icon(forFile:)` lookups per mount path. Without this,
/// every SwiftUI re-render of `VolumeRow` allocates a fresh NSImage, which
/// adds up under high FSEvents-driven re-render rates.
@MainActor
private enum DriveIconCache {
    private static var cache: [String: NSImage] = [:]

    static func icon(for mountPath: String) -> NSImage {
        if let cached = cache[mountPath] { return cached }
        let icon = NSWorkspace.shared.icon(forFile: mountPath)
        cache[mountPath] = icon
        return icon
    }

    static func invalidate(_ mountPath: String) {
        cache.removeValue(forKey: mountPath)
    }
}

struct VolumeListView: View {
    @ObservedObject private var state = AppState.shared

    private var watchingCount: Int {
        state.volumes.filter { $0.isEnabled && !$0.isEjected }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Volumes")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                Text(watchingCount == 1 ? "1 watching" : "\(watchingCount) watching")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 6)

            ScrollView {
                LazyVStack(spacing: 6) {
                    FullDiskAccessBanner()
                        .padding(.horizontal, 10)
                        .padding(.top, 4)

                    if state.volumes.isEmpty {
                        emptyState
                    } else {
                        ForEach(state.volumes) { volume in
                            VolumeRow(volume: volume)
                                .padding(.horizontal, 10)
                        }
                    }

                    LoginAtLoginRow()
                        .padding(.horizontal, 10)
                        .padding(.top, 6)
                }
                .padding(.bottom, 12)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "externaldrive.badge.questionmark")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
            Text("No volumes detected")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text("Plug in a drive to start cleaning.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }
}

private struct VolumeRow: View {
    let volume: Volume
    @ObservedObject private var state = AppState.shared
    @State private var expanded = false
    @State private var newWhitelist: String = ""
    @State private var pendingStripConfirm: Bool = false
    @State private var isStripping: Bool = false

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { volume.isEnabled },
            set: { state.setVolumeEnabled(mountPath: volume.mountPath, enabled: $0) }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if expanded {
                expandedDetails
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .opacity(volume.isEjected ? 0.55 : 1.0)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: DriveIconCache.icon(for: volume.mountPath))
                .resizable()
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(volume.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    if volume.isEjected {
                        Text("Ejected")
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                Capsule().fill(Color.secondary.opacity(0.18))
                            )
                            .foregroundStyle(.secondary)
                    }
                }
                Text(volume.mountPath)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Text(volume.filesystem)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule().fill(Color.secondary.opacity(0.12))
                )

            Toggle("", isOn: enabledBinding)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .disabled(volume.isEjected)
        }
        .padding(10)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                expanded.toggle()
            }
        }
    }

    private var expandedDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider().overlay(Color.white.opacity(0.08))

            HStack {
                stat(label: "Files cleaned", value: "\(volume.lifetimeFilesDeleted)")
                Spacer()
                stat(label: "Bytes freed",
                     value: ByteCountFormatter.string(fromByteCount: Int64(volume.lifetimeBytesFreed),
                                                     countStyle: .file))
            }

            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Dry run")
                        .font(.system(size: 11))
                    Text("Log matches without deleting. Useful for auditing rules.")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { volume.dryRun },
                    set: { state.setVolumeDryRun(mountPath: volume.mountPath, dryRun: $0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Whitelist (glob patterns)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                ForEach(volume.whitelist, id: \.self) { pattern in
                    HStack {
                        Text(pattern)
                            .font(.system(size: 11, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button {
                            state.removeWhitelistEntry(mountPath: volume.mountPath, pattern: pattern)
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(GlassIconButtonStyle())
                    }
                    .padding(.vertical, 2)
                }

                HStack(spacing: 6) {
                    TextField("e.g. *.psd", text: $newWhitelist)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                        .onSubmit { addWhitelist() }
                    Button {
                        addWhitelist()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .buttonStyle(GlassIconButtonStyle())
                    .disabled(newWhitelist.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            HStack {
                Spacer()
                Button("Clean Now") {
                    VolumeWatcher.shared.cleanNow(mountPath: volume.mountPath)
                }
                .buttonStyle(GlassButtonStyle(prominent: true))
                .disabled(volume.isEjected)
            }

            xattrStripSection
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var xattrStripSection: some View {
        Divider().overlay(Color.white.opacity(0.08))

        if pendingStripConfirm {
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text("Strip extended attributes from every file on \(volume.name)?")
                        .font(.system(size: 11))
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                Text("This permanently removes Finder color tags, comments, and any \(Text("com.apple.metadata:*").font(.system(size: 10, design: .monospaced))) attributes — including ones some apps (Lightroom, Photos export) rely on. The fix prevents `._*` files from regenerating on exFAT/FAT32 volumes.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button("Cancel") {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            pendingStripConfirm = false
                        }
                    }
                    .buttonStyle(GlassButtonStyle())
                    Button("Strip Now") {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            pendingStripConfirm = false
                        }
                        runStrip()
                    }
                    .buttonStyle(GlassButtonStyle(prominent: true))
                }
            }
            .transition(.opacity)
        } else {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Strip extended attributes")
                        .font(.system(size: 11))
                    Text(isStripping
                         ? "Working… this may take a while on large volumes."
                         : "One-shot. Stops `._*` files from regenerating on exFAT/FAT32.")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isStripping {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Strip…") {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            pendingStripConfirm = true
                        }
                    }
                    .buttonStyle(GlassButtonStyle())
                    .disabled(volume.isEjected)
                }
            }
        }
    }

    private func runStrip() {
        let mountPath = volume.mountPath
        let volumeName = volume.name
        isStripping = true
        Task.detached(priority: .userInitiated) {
            let result = XattrStripper.strip(at: mountPath)
            await MainActor.run {
                let summary: String
                if result.filesModified == 0 {
                    summary = result.errors > 0
                        ? "No xattrs cleared (\(result.errors) errors)"
                        : "No extended attributes found"
                } else {
                    summary = "Stripped xattrs from \(result.filesModified) "
                        + (result.filesModified == 1 ? "file" : "files")
                        + (result.errors > 0 ? " (\(result.errors) errors)" : "")
                }
                let event = DeletionEvent(
                    path: mountPath,
                    ruleName: summary,
                    bytes: 0,
                    volumeName: volumeName,
                    volumeMountPath: mountPath,
                    status: .xattrStripped
                )
                AppState.shared.recordBatch([event])
                isStripping = false
            }
        }
    }

    private func addWhitelist() {
        let trimmed = newWhitelist.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        state.addWhitelistEntry(mountPath: volume.mountPath, pattern: trimmed)
        newWhitelist = ""
    }

    private func stat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
        }
    }
}

private struct LoginAtLoginRow: View {
    @State private var enabled: Bool = LoginItemManager.isEnabled

    var body: some View {
        HStack {
            Image(systemName: "power.circle")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Text("Launch at Login")
                .font(.system(size: 12))
            Spacer()
            Toggle("", isOn: Binding(
                get: { enabled },
                set: { newValue in
                    LoginItemManager.setEnabled(newValue)
                    enabled = LoginItemManager.isEnabled
                }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }
}
