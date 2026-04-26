import SwiftUI
import AppKit

struct AboutView: View {
    @ObservedObject private var updater = UpdaterModel.shared

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                identityCard
                updatesCard
                linksCard
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Cards

    private var identityCard: some View {
        VStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 64, height: 64)

            Text("DotZap")
                .font(.system(size: 17, weight: .semibold))

            Text(versionString)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Text("Silently deletes Apple metadata junk on every mounted volume.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .background(card)
    }

    private var updatesCard: some View {
        VStack(spacing: 10) {
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Text("Updates")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
            }

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
        .padding(12)
        .background(card)
    }

    private var linksCard: some View {
        VStack(spacing: 8) {
            linkRow(label: "Releases", systemImage: "shippingbox",
                    url: "https://github.com/Foiler25/DotZap/releases")
            Divider().overlay(Color.white.opacity(0.08))
            linkRow(label: "Source on GitHub", systemImage: "chevron.left.forwardslash.chevron.right",
                    url: "https://github.com/Foiler25/DotZap")
            Divider().overlay(Color.white.opacity(0.08))
            linkRow(label: "Sparkle (auto-update framework)", systemImage: "sparkles",
                    url: "https://sparkle-project.org")
        }
        .padding(10)
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
        .padding(.vertical, 4)
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
