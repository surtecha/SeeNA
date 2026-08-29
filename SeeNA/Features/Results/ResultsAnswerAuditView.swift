import Foundation
import SwiftUI

struct ResultsAnswerAuditView: View {
    @Environment(\.dismiss) private var dismiss

    let screening: ScreeningSession
    let isScreeningComplete: Bool

    var body: some View {
        NavigationStack {
            Group {
                if isScreeningComplete {
                    AnswerAuditContent(screening: screening)
                } else {
                    LockedAnswersView()
                }
            }
            .background(Color.white.ignoresSafeArea())
            .navigationTitle("Your answers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss.callAsFunction)
                }
            }
        }
    }
}

private struct AnswerAuditContent: View {
    let screening: ScreeningSession

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 24) {
                Text("Each target is shown with the answer that was accepted during the test.")
                    .font(.subheadline)
                    .foregroundStyle(SEENATheme.secondaryInk)

                EyeAnswerAuditSection(
                    eye: .right,
                    landoltBlocks: screening.rightEyeTrials,
                    gaborBlocks: screening.rightGaborTrials ?? []
                )

                EyeAnswerAuditSection(
                    eye: .left,
                    landoltBlocks: screening.leftEyeTrials,
                    gaborBlocks: screening.leftGaborTrials ?? []
                )
            }
            .padding(20)
        }
    }
}

private struct EyeAnswerAuditSection: View {
    let eye: Eye
    let landoltBlocks: [TrialBlock]
    let gaborBlocks: [GaborTrial]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(eye.displayName) eye")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)

            Text("Landolt circles")
                .font(.headline)
                .foregroundStyle(SEENATheme.secondaryInk)

            if landoltBlocks.isEmpty {
                EmptyAnswerBlockLabel()
            } else {
                ForEach(Array(landoltBlocks.enumerated()), id: \.element.id) { index, block in
                    LandoltAnswerBlock(blockNumber: index + 1, block: block)
                }
            }

            Text("Gabor patterns")
                .font(.headline)
                .foregroundStyle(SEENATheme.secondaryInk)
                .padding(.top, 4)

            if gaborBlocks.isEmpty {
                EmptyAnswerBlockLabel()
            } else {
                ForEach(Array(gaborBlocks.enumerated()), id: \.element.id) { index, block in
                    GaborAnswerBlock(blockNumber: index + 1, block: block)
                }
            }
        }
    }
}

private struct LandoltAnswerBlock: View {
    let blockNumber: Int
    let block: TrialBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AnswerBlockHeader(
                title: "Block \(blockNumber)",
                detail: String(format: "%.2f m · %d/%d correct", block.actualMedianDistanceMetres, block.correctCount, block.targets.count)
            )

            Divider()

            ForEach(Array(block.targets.enumerated()), id: \.offset) { index, target in
                LandoltAnswerRow(
                    number: index + 1,
                    target: target,
                    response: response(at: index)
                )

                if index < block.targets.count - 1 {
                    Divider().padding(.leading, 44)
                }
            }
        }
        .background(SEENATheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(SEENATheme.line, lineWidth: 1)
        }
    }

    private func response(at index: Int) -> OptotypeResponse? {
        guard block.responses.indices.contains(index) else { return nil }
        return block.responses[index]
    }
}

private struct GaborAnswerBlock: View {
    let blockNumber: Int
    let block: GaborTrial

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AnswerBlockHeader(
                title: "Block \(blockNumber)",
                detail: "\(Int((block.contrast * 100).rounded()))% contrast · \(block.correctCount)/\(block.targets.count) correct"
            )

            Divider()

            ForEach(Array(block.targets.enumerated()), id: \.offset) { index, target in
                GaborAnswerRow(
                    number: index + 1,
                    target: target,
                    response: response(at: index)
                )

                if index < block.targets.count - 1 {
                    Divider().padding(.leading, 44)
                }
            }
        }
        .background(SEENATheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(SEENATheme.line, lineWidth: 1)
        }
    }

    private func response(at index: Int) -> GaborResponse? {
        guard block.responses.indices.contains(index) else { return nil }
        return block.responses[index]
    }
}
