import Foundation

/// A flicker program: an ordered set of segments whose flash frequency glides linearly from
/// `startHz` to `endHz`. Segment `weight`s are shares of the light part of a session, so the
/// same program stretches to any session length. Intensities are fractions of the user's
/// brightness setting. No program here is a clinically validated dose.
struct LightProgram: Identifiable, Codable, Hashable {
    struct Segment: Codable, Hashable {
        var weight: Double
        var startHz: Double
        var endHz: Double
        var startIntensity: Double = 1
        var endIntensity: Double = 1
    }

    var id: String
    var name: String
    var summary: String
    /// Share of each flash cycle the torch is on.
    var dutyCycle: Double
    var segments: [Segment]

    var lowestHz: Double { segments.flatMap { [$0.startHz, $0.endHz] }.min() ?? 0 }
    var highestHz: Double { segments.flatMap { [$0.startHz, $0.endHz] }.max() ?? 0 }

    var rangeDescription: String {
        let low = Self.format(lowestHz), high = Self.format(highestHz)
        return low == high ? "\(low) Hz" : "\(low)–\(high) Hz"
    }

    static func format(_ hz: Double) -> String {
        hz.rounded() == hz ? String(Int(hz)) : String(format: "%.1f", hz)
    }

    func isWellFormed(bounds: LightBounds = .standard) -> Bool {
        guard !segments.isEmpty, dutyCycle.isFinite, bounds.dutyRange.contains(dutyCycle) else { return false }
        return segments.allSatisfy {
            $0.weight.isFinite && $0.weight > 0
                && bounds.frequencyRange.contains($0.startHz) && bounds.frequencyRange.contains($0.endHz)
                && (0...1).contains($0.startIntensity) && (0...1).contains($0.endIntensity)
        }
    }

    /// Frequency and relative intensity `fraction` (0...1) of the way through the light.
    func profile(at fraction: Double) -> (hz: Double, intensity: Double) {
        let total = segments.reduce(0) { $0 + $1.weight }
        guard total > 0, let last = segments.last else { return (0, 0) }
        var start = 0.0
        let target = min(max(fraction, 0), 1) * total
        for (index, segment) in segments.enumerated() {
            let end = start + segment.weight
            if target < end || index == segments.count - 1 {
                let p = min(max((target - start) / segment.weight, 0), 1)
                return (segment.startHz + (segment.endHz - segment.startHz) * p,
                        segment.startIntensity + (segment.endIntensity - segment.startIntensity) * p)
            }
            start = end
        }
        return (last.endHz, last.endIntensity)
    }

    /// A user-defined glide between two frequencies.
    static func custom(startHz: Double, endHz: Double, dutyCycle: Double = 0.5) -> LightProgram {
        LightProgram(
            id: LightProgramCatalog.customID,
            name: "Custom",
            summary: "Your own glide from \(format(startHz)) to \(format(endHz)) Hz.",
            dutyCycle: dutyCycle,
            segments: [Segment(weight: 1, startHz: startHz, endHz: endHz)]
        )
    }
}

/// Hard global limits every program and plan must respect, whatever its source.
struct LightBounds: Hashable {
    /// Flashes per second. Photosensitive responses are most often reported around 15–25 Hz;
    /// built-in programs stay below 15 Hz and the UI warns when a custom rate goes above it.
    var frequencyRange: ClosedRange<Double>
    var dutyRange: ClosedRange<Double>
    /// Shortest planned on or off interval accepted; not an optical timing guarantee.
    var minimumPulse: TimeInterval
    var maximumLightDuration: TimeInterval
    var brightnessCeiling: Float

    static let standard = LightBounds(
        frequencyRange: 1...20,
        dutyRange: 0.2...0.7,
        minimumPulse: 0.012,
        maximumLightDuration: 60 * 60,
        brightnessCeiling: 1
    )
}

/// A program rendered for one session: absolute on/off edges from session start.
struct LightPlan {
    struct Edge: Hashable {
        /// Seconds from session start.
        var time: TimeInterval
        /// Fraction of `peakTorchLevel`, 0 means torch off.
        var level: Float
    }

