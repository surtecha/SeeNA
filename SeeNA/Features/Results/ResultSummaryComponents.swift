import Foundation
import SwiftUI

struct ResultPair: View {
    let eye: Eye
    let landolt: EyeScreeningResult?
    let gabor: GaborScreeningResult?
    let integrity: ResultIntegrityValidation?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(eye.displayName) eye")
                .font(.title3.bold())
            Divider()
            ResultMetric(label: "Landolt C", value: landoltValue)
            ResultMetric(label: "Gabor pattern", value: gaborValue)
        }
        .padding(16)
        .background(Color.black.opacity(0.045), in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }

    private var landoltValue: String {
        if integrity?.isValid == false { return "Repeat needed · review required" }
        guard let landolt else { return "Repeat needed" }
        switch landolt.status {
        case .validEstimate:
            if let fail = landolt.lastFailDiopter, let pass = landolt.firstPassDiopter {
                return String(format: "%.2f to %.2f D", max(fail, pass), min(fail, pass))
            }
            return "Estimate available"
        case .noMyopiaDetectedWithinRange: return "No significant myopia detected in POC range"
        case .strongerThanSupportedRange: return "Outside POC range"
        case .unreliableMeasurement: return "Repeat needed"
        case .deviceUnsupported: return "Device unsupported"
        case .userIneligible: return "Not suitable"
        }
    }

    private var gaborValue: String {
        guard let gabor, gabor.status == .completed else { return "Repeat needed" }
        return "Completed"
    }

    static func spokenSummary(
        eye: Eye,
        landolt: EyeScreeningResult?,
        gabor: GaborScreeningResult?,
        integrity: ResultIntegrityValidation?
    ) -> String {
        let eyeName = eye.displayName
        let landoltText: String
        if integrity?.isValid == false {
            landoltText = "\(eyeName) eye result needs repeating because its internal consistency checks need review."
        } else if let landolt, landolt.status == .validEstimate,
                  let fail = landolt.lastFailDiopter, let pass = landolt.firstPassDiopter {
            landoltText = String(
                format: "%@ eye approximate myopia range, minus %.2f to minus %.2f diopters.",
                eyeName,
                abs(max(fail, pass)),
                abs(min(fail, pass))
            )
        } else if landolt?.status == .noMyopiaDetectedWithinRange {
            landoltText = "\(eyeName) eye showed no significant myopia within the supported POC range."
        } else if landolt?.status == .strongerThanSupportedRange {
            landoltText = "\(eyeName) eye was outside the supported POC range."
        } else {
            landoltText = "\(eyeName) eye Landolt test needs repeating."
        }

        if gabor?.status == .completed {
            return "\(landoltText) \(eyeName) eye Gabor orientation task complete."
        }
        return "\(landoltText) The Gabor check needs repeating."
    }
}

private struct ResultMetric: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(SEENATheme.secondaryInk)
            Spacer(minLength: 8)
            Text(value)
                .font(.body.weight(.semibold))
                .multilineTextAlignment(.trailing)
        }
    }
}
