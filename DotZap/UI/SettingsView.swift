import SwiftUI

struct SettingsView: View {
    @ObservedObject private var state = AppState.shared
    @State private var tab: Tab = .volumes

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
                case .activity: ActivityView()
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
