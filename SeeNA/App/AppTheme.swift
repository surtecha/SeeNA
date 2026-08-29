import SwiftUI

enum SEENATheme {
    static let background = Color(red: 0.98, green: 0.97, blue: 0.94)
    static let card = Color.white
    static let ink = Color(red: 0.06, green: 0.10, blue: 0.12)
    static let secondaryInk = Color(red: 0.28, green: 0.34, blue: 0.36)
    static let teal = Color(red: 0.00, green: 0.43, blue: 0.42)
    static let danger = Color(red: 0.72, green: 0.12, blue: 0.13)
    static let warning = Color(red: 0.74, green: 0.43, blue: 0.05)
}

struct PrimaryActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 56)
            .foregroundColor(.white)
            .background(isEnabled ? SEENATheme.teal : Color.gray)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(configuration.isPressed ? 0.78 : 1)
            .contentShape(Rectangle())
    }
}

struct SecondaryActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 54)
            .foregroundColor(SEENATheme.ink)
            .background(SEENATheme.card)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(SEENATheme.ink.opacity(0.18), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

struct ScreenScaffold<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let content: Content

    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(title)
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .foregroundColor(SEENATheme.ink)
                        .accessibilityAddTraits(.isHeader)
                    if let subtitle {
                        Text(subtitle)
                            .font(.title3)
                            .foregroundColor(SEENATheme.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                content
            }
            .frame(maxWidth: 680, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 44)
        }
        .background(SEENATheme.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            Text("Research prototype — not a prescription")
                .font(.caption.weight(.semibold))
                .foregroundColor(SEENATheme.secondaryInk)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(SEENATheme.background.opacity(0.96))
        }
    }
}

struct StatusRow: View {
    let title: String
    let detail: String
    let state: State

    enum State {
        case ready
        case warning
        case unavailable

        var color: Color {
            switch self {
            case .ready: return SEENATheme.teal
            case .warning: return SEENATheme.warning
            case .unavailable: return SEENATheme.danger
            }
        }

        var icon: String {
            switch self {
            case .ready: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .unavailable: return "xmark.circle.fill"
            }
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: state.icon)
                .foregroundColor(state.color)
                .font(.title3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline).foregroundColor(SEENATheme.ink)
                Text(detail).font(.subheadline).foregroundColor(SEENATheme.secondaryInk)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(SEENATheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
