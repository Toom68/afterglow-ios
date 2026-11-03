import Foundation

/// A versioned torch sequence. Afterglow does not claim that any set of light parameters is
/// safe or effective. A protocol is either `validated` (reviewed and cited; none exist today) or
/// an `unvalidatedEngineeringTest` used only to exercise the hardware path in development builds.
struct LightProtocol: Identifiable, Codable, Hashable {
    enum Status: Codable, Hashable {
        /// Passed scientific/safety review and optical measurement. `reference` cites the record.
        case validated(reference: String)
        /// Arbitrary engineering numbers for exercising code on a device. NOT a safe dose,
        /// NOT an efficacy protocol, NOT derived from or validated by any study.
        case unvalidatedEngineeringTest(rationale: String)

        var isValidated: Bool {
            if case .validated = self { return true }
            return false
        }
    }

    struct Step: Codable, Hashable {
        /// Fraction of `peakTorchLevel`, 0...1. 0 means torch off.
        var relativeLevel: Float
        var duration: TimeInterval
    }

    var id: String
    var version: Int
    var name: String
    var status: Status
    /// Absolute `AVCaptureDevice` torch level requested at relative level 1, before the
    /// controller's engineering ceiling and the system's thermal limit are applied.
    var peakTorchLevel: Float
    /// Torch stays off for this long after the session starts.
    var preparationDelay: TimeInterval
    /// Steps repeat in order for `lightDuration` seconds after the delay, then light ends.
    var steps: [Step]
    var lightDuration: TimeInterval

    var cycleDuration: TimeInterval { steps.reduce(0) { $0 + $1.duration } }
    var totalDuration: TimeInterval { preparationDelay + lightDuration }

    /// Rejects malformed, non-finite or out-of-range data before anything reaches the torch.
    func isWellFormed(minimumStepDuration: TimeInterval, levelCeiling: Float, maximumLightDuration: TimeInterval) -> Bool {
        guard !steps.isEmpty,
              peakTorchLevel.isFinite, peakTorchLevel > 0, peakTorchLevel <= levelCeiling,
              preparationDelay.isFinite, preparationDelay >= 0,
              lightDuration.isFinite, lightDuration > 0, lightDuration <= maximumLightDuration
        else { return false }
        return steps.allSatisfy {
            $0.duration.isFinite && $0.duration >= minimumStepDuration
                && $0.relativeLevel.isFinite && (0...1).contains($0.relativeLevel)
        }
    }

    /// Relative level `elapsed` seconds after start; nil once the sequence has finished.
    func relativeLevel(at elapsed: TimeInterval) -> Float? {
        guard let located = locate(elapsed) else { return elapsed < preparationDelay && elapsed >= 0 ? 0 : nil }
        return min(max(steps[located.index].relativeLevel, 0), 1)
    }

    /// The next instant (seconds from start) at which the level changes or the sequence ends.
    /// Computed from the absolute start, so scheduling never accumulates drift.
    func nextBoundary(after elapsed: TimeInterval) -> TimeInterval? {
        guard elapsed < totalDuration - Self.tolerance else { return nil }
        if elapsed < preparationDelay { return preparationDelay }
        guard let located = locate(elapsed) else { return nil }
        return min(located.end, totalDuration)
    }

    /// Absorbs floating-point error so an instant computed as a boundary is never treated as
    /// just before it (which would repeat a step or schedule a zero-length one).
    private static let tolerance: TimeInterval = 1e-9

    /// Index of the step active at `elapsed` and the absolute time that step ends.
    private func locate(_ elapsed: TimeInterval) -> (index: Int, end: TimeInterval)? {
        guard elapsed >= preparationDelay, elapsed < totalDuration - Self.tolerance, cycleDuration > 0 else { return nil }
        let intoLight = elapsed - preparationDelay
        let cycles = (intoLight / cycleDuration).rounded(.down)
        var stepEnd = preparationDelay + cycles * cycleDuration
        for (index, step) in steps.enumerated() {
            stepEnd += step.duration
            if elapsed < stepEnd - Self.tolerance { return (index: index, end: stepEnd) }
        }
        return (index: 0, end: stepEnd + steps[0].duration)
    }
}

enum LightProtocolCatalog {
    /// Protocols that passed scientific, safety and optical review. Intentionally empty: no
    /// validated protocol exists (see docs/research/science-and-safety.md). Never move the
    /// engineering test below into this list.
    static let validated: [LightProtocol] = []

    /// Development-only sequence for exercising the torch path on a physical device. These
    /// numbers were specified by the project coordinator as arbitrary engineering test settings:
    /// nominal 3 Hz, 50% duty, requested torch level 0.02, 30 s of light after a 10 s delay.
    /// They are NOT a safe dose, NOT an efficacy protocol, and NOT taken from any study.
    /// Requested timing is scheduled on the main thread; actual emitted timing is unmeasured.
    static let engineeringSmokeTest = LightProtocol(
        id: "engineering-smoke-test",
        version: 1,
        name: "Engineering smoke test (unvalidated)",
        status: .unvalidatedEngineeringTest(rationale: "Coordinator-specified arbitrary hardware test values; not reviewed, measured, or validated."),
        peakTorchLevel: 0.02,
        preparationDelay: 10,
        steps: [
            LightProtocol.Step(relativeLevel: 1, duration: 1.0 / 6.0),
            LightProtocol.Step(relativeLevel: 0, duration: 1.0 / 6.0)
        ],
        lightDuration: 30
    )

    /// Unvalidated sequences that research builds may run. Empty unless compiled for research.
    static var experimental: [LightProtocol] {
        LightFeature.buildAllowsLight ? [engineeringSmokeTest] : []
    }

