import SwiftUI

struct ScreeningIntegritySummary {
    let right: ResultIntegrityValidation?
    let left: ResultIntegrityValidation?

    init(screening: ScreeningSession) {
        right = screening.rightEyeResult.map {
            ResultIntegrityValidator.validate(
                $0,
                against: screening.rightEyeTrials,
                profile: screening.deviceProfile
            )
        }
        left = screening.leftEyeResult.map {
            ResultIntegrityValidator.validate(
                $0,
                against: screening.leftEyeTrials,
                profile: screening.deviceProfile
            )
        }
    }

    var allPresentResultsValid: Bool {
        guard let right, let left else { return false }
        return right.isValid && left.isValid
    }

    var issueCount: Int {
        [right, left]
            .compactMap { $0 }
            .reduce(0) { $0 + $1.issues.count }
    }

    func validation(for eye: Eye) -> ResultIntegrityValidation? {
        eye == .right ? right : left
    }
}

struct ResultVerificationBadge: View {
    let needsReview: Bool
    let issueCount: Int

    private var title: String {
        needsReview ? "Review needed" : "Math consistent"
    }

    private var detail: String {
        if needsReview, issueCount > 0 {
            return "\(issueCount) internal consistency \(issueCount == 1 ? "check needs" : "checks need") review. Not clinical validation."
        }
        if needsReview {
            return "The explanation consistency check needs review. Not clinical validation."
        }
        return "On-device values passed internal consistency checks. Not clinical validation."
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: needsReview ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(needsReview ? SEENATheme.warning : SEENATheme.ink)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(SEENATheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SEENATheme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(SEENATheme.line, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}
