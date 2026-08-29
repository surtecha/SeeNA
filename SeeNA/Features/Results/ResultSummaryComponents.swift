import Foundation
import SwiftUI

struct ResultPair: View {
    let eye: Eye
    let landolt: EyeScreeningResult?
    let gabor: GaborScreeningResult?
    let integrity: ResultIntegrityValidation?
    let gaborIntegrity: GaborResultIntegrityValidation?
    let numericResultsAllowed: Bool?

    init(
        eye: Eye,
        landolt: EyeScreeningResult?,
        gabor: GaborScreeningResult?,
        integrity: ResultIntegrityValidation?,
        gaborIntegrity: GaborResultIntegrityValidation? = nil,
        numericResultsAllowed: Bool?
    ) {
        self.eye = eye
        self.landolt = landolt
        self.gabor = gabor
        self.integrity = integrity
        self.gaborIntegrity = gaborIntegrity
        self.numericResultsAllowed = numericResultsAllowed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(eye.displayName) eye")
                .font(.title3.bold())
            Divider()
            ResultMetric(label: "Landolt C", value: landoltValue)
            ResultMetric(label: "Gabor pattern task", value: gaborValue)
        }
        .padding(16)
        .background(Color.black.opacity(0.045), in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }

    private var landoltValue: String {
        ResultsPresentationPolicy.landoltDisplayValue(
            result: landolt,
            integrityValid: integrity?.isValid,
            numericResultsAllowed: numericResultsAllowed
        )
    }

    private var gaborValue: String {
        if gaborIntegrity?.isValid == false { return "Repeat needed · evidence review required" }
        guard let gabor, gabor.status == .completed else { return "Repeat needed" }
        return "Completed"
    }

    static func spokenSummary(
        eye: Eye,
        landolt: EyeScreeningResult?,
        gabor: GaborScreeningResult?,
        integrity: ResultIntegrityValidation?,
        gaborIntegrity: GaborResultIntegrityValidation? = nil,
        numericResultsAllowed: Bool?
    ) -> String {
        let eyeName = eye.displayName
        let landoltText = ResultsPresentationPolicy.spokenLandoltSummary(
            eye: eye,
            result: landolt,
            integrityValid: integrity?.isValid,
            numericResultsAllowed: numericResultsAllowed
        )

        if gaborIntegrity?.isValid == false {
            return "\(landoltText) The Gabor pattern task needs repeating."
        }
        if gabor?.status == .completed {
            return "\(landoltText) \(eyeName) eye Gabor pattern task complete."
        }
        return "\(landoltText) The Gabor pattern task needs repeating."
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
