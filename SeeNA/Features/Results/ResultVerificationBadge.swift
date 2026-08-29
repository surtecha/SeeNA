import SwiftUI

struct ScreeningIntegritySummary {
    let right: ResultIntegrityValidation?
    let left: ResultIntegrityValidation?
    let rightGabor: GaborResultIntegrityValidation?
    let leftGabor: GaborResultIntegrityValidation?

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
        rightGabor = screening.rightGaborResult.map {
            GaborResultIntegrityValidator.validate($0, against: screening.rightGaborTrials ?? [])
        }
        leftGabor = screening.leftGaborResult.map {
            GaborResultIntegrityValidator.validate($0, against: screening.leftGaborTrials ?? [])
        }
    }

    var allPresentResultsValid: Bool {
        guard let right, let left, let rightGabor, let leftGabor else { return false }
        return right.isValid && left.isValid && rightGabor.isValid && leftGabor.isValid
    }

    var issueCount: Int {
        let landoltIssues = [right, left]
            .compactMap { $0 }
            .reduce(0) { $0 + $1.issues.count }
        let gaborIssues = [rightGabor, leftGabor]
            .compactMap { $0 }
            .reduce(0) { $0 + $1.issues.count }
        return landoltIssues + gaborIssues
    }

    func validation(for eye: Eye) -> ResultIntegrityValidation? {
        eye == .right ? right : left
    }
}

enum ResultVerificationState: Equatable {
    case reviewNeeded
    case numericConsistent
    case numericNotApplicable
}

struct ResultVerificationBadge: View {
    let state: ResultVerificationState
    let issueCount: Int

    private var title: String {
        switch state {
        case .reviewNeeded: return "Review needed"
        case .numericConsistent: return "Screening checks passed"
        case .numericNotApplicable: return "Screening checks passed"
        }
    }

    private var detail: String {
        if state == .reviewNeeded, issueCount > 0 {
            return "\(issueCount) screening \(issueCount == 1 ? "check needs" : "checks need") review."
        }
        if state == .reviewNeeded {
            return "The screening summary needs review."
        }
        if state == .numericConsistent {
            return "Your completed tasks passed the screening checks."
        }
        return "Your completed tasks passed the screening checks."
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: state == .reviewNeeded ? "exclamationmark.circle.fill" : "info.circle.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(state == .reviewNeeded ? SEENATheme.warning : SEENATheme.ink)

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
