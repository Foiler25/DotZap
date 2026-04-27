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

struct AboutView: View {
    @ObservedObject private var updater = UpdaterModel.shared
    @ObservedObject private var state = AppState.shared

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                identityCard
                updatesCard
                behaviorCard
                linksCard
                quitRow
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
    }

    private var quitRow: some View {
        HStack {
            Spacer()
            Button("Quit DotZap") {
                NSApp.terminate(nil)
            }
            .buttonStyle(GlassButtonStyle())
            .keyboardShortcut("q", modifiers: .command)
            Spacer()
        }
    }

    // MARK: - Cards

    private var identityCard: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text("DotZap")
                    .font(.system(size: 17, weight: .semibold))
                Text(versionString)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(card)
    }

    private var updatesCard: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Automatically check for updates")
                    .font(.system(size: 11))
                Spacer()
                Toggle("", isOn: $updater.automaticallyChecksForUpdates)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
            }

            HStack {
                Spacer()
                Button("Check for Updates…") {
                    updater.checkForUpdates()
                }
                .buttonStyle(GlassButtonStyle(prominent: true))
                .disabled(!updater.canCheckForUpdates)
            }
        }
        .padding(10)
        .background(card)
    }

    private var behaviorCard: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Move deletions to Trash")
                        .font(.system(size: 11))
                    Text("Recoverable from Finder. Turn off for permanent delete.")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { state.moveToTrash },
                    set: {
                        state.moveToTrash = $0
                        state.persistSettings()
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
            }

            Divider().overlay(Color.white.opacity(0.08))

            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Skip files larger than")
                        .font(.system(size: 11))
                    Text("Safety net — files over this never delete, even on rule match.")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                TextField("", value: sizeCapMBBinding,
                          formatter: Self.integerFormatter)
                    .frame(width: 56)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                Stepper("", value: sizeCapMBBinding, in: 1...10000, step: 10)
                    .labelsHidden()
                Text("MB")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(card)
    }

    private var sizeCapMBBinding: Binding<Int> {
        Binding(
            get: {
                let bytes = state.maxFileSizeBytes
                guard bytes > 0, bytes < Int.max else { return 50 }
                return max(1, bytes / (1024 * 1024))
            },
            set: { newMB in
                let clamped = max(1, min(newMB, 10000))
                state.maxFileSizeBytes = clamped * 1024 * 1024
                state.persistSettings()
            }
        )
    }

    private static let integerFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.allowsFloats = false
        f.minimum = 1
        f.maximum = 10000
        return f
    }()

    private var linksCard: some View {
        VStack(spacing: 4) {
            linkRow(label: "Releases", systemImage: "shippingbox",
                    url: "https://github.com/Foiler25/DotZap/releases")
            Divider().overlay(Color.white.opacity(0.08))
            linkRow(label: "Source on GitHub", systemImage: "chevron.left.forwardslash.chevron.right",
                    url: "https://github.com/Foiler25/DotZap")
        }
        .padding(8)
        .background(card)
    }

    private func linkRow(label: String, systemImage: String, url: String) -> some View {
        Button {
            if let u = URL(string: url) { NSWorkspace.shared.open(u) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(label)
                    .font(.system(size: 11))
                Spacer()
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
            )
    }
}