    let program: LightProgram
    let preparationDelay: TimeInterval
    let lightDuration: TimeInterval
    /// Requested `AVCaptureDevice` torch level at relative level 1 (the brightness setting).
    let peakTorchLevel: Float
    let fadeIn: TimeInterval
    let fadeOut: TimeInterval
    let edges: [Edge]

    var totalDuration: TimeInterval { preparationDelay + lightDuration }

    private static let tolerance: TimeInterval = 1e-9

    init(program: LightProgram, preparationDelay: TimeInterval, lightDuration: TimeInterval, peakTorchLevel: Float, fadeIn: TimeInterval = 20, fadeOut: TimeInterval = 20, bounds: LightBounds = .standard) {
        self.program = program
        self.preparationDelay = max(0, preparationDelay)
        self.lightDuration = max(0, min(lightDuration, bounds.maximumLightDuration))
        self.peakTorchLevel = peakTorchLevel
        self.fadeIn = max(0, fadeIn)
        self.fadeOut = max(0, fadeOut)
        edges = Self.render(program: program, delay: self.preparationDelay, duration: self.lightDuration, fadeIn: self.fadeIn, fadeOut: self.fadeOut, bounds: bounds)
    }

    /// Builds a plan for a session of `sessionDuration`: a lead-in in darkness, light, then a
    /// quiet outro so the session ends without flicker.
    static func forSession(program: LightProgram, sessionDuration: TimeInterval, brightness: Float, leadIn: TimeInterval = 5, maximumLight: TimeInterval? = nil, fade: TimeInterval = 8, bounds: LightBounds = .standard) -> LightPlan {
        let outro = min(90, sessionDuration * 0.1)
        var light = sessionDuration - leadIn - outro
        if let maximumLight { light = min(light, maximumLight) }
        return LightPlan(program: program, preparationDelay: leadIn, lightDuration: max(light, 0), peakTorchLevel: brightness, fadeIn: fade, fadeOut: fade, bounds: bounds)
    }

    func isWellFormed(bounds: LightBounds = .standard) -> Bool {
        guard program.isWellFormed(bounds: bounds),
              peakTorchLevel.isFinite, peakTorchLevel > 0, peakTorchLevel <= bounds.brightnessCeiling,
              preparationDelay.isFinite, lightDuration.isFinite,
              lightDuration > 0, lightDuration <= bounds.maximumLightDuration,
              !edges.isEmpty
        else { return false }
        return edges.allSatisfy { $0.level.isFinite && (0...1).contains($0.level) }
    }

    /// Relative level `elapsed` seconds after session start; nil once the light has finished.
    func relativeLevel(at elapsed: TimeInterval) -> Float? {
        guard elapsed < totalDuration - Self.tolerance else { return nil }
        guard let index = lastEdgeIndex(atOrBefore: elapsed) else { return 0 }
        return edges[index].level
    }

    /// The next instant at which the level changes or the light ends. Drift-free: computed
    /// from absolute edge times, never by accumulating delays.
    func nextBoundary(after elapsed: TimeInterval) -> TimeInterval? {
        guard elapsed < totalDuration - Self.tolerance else { return nil }
        let next = (lastEdgeIndex(atOrBefore: elapsed).map { $0 + 1 }) ?? 0
        return next < edges.count ? min(edges[next].time, totalDuration) : totalDuration
    }

    /// Nominal flash frequency at `elapsed`, or nil outside the light.
    func frequency(at elapsed: TimeInterval) -> Double? {
        guard lightDuration > 0, elapsed >= preparationDelay, elapsed < totalDuration else { return nil }
        return program.profile(at: (elapsed - preparationDelay) / lightDuration).hz
    }

