import SwiftUI

enum SEENATheme {
    static let background = Color.white
    static let card = Color.black.opacity(0.045)
    static let strongCard = Color.black.opacity(0.08)
    static let ink = Color.black
    static let secondaryInk = Color.black.opacity(0.58)
    static let tertiaryInk = Color.black.opacity(0.38)
    static let line = Color.black.opacity(0.12)

    // Retained as a semantic compatibility alias for measurement-ready UI.
    static let teal = ink
    static let danger = Color(red: 0.72, green: 0.12, blue: 0.13)
    static let warning = Color(red: 0.72, green: 0.42, blue: 0.04)

    static let prototypeFooter = "Research prototype · not a prescription"
}

struct SEENABackdrop: View {
    var body: some View {
        ZStack {
            SEENATheme.background

            Circle()
                .fill(Color.black.opacity(0.035))
                .frame(width: 320, height: 320)
                .blur(radius: 34)
                .offset(x: 170, y: -290)

            Circle()
                .fill(Color.black.opacity(0.025))
                .frame(width: 280, height: 280)
                .blur(radius: 44)
                .offset(x: -190, y: 360)
        }
        .ignoresSafeArea()
    }
}

struct FloatingAction {
    let title: String
    let systemImage: String
    let action: () -> Void
}

struct ActionScaffold<Content: View>: View {
    let eyebrow: String
    let title: String
    let subtitle: String?
    let primaryTitle: String
    let primarySystemImage: String
    let primaryEnabled: Bool
    let primaryAction: () -> Void
    let secondaryAction: FloatingAction?
    @ViewBuilder let content: Content

    init(
        eyebrow: String = "SeeNA",
        title: String,
        subtitle: String? = nil,
        primaryTitle: String,
        primarySystemImage: String = "arrow.right",
        primaryEnabled: Bool = true,
        primaryAction: @escaping () -> Void,
        secondaryAction: FloatingAction? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.primaryTitle = primaryTitle
        self.primarySystemImage = primarySystemImage
        self.primaryEnabled = primaryEnabled
        self.primaryAction = primaryAction
        self.secondaryAction = secondaryAction
        self.content = content()
    }

    var body: some View {
        ZStack {
            SEENABackdrop()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    PageHeader(eyebrow: eyebrow, title: title, subtitle: subtitle)
                    content
                }
                .frame(maxWidth: 680, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 132)
                .frame(maxWidth: .infinity)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 7) {
                GlassEffectContainer(spacing: 12) {
                    HStack(spacing: 12) {
                        if let secondaryAction {
                            Button(action: secondaryAction.action) {
                                Image(systemName: secondaryAction.systemImage)
                                    .font(.headline.weight(.semibold))
                                    .frame(width: 54, height: 54)
                            }
                            .buttonStyle(.glass)
                            .accessibilityLabel(secondaryAction.title)
                        }

                        Button(action: primaryAction) {
                            Label(primaryTitle, systemImage: primarySystemImage)
                                .font(.headline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 54)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(SEENATheme.ink)
                        .disabled(!primaryEnabled)
                    }
                }

                Text(SEENATheme.prototypeFooter)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(SEENATheme.tertiaryInk)
                    .accessibilityLabel("Research prototype. This is not an eyeglass prescription or diagnosis.")
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 4)
        }
    }
}

struct PrimaryActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .frame(minHeight: 56)
            .foregroundStyle(Color.white)
            .background(isEnabled ? SEENATheme.ink : SEENATheme.secondaryInk, in: Capsule())
            .overlay {
                Capsule().stroke(SEENATheme.line, lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

struct SecondaryActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .frame(minHeight: 54)
            .foregroundStyle(isEnabled ? SEENATheme.ink : SEENATheme.tertiaryInk)
            .background(SEENATheme.background, in: Capsule())
            .overlay {
                Capsule().stroke(SEENATheme.line, lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

struct ScreenScaffold<Content: View>: View {
    let eyebrow: String
    let title: String
    let subtitle: String?
    @ViewBuilder let content: Content

    init(
        eyebrow: String = "SeeNA",
        title: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        ZStack {
            SEENABackdrop()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    PageHeader(eyebrow: eyebrow, title: title, subtitle: subtitle)
                    content
                }
                .frame(maxWidth: 680, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            DisclaimerFooter()
        }
    }
}

struct PageHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String?
    @ScaledMetric(relativeTo: .title) private var titleSize = 34.0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(eyebrow.uppercased())
                .font(.caption.weight(.bold))
                .tracking(1.8)
                .foregroundStyle(SEENATheme.secondaryInk)

            Text(title)
                .font(.system(size: titleSize, weight: .bold, design: .rounded))
                .foregroundStyle(SEENATheme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            if let subtitle {
                Text(subtitle)
                    .font(.body.weight(.medium))
                    .lineSpacing(4)
                    .foregroundStyle(SEENATheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PlainCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SEENATheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(SEENATheme.line, lineWidth: 1)
            }
    }
}

struct ProgressLine: View {
    let title: String
    let value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(Int(min(max(value, 0), 1) * 100))%")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(SEENATheme.secondaryInk)
                    .monospacedDigit()
            }
            ProgressView(value: min(max(value, 0), 1))
                .tint(SEENATheme.ink)
        }
    }
}

struct DisclaimerFooter: View {
    var body: some View {
        Text(SEENATheme.prototypeFooter)
            .font(.caption2.weight(.medium))
            .foregroundStyle(SEENATheme.tertiaryInk)
            .multilineTextAlignment(.center)
            .lineSpacing(2)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 28)
            .padding(.top, 8)
            .padding(.bottom, 6)
            .background(SEENATheme.background)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(SEENATheme.line)
                    .frame(height: 1)
            }
            .accessibilityLabel(SEENATheme.prototypeFooter)
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
            case .ready: return SEENATheme.ink
            case .warning: return SEENATheme.warning
            case .unavailable: return SEENATheme.danger
            }
        }

        var icon: String {
            switch self {
            case .ready: return "checkmark"
            case .warning: return "exclamationmark"
            case .unavailable: return "xmark"
            }
        }

        var accessibilityValue: String {
            switch self {
            case .ready: return "Ready"
            case .warning: return "Needs attention"
            case .unavailable: return "Unavailable"
            }
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(state.color)
                    .frame(width: 22, height: 22)
                Image(systemName: state.icon)
                    .font(.caption2.weight(.black))
                    .foregroundStyle(Color.white)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(SEENATheme.ink)
                Text(detail)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(SEENATheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(SEENATheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(SEENATheme.line, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(state.accessibilityValue)
    }
}
