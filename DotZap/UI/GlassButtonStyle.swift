import SwiftUI

struct GlassButtonStyle: ButtonStyle {
    var prominent: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.callout, design: .default).weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5)
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .fill(prominent ? Color.accentColor.opacity(0.25) : Color.white.opacity(0.0))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(configuration.isPressed ? 0.12 : 0.0))
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

struct GlassIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 22, height: 22)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white.opacity(configuration.isPressed ? 0.12 : 0.0))
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: configuration.isPressed)
    }
}