    private func lastEdgeIndex(atOrBefore elapsed: TimeInterval) -> Int? {
        var low = 0, high = edges.count - 1, found: Int?
        while low <= high {
            let mid = (low + high) / 2
            if edges[mid].time <= elapsed + Self.tolerance {
                found = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return found
    }

    private static func render(program: LightProgram, delay: TimeInterval, duration: TimeInterval, fadeIn: TimeInterval, fadeOut: TimeInterval, bounds: LightBounds) -> [Edge] {
        guard duration > 0, program.isWellFormed(bounds: bounds) else { return [] }
        var edges: [Edge] = []
        var t = 0.0
        while duration - t >= bounds.minimumPulse {
            let profile = program.profile(at: t / duration)
            let hz = min(max(profile.hz, bounds.frequencyRange.lowerBound), bounds.frequencyRange.upperBound)
            let period = 1 / hz
            let on = max(period * program.dutyCycle, bounds.minimumPulse)
            let rampIn = fadeIn > 0 ? min(1, t / fadeIn) : 1
            let rampOut = fadeOut > 0 ? min(1, (duration - t) / fadeOut) : 1
            // Fades start at half brightness so the flicker is clearly there from the first flash.
            let envelope = 0.5 + 0.5 * min(rampIn, rampOut)
            let level = Float(min(max(profile.intensity * envelope, 0), 1))
            if level > 0 {
                edges.append(Edge(time: delay + t, level: level))
                if t + on < duration { edges.append(Edge(time: delay + t + on, level: 0)) }
            }
            t += period
        }
        return edges
    }
}

enum LightProgramCatalog {
    static let customID = "custom"

    static let relax = LightProgram(
        id: "relax",
        name: "Unwind",
        summary: "Starts in alpha around 10 Hz and slowly settles toward 6 Hz, then lifts gently at the end.",
        dutyCycle: 0.5,
        segments: [
            .init(weight: 1, startHz: 10, endHz: 9),
            .init(weight: 3, startHz: 9, endHz: 7),
            .init(weight: 3, startHz: 7, endHz: 6),
            .init(weight: 2, startHz: 6, endHz: 8),
            .init(weight: 1, startHz: 8, endHz: 10)
        ]
    )

    static let focus = LightProgram(
        id: "focus",
        name: "Steady",
        summary: "Holds a steady 10–12 Hz alpha rhythm for clear, settled attention.",
        dutyCycle: 0.5,
        segments: [
            .init(weight: 1, startHz: 12, endHz: 10),
            .init(weight: 6, startHz: 10, endHz: 10),
            .init(weight: 2, startHz: 10, endHz: 11),
            .init(weight: 1, startHz: 11, endHz: 10)
        ]
    )

    static let explore = LightProgram(
        id: "explore",
        name: "Explore",
        summary: "Builds to vivid 10–12 Hz flicker, where imagery tends to be strongest, then eases down.",
        dutyCycle: 0.4,
        segments: [
            .init(weight: 1, startHz: 8, endHz: 10),
            .init(weight: 2, startHz: 10, endHz: 12),
            .init(weight: 2, startHz: 12, endHz: 10),
            .init(weight: 3, startHz: 10, endHz: 10),
            .init(weight: 2, startHz: 10, endHz: 7)
        ]
    )

    static let deep = LightProgram(
        id: "deep",
        name: "Deep",
        summary: "Descends from 8 Hz into slow 4–5 Hz theta flicker and back up.",
        dutyCycle: 0.5,
        segments: [
            .init(weight: 2, startHz: 8, endHz: 6),
            .init(weight: 3, startHz: 6, endHz: 4.5),
            .init(weight: 3, startHz: 4.5, endHz: 6),
            .init(weight: 2, startHz: 6, endHz: 8)
        ]
    )

    static let sleep = LightProgram(
        id: "sleep",
        name: "Drift off",
        summary: "Slows from 6 Hz to around 3 Hz and dims as it goes, then switches itself off.",
        dutyCycle: 0.5,
        segments: [
            .init(weight: 2, startHz: 6, endHz: 4, startIntensity: 1, endIntensity: 0.8),
            .init(weight: 5, startHz: 4, endHz: 3, startIntensity: 0.8, endIntensity: 0.5),
            .init(weight: 3, startHz: 3, endHz: 2, startIntensity: 0.5, endIntensity: 0.25)
        ]
    )

    static let all: [LightProgram] = [relax, focus, explore, deep, sleep]

    static func program(id: String) -> LightProgram? {
        all.first { $0.id == id }
    }

    static func recommended(for intent: SessionIntent) -> LightProgram {
        switch intent {
        case .calm: return relax
        case .focus: return focus
        case .reflect: return explore
        case .sleep: return sleep
        }
    }

    /// Sleep light switches itself off after this long so nobody is flickered while asleep.
    static let sleepLightLimit: TimeInterval = 20 * 60
}

/// Contraindication checklist. Answering "yes" to any question blocks light. Passing it does
/// not make light safe; it only excludes people known to be at higher risk.
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

    /// How long a completed safety check is remembered before it must be repeated.
    static let validity: TimeInterval = 30 * 24 * 60 * 60

    static func isCurrent(screenedAt: Date?, now: Date = Date()) -> Bool {
        guard let screenedAt else { return false }
        return now.timeIntervalSince(screenedAt) < validity && screenedAt <= now
    }
}

enum LightUnavailableReason: Error, Hashable {
    case disabledInThisBuild
    case noProgram
    case invalidProgram
    case consentMissing
    case deviceThermalState
    case sessionNotRunning
    case stoppedThisSession
    /// A previous off request failed and the user has not yet confirmed the torch is off.
    case shutdownUnconfirmed
    case hardware(TorchError)

