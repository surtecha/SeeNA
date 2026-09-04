import SwiftUI

struct AnswerBlockHeader: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.headline.bold())
            Text(detail)
                .font(.caption)
                .foregroundStyle(SEENATheme.secondaryInk)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

struct LandoltAnswerRow: View {
    let number: Int
    let target: OptotypeDirection
    let response: OptotypeResponse?

    private var responseText: String {
        response?.answerLabel ?? "No answer"
    }

    private var responseImage: String {
        response?.answerSystemImage ?? "questionmark"
    }

    private var isCorrect: Bool {
        response?.matches(target) == true
    }

    var body: some View {
        AnswerAuditRow(
            number: number,
            target: target.answerLabel,
            targetImage: target.answerSystemImage,
            response: responseText,
            responseImage: responseImage,
            isCorrect: isCorrect
        )
    }
}

struct GaborAnswerRow: View {
    let number: Int
    let target: GaborOrientation
    let response: GaborResponse?

    private var responseText: String {
        response?.answerLabel ?? "No answer"
    }

    private var responseImage: String {
        response?.answerSystemImage ?? "questionmark"
    }

    private var isCorrect: Bool {
        response?.matches(target) == true
    }

    var body: some View {
        AnswerAuditRow(
            number: number,
            target: target.answerLabel,
            targetImage: target.answerSystemImage,
            response: responseText,
            responseImage: responseImage,
            isCorrect: isCorrect
        )
    }
}

private struct AnswerAuditRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let number: Int
    let target: String
    let targetImage: String
    let response: String
    let responseImage: String
    let isCorrect: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Trial \(number)")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Label(
                    isCorrect ? "Correct" : "Incorrect",
                    systemImage: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill"
                )
                .font(.caption.weight(.bold))
                .foregroundStyle(isCorrect ? SEENATheme.ink : SEENATheme.danger)
            }

            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    AnswerValue(label: "Correct answer", value: target, systemImage: targetImage)
                    AnswerValue(label: "Accepted answer", value: response, systemImage: responseImage)
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    AnswerValue(label: "Correct answer", value: target, systemImage: targetImage)

                    Image(systemName: "arrow.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(SEENATheme.tertiaryInk)
                        .padding(.top, 22)
                        .accessibilityHidden(true)

                    AnswerValue(label: "Accepted answer", value: response, systemImage: responseImage)
                }
            }
        }
        .padding(14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Trial \(number). Correct answer \(target). Accepted answer \(response). \(isCorrect ? "Correct" : "Incorrect")."
        )
    }
}

private struct AnswerValue: View {
    let label: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(SEENATheme.secondaryInk)

            Label(value, systemImage: systemImage)
                .font(.body.weight(.semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct EmptyAnswerBlockLabel: View {
    var body: some View {
        Text("No saved answers")
            .font(.subheadline)
            .foregroundStyle(SEENATheme.secondaryInk)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SEENATheme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct LockedAnswersView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.fill")
                .font(.system(size: 36, weight: .medium))
            Text("Answers appear after the test")
                .font(.title3.bold())
            Text("Complete both tests for both eyes first.")
                .font(.body)
                .foregroundStyle(SEENATheme.secondaryInk)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private extension OptotypeDirection {
    var answerLabel: String { rawValue.capitalized }

    var answerSystemImage: String {
        switch self {
        case .up: return "arrow.up"
        case .right: return "arrow.right"
        case .down: return "arrow.down"
        case .left: return "arrow.left"
        }
    }
}

private extension OptotypeResponse {
    var answerLabel: String {
        switch self {
        case .notVisible: return "Not visible"
        default: return rawValue.capitalized
        }
    }

    var answerSystemImage: String {
        switch self {
        case .up: return "arrow.up"
        case .right: return "arrow.right"
        case .down: return "arrow.down"
        case .left: return "arrow.left"
        case .notVisible: return "eye.slash"
        }
    }
}

private extension GaborOrientation {
    var answerLabel: String { rawValue.capitalized }

    var answerSystemImage: String {
        switch self {
        case .left: return "arrow.down.left"
        case .right: return "arrow.down.right"
        }
    }
}

private extension GaborResponse {
    var answerLabel: String {
        switch self {
        case .left: return "Left"
        case .right: return "Right"
        case .notVisible: return "Not visible"
        }
    }

    var answerSystemImage: String {
        switch self {
        case .left: return "arrow.down.left"
        case .right: return "arrow.down.right"
        case .notVisible: return "eye.slash"
        }
    }
}
