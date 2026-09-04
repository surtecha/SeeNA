import Foundation

enum DistanceGuidanceCue: Equatable, Hashable, Sendable {
    case moveBack(steps: Int)
    case moveCloser(steps: Int)
    case tinyStepBack
    case tinyStepCloser
    case stop
    case findFace
    case waitForPhone
    case facePhone
    case lookAtCentre
    case addLight

    var displayText: String {
        switch self {
        case .moveBack, .tinyStepBack: return "MOVE BACK"
        case .moveCloser, .tinyStepCloser: return "MOVE CLOSER"
        case .stop: return "HOLD STILL"
        case .findFace: return "MOVE INTO VIEW"
        case .waitForPhone: return "KEEP PHONE STILL"
        case .facePhone: return "FACE THE PHONE"
        case .lookAtCentre: return "LOOK AT THE CENTRE"
        case .addLight: return "ADD MORE LIGHT"
        }
    }

    var spokenText: String {
        switch self {
        case .moveBack(let steps):
            return "Take about \(Self.numberWord(steps)) small \(steps == 1 ? "step" : "steps") back, then pause."
        case .moveCloser(let steps):
            return "Take about \(Self.numberWord(steps)) small \(steps == 1 ? "step" : "steps") towards the phone, then pause."
        case .tinyStepBack: return "Take one tiny step back, then pause."
        case .tinyStepCloser: return "Take one tiny step towards the phone, then pause."
        case .stop: return "Stop."
        case .findFace: return "Move into the centre of the camera view."
        case .waitForPhone: return "Wait for the phone to settle."
        case .facePhone: return "Face the phone."
        case .lookAtCentre: return "Look at the centre of the screen."
        case .addLight: return "Turn on another light."
        }
    }

    static var preloadTexts: [String] {
        var texts = [
            tinyStepBack.spokenText,
            tinyStepCloser.spokenText,
            stop.spokenText,
            findFace.spokenText,
            waitForPhone.spokenText,
            facePhone.spokenText,
            lookAtCentre.spokenText,
            addLight.spokenText,
            "Walk backwards slowly. I will tell you when to stop.",
            "Walk towards the phone. I will tell you when to stop.",
            "Stay where you are.",
            "You are in position. Starting now. \(SequentialOptotypeSession.requiredTargetCount) rings. Say the openings from left to right.",
            "You are in position. Starting now. \(SequentialGaborSession.requiredTargetCount) stripes. Say left or right, in order."
        ]
        for steps in 1...6 {
            texts.append(moveBack(steps: steps).spokenText)
            texts.append(moveCloser(steps: steps).spokenText)
        }
        return texts
    }

    private static func numberWord(_ value: Int) -> String {
        switch value {
        case 1: return "one"
        case 2: return "two"
        case 3: return "three"
        case 4: return "four"
        case 5: return "five"
        default: return "six"
        }
    }
}

enum DistanceGuidanceEngine {
    static func entryTolerance(for targetDistance: Double) -> Double {
        if targetDistance >= 1 { return 0.05 }
        if targetDistance <= 0.50 { return 0.03 }
        return 0.04
    }

    /// A user who has already reached the target should not lose the lock from
    /// one ordinary head movement. Entry remains clinically tighter than exit.
    static func exitTolerance(for targetDistance: Double) -> Double {
        if targetDistance >= 1.50 { return 0.10 }
        if targetDistance >= 1 { return 0.08 }
        return 0.06
    }

    static func holdDuration(for targetDistance: Double) -> TimeInterval {
        targetDistance >= 1.50 ? 0.55 : 0.65
    }

    static func cue(currentDistance: Double, targetDistance: Double) -> DistanceGuidanceCue {
        let difference = targetDistance - currentDistance
        let magnitude = abs(difference)
        guard magnitude > entryTolerance(for: targetDistance) else { return .stop }

        if magnitude < 0.15 {
            return difference > 0 ? .tinyStepBack : .tinyStepCloser
        }

        let steps = max(1, min(6, Int((magnitude / 0.30).rounded())))
        return difference > 0 ? .moveBack(steps: steps) : .moveCloser(steps: steps)
    }
}

struct RobustDistanceFilter: Sendable {
    private var values: [Double] = []
    private let windowSize: Int
    private let maximumConsecutiveDropouts: Int
    private var consecutiveDropouts = 0

    init(windowSize: Int = 9, maximumConsecutiveDropouts: Int = 6) {
        self.windowSize = max(5, min(15, windowSize))
        self.maximumConsecutiveDropouts = max(0, min(30, maximumConsecutiveDropouts))
    }

    mutating func update(_ value: Double?) -> Double? {
        guard let value, value.isFinite, (0.20...3.0).contains(value) else {
            consecutiveDropouts = min(maximumConsecutiveDropouts + 1, consecutiveDropouts + 1)
            if consecutiveDropouts > maximumConsecutiveDropouts {
                values.removeAll(keepingCapacity: true)
            }
            return nil
        }
        consecutiveDropouts = 0
        values.append(value)
        if values.count > windowSize {
            values.removeFirst(values.count - windowSize)
        }
        return Statistics.median(Statistics.rejectOutliersMAD(values))
    }

