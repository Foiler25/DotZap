import SwiftUI
import AppKit
import Darwin

struct FullDiskAccessBanner: View {
    @State private var isGranted: Bool = FullDiskAccessProbe.hasFullDiskAccess()

    var body: some View {
        if isGranted {
            EmptyView()
        } else {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Full Disk Access required")
                        .font(.system(size: 12, weight: .semibold))
                    Text("DotZap needs Full Disk Access to delete metadata files on every volume.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Button("Open Settings") {
                            FullDiskAccessProbe.openSettings()
                        }
                        .buttonStyle(GlassButtonStyle(prominent: true))

                        Button("Recheck") {
                            isGranted = FullDiskAccessProbe.hasFullDiskAccess()
                        }
                        .buttonStyle(GlassButtonStyle())
                    }
                    .padding(.top, 2)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.orange.opacity(0.25), lineWidth: 0.5)
                    )
            )
        }
    }
}

enum FullDiskAccessProbe {
    static func hasFullDiskAccess() -> Bool {
        let probePath = "/Library/Application Support/com.apple.TCC/TCC.db"
        let fd = open(probePath, O_RDONLY)
        if fd >= 0 {
            close(fd)
            return true
        }
        // EACCES means file exists but we don't have permission → FDA missing.
        // ENOENT (file missing) is unusual; treat as granted to avoid false banner.
        return errno != EACCES
    }

    static func openSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        NSWorkspace.shared.open(url)
    }
}