    /// Everything the current build may run.
    static var available: [LightProtocol] { validated + experimental }

    static func availableProtocol(id: String) -> LightProtocol? {
        available.first { $0.id == id }
    }
}

/// Optional model of a contraindication checklist. Answering "yes" to any question blocks light.
/// Passing it does NOT make light safe; it only excludes people known to be at higher risk. The
/// UI's own screening sheet is authoritative and must be completed before every light session.
struct LightScreening: Codable, Hashable {
    enum Question: String, Codable, CaseIterable, Identifiable {
        case seizureHistory
        case familySeizureHistory
        case lightTriggeredMigraine
        case lightSensitivity
        case under18
        case drivingOrMoving

        var id: String { rawValue }

        var prompt: String {
            switch self {
            case .seizureHistory:
                return "Have you ever had a seizure, epilepsy, or a diagnosis of photosensitivity?"
            case .familySeizureHistory:
                return "Does a close family member have epilepsy or photosensitive seizures?"
            case .lightTriggeredMigraine:
                return "Do flashing or bright lights ever trigger migraines or headaches for you?"
            case .lightSensitivity:
                return "Do you have an eye condition, or take medication, that makes you sensitive to light?"
            case .under18:
                return "Are you under 18?"
            case .drivingOrMoving:
                return "Are you driving, cycling, or operating anything right now?"
            }
        }
    }

    /// `true` means the person answered "yes". Missing answers count as unanswered.
    var answers: [Question: Bool] = [:]

    var isComplete: Bool { Question.allCases.allSatisfy { answers[$0] != nil } }
    var hasContraindication: Bool { answers.values.contains(true) }
    var isEligible: Bool { isComplete && !hasContraindication }
}

enum LightUnavailableReason: Error, Hashable {
    case disabledInThisBuild
    case noProtocolAvailable
    case unknownProtocol
    case screeningNotPassed
    case consentMissing
    case deviceThermalState
    case sessionNotRunning
    case alreadyUsedThisSession
    /// A previous off request failed and the user has not yet confirmed the torch is off.
    case shutdownUnconfirmed
    case hardware(TorchError)

    var message: String {
        switch self {
        case .disabledInThisBuild, .noProtocolAvailable, .unknownProtocol:
            return "Light mode isn't available in this version, so this session is audio only."
        case .screeningNotPassed, .consentMissing:
            return "Light needs this session's safety check and consent, so this session is audio only."
        case .deviceThermalState:
            return "Your device is warm, so light stays off for this session."
        case .sessionNotRunning:
            return "Light can only start with a running session."
        case .alreadyUsedThisSession:
            return "Light already ran in this session. Start a new session to use it again."
        case .shutdownUnconfirmed:
            return "Light is blocked until you confirm the flashlight from an earlier session is off."
        case .hardware(let error):
            return error.localizedDescription
        }
    }
}

/// Pure gate deciding whether a light run may begin. Light is per-session opt-in: screening
/// and consent are never remembered between sessions.
enum LightGate {
    static func evaluate(
        buildAllowsLight: Bool = LightFeature.buildAllowsLight,
        protocolID: String?,
        catalog: [LightProtocol] = LightProtocolCatalog.available,
        screeningPassed: Bool,
        consentedThisSession: Bool,
        thermal: ProcessInfo.ThermalState
    ) -> Result<LightProtocol, LightUnavailableReason> {
        guard buildAllowsLight else { return .failure(.disabledInThisBuild) }
        guard let first = catalog.first else { return .failure(.noProtocolAvailable) }
        let wanted = protocolID ?? first.id
        guard let light = catalog.first(where: { $0.id == wanted }) else { return .failure(.unknownProtocol) }
        guard screeningPassed else { return .failure(.screeningNotPassed) }
        guard consentedThisSession else { return .failure(.consentMissing) }
        guard thermal == .nominal || thermal == .fair else { return .failure(.deviceThermalState) }
        return .success(light)
    }
}

enum LightFeature {
    /// Compile-time switch. Only builds compiled with `AFTERGLOW_LIGHT_RESEARCH` (the project sets
    /// it for the Debug configuration only) can run light. Release/Archive builds never can.
    static var buildAllowsLight: Bool {
        #if AFTERGLOW_LIGHT_RESEARCH
        return true
        #else
        return false
        #endif
    }

    /// What Views should check before offering any light option.
    static var isAvailable: Bool {
        buildAllowsLight && !LightProtocolCatalog.available.isEmpty
    }

    /// True when the only light on offer is unvalidated. Views must say so wherever it is offered.
    static var isExperimentalOnly: Bool {
        isAvailable && !LightProtocolCatalog.available.contains { $0.status.isValidated }
    }

    static var statusTitle: String {
        isAvailable ? "Experimental light (development build)" : "Light mode is not available"
    }

    static var statusExplanation: String {
        isAvailable ? experimentalDisclosure : releaseExplanation
    }

    static let releaseExplanation = """
    Afterglow is audio-only in this build. We have not found a validated protocol for flashing \
    phone-torch light, and the device output has not been measured, so light is switched off. \
    Flashing light can trigger seizures, including in people with no known history.
    """

    static let experimentalDisclosure = """
    This development build includes an unvalidated engineering test of the phone torch: nominal \
    3 Hz flashing, 50% duty, a requested torch level of 0.02, and at most 30 seconds of light \
    after a 10-second delay. These are arbitrary test settings, not a safe dose or a treatment, \
    and they are not taken from any study. Actual emitted timing and brightness have not been \
    measured. Check the output with the torch pointed away from everyone's eyes before any use. \
    Flashing light can trigger seizures, including in people with no known history.
    """
}