    mutating func reset() {
        values.removeAll(keepingCapacity: true)
        consecutiveDropouts = 0
    }
}

struct DistanceTargetState: Equatable, Sendable {
    let isInTargetZone: Bool
    let progress: Double
    let isReady: Bool

    static let idle = DistanceTargetState(isInTargetZone: false, progress: 0, isReady: false)
}

struct DistanceTargetTracker: Sendable {
    private var activeTarget: Double?
    private var isInTargetZone = false
    private var stableDuration: TimeInterval = 0
    private var violationSince: TimeInterval?
    private var lastTimestamp: TimeInterval?
    private let dropoutGrace: TimeInterval

    init(dropoutGrace: TimeInterval = 0.45) {
        self.dropoutGrace = max(0, dropoutGrace)
    }

    mutating func update(
        distance: Double?,
        target: Double,
        conditionsReady: Bool,
        timestamp: TimeInterval
    ) -> DistanceTargetState {
        if activeTarget.map({ abs($0 - target) > 0.001 }) != false {
            reset(for: target)
        }
        let timestamp = timestamp.isFinite ? timestamp : (lastTimestamp ?? 0)
        let entryTolerance = DistanceGuidanceEngine.entryTolerance(for: target)
        let exitTolerance = DistanceGuidanceEngine.exitTolerance(for: target)
        let validDistance = distance.flatMap { value in
            value.isFinite && (0.20...3.0).contains(value) ? value : nil
        }

        guard isInTargetZone else {
            lastTimestamp = timestamp
            guard conditionsReady, let validDistance else { return .idle }
            let error = abs(validDistance - target)
            guard error <= entryTolerance else { return .idle }
            isInTargetZone = true
            stableDuration = 0
            violationSince = nil
            return state(for: target)
        }

        let frameDuration = min(0.20, max(0, timestamp - (lastTimestamp ?? timestamp)))
        lastTimestamp = timestamp
        if let violationSince,
           timestamp - violationSince >= dropoutGrace {
            reset(for: target)
            return .idle
        }
        if conditionsReady,
           let validDistance,
           abs(validDistance - target) <= exitTolerance {
            violationSince = nil
            // Recovery inside the hysteresis window continues the existing
            // hold. The contribution is capped at 200 ms, while a gap lasting
            // 450 ms still resets before this branch can run.
            stableDuration += frameDuration
        } else {
            violationSince = violationSince ?? timestamp
            if timestamp - (violationSince ?? timestamp) >= dropoutGrace {
                reset(for: target)
                return .idle
            }
        }
        return state(for: target)
    }

    mutating func reset() {
        activeTarget = nil
        isInTargetZone = false
        stableDuration = 0
        violationSince = nil
        lastTimestamp = nil
    }

    private mutating func reset(for target: Double) {
        activeTarget = target
        isInTargetZone = false
        stableDuration = 0
        violationSince = nil
        lastTimestamp = nil
    }

    private func state(for target: Double) -> DistanceTargetState {
        let duration = DistanceGuidanceEngine.holdDuration(for: target)
        let progress = min(1, stableDuration / duration)
        return DistanceTargetState(
            isInTargetZone: isInTargetZone,
            progress: progress,
            isReady: isInTargetZone && progress >= 1
        )
    }
}

struct VoiceGuidanceScheduler: Sendable {
    private var lastCue: DistanceGuidanceCue?
    private var lastAnnouncement: TimeInterval?
    private var candidateCue: DistanceGuidanceCue?
    private var candidateSince: TimeInterval?
    private var isSuspended = false

    mutating func begin(at timestamp: TimeInterval) {
        isSuspended = false
        lastCue = nil
        lastAnnouncement = timestamp
        candidateCue = nil
        candidateSince = nil
    }

    /// Ends the current positioning phase. Once the target has been accepted,
    /// stale sensor frames must not restart movement guidance while the test is
    /// counting down or presenting targets. Only `begin(at:)` opens a new phase.
    mutating func acceptTarget() {
        isSuspended = true
        candidateCue = nil
        candidateSince = nil
    }

    mutating func shouldAnnounce(_ cue: DistanceGuidanceCue, at timestamp: TimeInterval) -> Bool {
        guard !isSuspended else { return false }

        if candidateCue != cue {
            candidateCue = cue
            candidateSince = timestamp
            return false
        }

        let settledFor = timestamp - (candidateSince ?? timestamp)
        let requiredSettling = cue == .stop ? 0.18 : 0.45
        guard settledFor >= requiredSettling else { return false }

        let elapsed = timestamp - (lastAnnouncement ?? -Double.infinity)
        let requiredInterval: TimeInterval
        if cue == lastCue {
            requiredInterval = 5.5
        } else if cue == .stop {
            requiredInterval = 0.35
        } else if lastCue == nil {
            requiredInterval = 1.45
        } else {
            requiredInterval = 2.75
        }
        guard elapsed >= requiredInterval else { return false }
        lastCue = cue
        lastAnnouncement = timestamp
        return true
    }

    mutating func reset() {
        lastCue = nil
        lastAnnouncement = nil
        candidateCue = nil
        candidateSince = nil
    }
}
