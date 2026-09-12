import Foundation

/// An experimental *clarity endpoint* protocol, not a clinically validated Rx.
/// Its display/tape measurements and answer evidence are separate from the
/// fixed-distance Landolt/Gabor task. See docs/REFRACTION_RESEARCH.md.
enum FarPointProtocol {
    static let identifier = "seena-tumbling-e-endpoint-v1"
    static let minimumDistance = 0.40
    static let maximumDistance = 2.0
    static let targetArcMinutes = 5.0
    static let responsesPerLevel = 3
    static let repetitions = 3
    static let maximumBracketWidth = 0.25
    static let maximumRepeatSpread = 0.50 // Engineering repeatability gate, not clinical accuracy.
    static let distanceReadingBound = 0.005 // Helper agrees to read a tape to within 5 mm.

    static func targetPoints(distance: Double, millimetresPerPoint: Double, displayScale: Double) -> Double? {
        guard distance.isFinite, (minimumDistance...maximumDistance).contains(distance),
              millimetresPerPoint.isFinite, (0.08...0.30).contains(millimetresPerPoint),
              displayScale.isFinite, (1...4).contains(displayScale),
              let metres = VisualAngleGeometry.physicalHeightMetres(
                forArcMinutes: targetArcMinutes, atDistanceMetres: distance
              ) else { return nil }
        let points = metres * 1000 / millimetresPerPoint
        // Do not enlarge the optotype to make it pass. Reject insufficient
        // raster resolution instead; each of the five strokes needs 2 pixels.
        return points * displayScale / 5 >= 2 ? points : nil
    }
}

struct FarPointLevel: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let eye: Eye
    let repetition: Int
    let requestedDiopter: Double
    let measuredDistanceMetres: Double
    let targets: [OptotypeDirection]
    let responses: [OptotypeResponse]
    let recordedAt: Date
    var passed: Bool {
        targets.count == FarPointProtocol.responsesPerLevel && responses.count == targets.count
            && zip(targets, responses).allSatisfy { $1.matches($0) }
    }
}

struct FarPointBracket: Equatable, Sendable {
    let passingDistance: Double
    let failingDistance: Double
    var lowerDiopter: Double { -1 / (passingDistance - FarPointProtocol.distanceReadingBound) }
    var upperDiopter: Double { -1 / (failingDistance + FarPointProtocol.distanceReadingBound) }
    var midpoint: Double { (-1 / passingDistance - 1 / failingDistance) / 2 }
}

enum FarPointOutcome: Equatable, Sendable {
    case estimate(midpoint: Double, lower: Double, upper: Double)
    case outsideRange
    case inconsistent
    case incomplete

    var shortDescription: String {
        switch self {
        case .estimate(let value, _, _): return String(format: "≈ %.2f D", RefractionEstimator.roundedToQuarterDiopter(value))
        case .outsideRange: return "Outside test range"
        case .inconsistent: return "Repeat needed"
        case .incomplete: return "Not completed"
        }
    }
}

/// A descending-distance bracket search. Three independent sweeps must agree.
/// All decisions derive from entered distances and verified target responses.
struct FarPointSearch: Sendable {
    let eye: Eye
    private(set) var requestedDiopter = -0.5
    private(set) var repetition = 0
    private(set) var levels: [FarPointLevel] = []
    private(set) var brackets: [FarPointBracket] = []
    private(set) var outcome: FarPointOutcome = .incomplete
    private var passDistance: Double?
    private var failDistance: Double?

    init(eye: Eye) { self.eye = eye }

    var isFinished: Bool { outcome != .incomplete }
    var requestedDistance: Double { -1 / requestedDiopter }

    @discardableResult
    mutating func submit(_ level: FarPointLevel) -> Bool {
        guard !isFinished, level.eye == eye, level.repetition == repetition,
              level.requestedDiopter.isFinite,
              abs(level.requestedDiopter - requestedDiopter) < 0.000_001,
              level.measuredDistanceMetres.isFinite,
              (FarPointProtocol.minimumDistance...FarPointProtocol.maximumDistance).contains(level.measuredDistanceMetres),
              abs(level.measuredDistanceMetres - requestedDistance) <= FarPointProtocol.distanceReadingBound + 0.000_001,
              level.targets.count == FarPointProtocol.responsesPerLevel,
              level.responses.count == level.targets.count,
              level.recordedAt.timeIntervalSinceReferenceDate.isFinite,
              !levels.contains(where: { $0.id == level.id }) else { return false }
        levels.append(level)
        if level.passed {
            guard failDistance != nil else { outcome = .outsideRange; return true }
            passDistance = level.measuredDistanceMetres
        } else {
            failDistance = level.measuredDistanceMetres
            if requestedDiopter <= -2.5 { outcome = .outsideRange; return true }
        }

        guard let pass = passDistance, let fail = failDistance else {
            requestedDiopter = max(-2.5, requestedDiopter - 0.5)
            return true
        }
        guard pass < fail else { outcome = .inconsistent; return true }
        let width = 1 / pass - 1 / fail
        if width <= FarPointProtocol.maximumBracketWidth + 0.000_001 {
            brackets.append(FarPointBracket(passingDistance: pass, failingDistance: fail))
            if brackets.count == FarPointProtocol.repetitions {
                let midpoints = brackets.map(\.midpoint)
                guard let lo = midpoints.min(), let hi = midpoints.max(),
                      hi - lo <= FarPointProtocol.maximumRepeatSpread,
                      let centre = Statistics.median(midpoints),
                      let lower = brackets.map(\.lowerDiopter).min(),
                      let upper = brackets.map(\.upperDiopter).max() else {
                    outcome = .inconsistent; return true
                }
                outcome = .estimate(midpoint: centre, lower: lower, upper: upper)
            } else {
                repetition += 1
                requestedDiopter = -0.5
                passDistance = nil
                failDistance = nil
            }
        } else {
            requestedDiopter = (-1 / pass - 1 / fail) / 2
        }
        return true
    }
}

struct RefractionRecord: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let createdAt: Date
    let protocolIdentifier: String
    let millimetresPerPoint: Double
    let displayScale: Double
    let levels: [FarPointLevel]

    /// Rebuild results from evidence on every read. Never trust a persisted
    /// computed power or a flag claiming clinical approval.
    func outcome(for eye: Eye) -> FarPointOutcome {
        guard protocolIdentifier == FarPointProtocol.identifier,
              createdAt.timeIntervalSinceReferenceDate.isFinite,
              !levels.isEmpty else { return .incomplete }
        var search = FarPointSearch(eye: eye)
        for level in levels where level.eye == eye {
            guard FarPointProtocol.targetPoints(distance: level.measuredDistanceMetres,
                                                millimetresPerPoint: millimetresPerPoint,
                                                displayScale: displayScale) != nil,
                  search.submit(level) else { return .inconsistent }
        }
        return search.outcome
    }
}
