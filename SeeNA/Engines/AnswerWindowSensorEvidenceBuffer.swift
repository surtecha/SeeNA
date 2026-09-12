import Foundation

/// Retains accepted response evidence without letting one answer's good frames
/// conceal another answer's poor conditions. Unaccepted retries are rolled back.
struct AnswerWindowSensorEvidenceBuffer {
    static let maximumRetainedSampleCount = 16_384
    // Engineering dropout budget, not a clinical accuracy threshold.
    static let maximumSampleGap: TimeInterval = 0.5

    private(set) var samples: [DistanceSample] = []
    private(set) var didExceedCapacity = false
    private var windowStartIndex: Int?
    private var windowStart: Date?
    private var windowEnd: Date?

    mutating func beginWindow(at date: Date) {
        discardPendingWindow()
        windowStartIndex = samples.count
        windowStart = date
    }

    mutating func endWindow(at date: Date) {
        windowEnd = date
    }

    mutating func record(_ sample: DistanceSample) {
        // UI timers and sensor publishers can observe the same frame. Retain
        // it once; continuity checks still reject a genuinely frozen stream.
        guard samples.last?.timestamp != sample.timestamp else { return }
        guard samples.count < Self.maximumRetainedSampleCount else {
            didExceedCapacity = true
            return
        }
        samples.append(sample)
    }

    mutating func acceptWindow(
        targetDistanceMetres: Double,
        targetToleranceMetres: Double,
        thresholds: QualityThresholds
    ) -> Bool {
        guard let index = windowStartIndex, let start = windowStart, let end = windowEnd,
              !didExceedCapacity, start.timeIntervalSinceReferenceDate.isFinite,
              end.timeIntervalSinceReferenceDate.isFinite, end > start else {
            discardPendingWindow()
            return false
        }
        let window = Array(samples[index...])
        var previous = start
        let timestampsAreContinuous = !window.isEmpty && window.enumerated().allSatisfy { index, sample in
            let timestamp = sample.timestamp
            let gap = timestamp.timeIntervalSince(previous)
            let valid = gap.isFinite && (index == 0 ? gap >= 0 : gap > 0)
                && gap <= Self.maximumSampleGap && timestamp <= end
            previous = timestamp
            return valid
        } && end.timeIntervalSince(previous) <= Self.maximumSampleGap
        let quality = BlockMeasurementQualityEngine.evaluate(
            samples: window,
            targetDistanceMetres: targetDistanceMetres,
            targetToleranceMetres: targetToleranceMetres,
            thresholds: thresholds
        )
        // Eye-gaze estimation remains advisory, consistent with the live task.
        let accepted = timestampsAreContinuous && quality.issues.allSatisfy {
            $0 == .gazeUnavailable || $0 == .gazeOffCentre
        }
        if accepted {
            windowStartIndex = nil
            windowStart = nil
            windowEnd = nil
        } else {
            discardPendingWindow()
        }
        return accepted
    }

    mutating func discardPendingWindow() {
        if let index = windowStartIndex {
            samples.removeSubrange(index...)
        }
        windowStartIndex = nil
        windowStart = nil
        windowEnd = nil
        // An overflow invalidates the block until its explicit reset.
    }

    mutating func reset(releasingCapacity: Bool = false) {
        samples.removeAll(keepingCapacity: !releasingCapacity)
        didExceedCapacity = false
        windowStartIndex = nil
        windowStart = nil
        windowEnd = nil
    }
}