    var message: String {
        switch self {
        case .disabledInThisBuild:
            return "Light isn't available in this build, so this session is audio only."
        case .noProgram, .invalidProgram:
            return "That light program can't run, so this session is audio only."
        case .consentMissing:
            return "Light needs the safety check first, so this session is audio only."
        case .deviceThermalState:
            return "Your device is warm, so light stays off for now."
        case .sessionNotRunning:
            return "Light can only start with a running session."
        case .stoppedThisSession:
            return "Light stopped earlier in this session, so it stays off until a new session."
        case .shutdownUnconfirmed:
            return "Light is blocked until you confirm the flashlight from an earlier session is off."
        case .hardware(let error):
            return error.localizedDescription
        }
    }
}

/// Pure gate deciding whether a light run may begin.
enum LightGate {
    static func evaluate(
        buildAllowsLight: Bool = LightFeature.buildAllowsLight,
        program: LightProgram?,
        consented: Bool,
        thermal: ProcessInfo.ThermalState,
        bounds: LightBounds = .standard
    ) -> Result<LightProgram, LightUnavailableReason> {
        guard buildAllowsLight else { return .failure(.disabledInThisBuild) }
        guard let program else { return .failure(.noProgram) }
        guard program.isWellFormed(bounds: bounds) else { return .failure(.invalidProgram) }
        guard consented else { return .failure(.consentMissing) }
        guard thermal == .nominal || thermal == .fair else { return .failure(.deviceThermalState) }
        return .success(program)
    }
}

enum LightFeature {
    /// Compile-time switch. Only builds compiled with `AFTERGLOW_LIGHT_RESEARCH` (the project sets
    /// it for the Debug configuration, which Xcode uses when you press Run) can run light.
    /// Release/Archive builds never can.
    static var buildAllowsLight: Bool {
        #if AFTERGLOW_LIGHT_RESEARCH
        return true
        #else
        return false
        #endif
    }

    static var isAvailable: Bool { buildAllowsLight }

    static var statusTitle: String {
        isAvailable ? "Flicker light" : "Light mode is not available"
    }

    static var statusExplanation: String {
        isAvailable ? disclosure : releaseExplanation
    }

    static let releaseExplanation = """
    Afterglow is audio-only in this build. Light is enabled only in development builds \
    installed from Xcode. Flashing light can trigger seizures, including in people with no \
    known history.
    """

    static let disclosure = """
    Light mode flashes the phone's flashlight through your closed eyelids, gliding between \
    frequencies over the session (built-in programs stay at 2–14 Hz; custom rates go up to \
    20 Hz), with a short dark lead-in and a fade in and out. These \
    programs are original designs informed by published flicker research; they are not \
    Lumenate's sequences and not a validated or medical treatment. Flashing light can trigger \
    seizures, including in people with no known history.
    """
}
