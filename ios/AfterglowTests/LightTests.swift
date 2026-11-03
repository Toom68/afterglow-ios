import XCTest
@testable import Afterglow

final class FakeTorch: TorchDevice {
    var hasTorch = true
    var isTorchAvailable = true
    var maxAvailableLevel: Float = 1
    var failNextOn = false
    var failOff = false
    private(set) var levels: [Float] = []

    var current: Float { levels.last ?? 0 }

    func setLevel(_ level: Float) throws {
        if failOff && level == 0 {
            throw TorchError.configurationFailed("off rejected")
        }
        if failNextOn && level > 0 {
            failNextOn = false
            throw TorchError.configurationFailed("busy")
        }
        levels.append(level)
    }
}

/// Test fixture: a steady 1 Hz, 50% duty program.
let fixtureProgram = LightProgram(
    id: "fixture",
    name: "Fixture",
    summary: "unit-test fixture",
    dutyCycle: 0.5,
    segments: [.init(weight: 1, startHz: 1, endHz: 1)]
)

/// 2 s dark, then 10 s of 1 Hz flashes at torch level 0.5, without fades.
let fixturePlan = LightPlan(program: fixtureProgram, preparationDelay: 2, lightDuration: 10, peakTorchLevel: 0.5, fadeIn: 0, fadeOut: 0)

final class LightPolicyTests: XCTestCase {
    func testCatalogProgramsAreWellFormedDistinctAndVaryOverTheSession() {
        let ids = LightProgramCatalog.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertFalse(ids.contains(LightProgramCatalog.customID))
        for program in LightProgramCatalog.all {
            XCTAssertTrue(program.isWellFormed(), program.id)
            XCTAssertGreaterThan(program.highestHz, program.lowestHz, "\(program.id) should glide between frequencies")
            XCTAssertTrue(LightBounds.standard.frequencyRange.contains(program.lowestHz))
            XCTAssertTrue(LightBounds.standard.frequencyRange.contains(program.highestHz))
        }
    }

    func testEachIntentHasARecommendedProgram() {
        XCTAssertEqual(LightProgramCatalog.recommended(for: .calm).id, LightProgramCatalog.relax.id)
        XCTAssertEqual(LightProgramCatalog.recommended(for: .focus).id, LightProgramCatalog.focus.id)
        XCTAssertEqual(LightProgramCatalog.recommended(for: .reflect).id, LightProgramCatalog.explore.id)
        XCTAssertEqual(LightProgramCatalog.recommended(for: .sleep).id, LightProgramCatalog.sleep.id)
        XCTAssertLessThanOrEqual(LightProgramCatalog.sleep.highestHz, 6, "Sleep stays slow")
    }

    func testProfileInterpolatesAcrossWeightedSegments() {
        let program = LightProgram(id: "p", name: "p", summary: "", dutyCycle: 0.5, segments: [
            .init(weight: 1, startHz: 10, endHz: 8),
            .init(weight: 3, startHz: 8, endHz: 4, startIntensity: 1, endIntensity: 0.5)
        ])
        XCTAssertEqual(program.profile(at: 0).hz, 10, accuracy: 1e-9)
        XCTAssertEqual(program.profile(at: 0.125).hz, 9, accuracy: 1e-9)
        XCTAssertEqual(program.profile(at: 0.25).hz, 8, accuracy: 1e-9)
        XCTAssertEqual(program.profile(at: 1).hz, 4, accuracy: 1e-9)
        XCTAssertEqual(program.profile(at: 1).intensity, 0.5, accuracy: 1e-9)
        XCTAssertEqual(program.profile(at: 2).hz, 4, accuracy: 1e-9, "Clamped past the end")
    }

    func testPlanLevelsFollowDelayPulsesAndEnd() {
        XCTAssertEqual(fixturePlan.relativeLevel(at: -1), 0)
        XCTAssertEqual(fixturePlan.relativeLevel(at: 0), 0, "Dark during the lead-in")
        XCTAssertEqual(fixturePlan.relativeLevel(at: 1.9), 0)
        XCTAssertEqual(fixturePlan.relativeLevel(at: 2.0), 1)
        XCTAssertEqual(fixturePlan.relativeLevel(at: 2.4), 1)
        XCTAssertEqual(fixturePlan.relativeLevel(at: 2.5), 0)
        XCTAssertEqual(fixturePlan.relativeLevel(at: 3.2), 1)
        XCTAssertEqual(fixturePlan.relativeLevel(at: 11.7), 0)
        XCTAssertNil(fixturePlan.relativeLevel(at: 12))
        XCTAssertNil(fixturePlan.relativeLevel(at: 99))
    }

    func testBoundariesAreAbsoluteAndDriftFree() {
        XCTAssertEqual(fixturePlan.nextBoundary(after: 0), 2)
        XCTAssertEqual(fixturePlan.nextBoundary(after: 2), 2.5)
        XCTAssertEqual(fixturePlan.nextBoundary(after: 2.499), 2.5)
        XCTAssertEqual(fixturePlan.nextBoundary(after: 2.5), 3)
        XCTAssertEqual(fixturePlan.nextBoundary(after: 11.6), 12)
        XCTAssertNil(fixturePlan.nextBoundary(after: 12))

        var t = 0.0
        var count = 0
        while let next = fixturePlan.nextBoundary(after: t) {
            XCTAssertGreaterThan(next, t)
            t = next
            count += 1
        }
        XCTAssertEqual(t, 12, accuracy: 1e-6)
        XCTAssertEqual(count, 21, "10 on and 10 off edges, then the end")
    }

    func testFrequencyGlidesWithinOneSession() {
        let plan = LightPlan(program: .custom(startHz: 10, endHz: 5), preparationDelay: 0, lightDuration: 60, peakTorchLevel: 1, fadeIn: 0, fadeOut: 0)
        XCTAssertTrue(plan.isWellFormed())
        XCTAssertEqual(plan.frequency(at: 0) ?? 0, 10, accuracy: 0.01)
        XCTAssertEqual(plan.frequency(at: 59.9) ?? 0, 5, accuracy: 0.02)
        let onsets = plan.edges.filter { $0.level > 0 }.map(\.time)
        XCTAssertEqual(onsets[1] - onsets[0], 0.1, accuracy: 0.002, "About 10 Hz at the start")
        XCTAssertEqual(onsets[onsets.count - 1] - onsets[onsets.count - 2], 0.2, accuracy: 0.005, "About 5 Hz at the end")
        XCTAssertTrue(plan.edges.allSatisfy { $0.time >= 0 && $0.time <= plan.totalDuration })
        XCTAssertEqual(plan.edges.map(\.time), plan.edges.map(\.time).sorted())
    }

    func testFadesRampTheLightInAndOut() {
        let plan = LightPlan(program: .custom(startHz: 10, endHz: 10), preparationDelay: 0, lightDuration: 120, peakTorchLevel: 1, fadeIn: 20, fadeOut: 20)
        let onsets = plan.edges.filter { $0.level > 0 }
        XCTAssertEqual(onsets.first?.level ?? 0, 0.15, accuracy: 0.01, "Starts dim")
        XCTAssertEqual(plan.relativeLevel(at: 60.02) ?? 0, 1, accuracy: 1e-6, "Full in the middle")
        XCTAssertLessThan(onsets.last?.level ?? 1, 0.2, "Ends dim")
    }

    func testBoundsRejectUnsafeOrMalformedPrograms() {
        func valid(_ change: (inout LightProgram) -> Void) -> Bool {
            var program = fixtureProgram
            change(&program)
            return program.isWellFormed()
        }
        XCTAssertTrue(valid { _ in })
        XCTAssertFalse(valid { $0.segments = [] })
        XCTAssertFalse(valid { $0.segments[0].endHz = 20 }, "Above the 15 Hz ceiling")
        XCTAssertFalse(valid { $0.segments[0].startHz = 0.5 })
        XCTAssertFalse(valid { $0.segments[0].startHz = .nan })
        XCTAssertFalse(valid { $0.segments[0].weight = 0 })
        XCTAssertFalse(valid { $0.segments[0].startIntensity = 2 })
        XCTAssertFalse(valid { $0.dutyCycle = 0.95 })
        XCTAssertFalse(valid { $0.dutyCycle = .infinity })

        XCTAssertFalse(LightPlan(program: fixtureProgram, preparationDelay: 0, lightDuration: 10, peakTorchLevel: 1.5).isWellFormed())
        XCTAssertFalse(LightPlan(program: fixtureProgram, preparationDelay: 0, lightDuration: 10, peakTorchLevel: 0).isWellFormed())
        XCTAssertFalse(LightPlan(program: fixtureProgram, preparationDelay: 0, lightDuration: 0, peakTorchLevel: 0.5).isWellFormed())
        XCTAssertFalse(LightPlan(program: .custom(startHz: 30, endHz: 30), preparationDelay: 0, lightDuration: 10, peakTorchLevel: 0.5).isWellFormed())
        let long = LightPlan(program: fixtureProgram, preparationDelay: 0, lightDuration: 10 * 60 * 60, peakTorchLevel: 0.5)
        XCTAssertEqual(long.lightDuration, LightBounds.standard.maximumLightDuration, "Clamped to the hard limit")
    }

    func testHighestFrequencyPulsesStayAboveSchedulingResolution() {
        let plan = LightPlan(program: LightProgram(id: "fast", name: "fast", summary: "", dutyCycle: 0.2, segments: [.init(weight: 1, startHz: 15, endHz: 15)]), preparationDelay: 0, lightDuration: 5, peakTorchLevel: 1)
        let gaps = zip(plan.edges.dropFirst(), plan.edges).map { $0.time - $1.time }
        XCTAssertTrue(gaps.allSatisfy { $0 >= LightBounds.standard.minimumPulse - 1e-9 })
    }

    func testSessionPlanLeavesLeadInAndOutro() {
        let plan = LightPlan.forSession(program: LightProgramCatalog.relax, sessionDuration: 600, brightness: 0.6)
        XCTAssertEqual(plan.preparationDelay, 15)
        XCTAssertEqual(plan.lightDuration, 600 - 15 - 60, accuracy: 1e-9)
        XCTAssertEqual(plan.peakTorchLevel, 0.6)
        XCTAssertTrue(plan.isWellFormed())
        let sleep = LightPlan.forSession(program: LightProgramCatalog.sleep, sessionDuration: 45 * 60, brightness: 0.6, maximumLight: LightProgramCatalog.sleepLightLimit)
        XCTAssertEqual(sleep.lightDuration, LightProgramCatalog.sleepLightLimit)
    }

    func testScreeningRequiresEveryAnswerAndNoContraindication() {
        var screening = LightScreening()
        XCTAssertFalse(screening.isEligible)
        for question in LightScreening.Question.allCases { screening.answers[question] = false }
        XCTAssertTrue(screening.isEligible)
        screening.answers[.seizureHistory] = true
        XCTAssertFalse(screening.isEligible)
    }

    func testScreeningExpires() {
        let now = Date()
        XCTAssertFalse(LightScreening.isCurrent(screenedAt: nil, now: now))
        XCTAssertTrue(LightScreening.isCurrent(screenedAt: now.addingTimeInterval(-86_400), now: now))
        XCTAssertFalse(LightScreening.isCurrent(screenedAt: now.addingTimeInterval(-31 * 86_400), now: now))
        XCTAssertFalse(LightScreening.isCurrent(screenedAt: now.addingTimeInterval(86_400), now: now), "A future date is not trusted")
    }

    func testGateOrder() {
        func gate(build: Bool = true, program: LightProgram? = fixtureProgram, consent: Bool = true, thermal: ProcessInfo.ThermalState = .nominal) -> LightUnavailableReason? {
            if case .failure(let reason) = LightGate.evaluate(buildAllowsLight: build, program: program, consented: consent, thermal: thermal) {
                return reason
            }
            return nil
        }
        XCTAssertEqual(gate(build: false), .disabledInThisBuild)
        XCTAssertEqual(gate(program: nil), .noProgram)
        XCTAssertEqual(gate(program: .custom(startHz: 20, endHz: 25)), .invalidProgram)
        XCTAssertEqual(gate(consent: false), .consentMissing)
        XCTAssertEqual(gate(thermal: .serious), .deviceThermalState)
        XCTAssertEqual(gate(thermal: .critical), .deviceThermalState)
        XCTAssertNil(gate())
        XCTAssertNil(gate(thermal: .fair))
    }

    func testAvailabilityFollowsBuildFlag() {
        // Debug (tests) sets AFTERGLOW_LIGHT_RESEARCH; Release never does.
        XCTAssertEqual(LightFeature.isAvailable, LightFeature.buildAllowsLight)
        XCTAssertEqual(LightFeature.statusExplanation, LightFeature.isAvailable ? LightFeature.disclosure : LightFeature.releaseExplanation)
    }
}

@MainActor
final class TorchControllerTests: XCTestCase {
    private var now: TimeInterval = 0
    private var thermal: ProcessInfo.ThermalState = .nominal
    private var torch: FakeTorch!
    private var controller: TorchController!

    override func setUp() async throws {
        now = 0
        thermal = .nominal
        torch = FakeTorch()
        controller = TorchController(
            device: torch,
            clock: { [unowned self] in self.now },
            thermalState: { [unowned self] in self.thermal },
            notificationCenter: NotificationCenter(),
            schedulesTimers: false
        )
    }

    override func tearDown() async throws {
        controller?.hardStop()
        controller = nil
    }

    private func advance(to time: TimeInterval) {
        now = time
        controller.step()
    }

    func testRejectsMalformedPlans() {
        let bad = LightPlan(program: .custom(startHz: 30, endHz: 30), preparationDelay: 0, lightDuration: 10, peakTorchLevel: 0.5)
        XCTAssertThrowsError(try controller.start(bad)) { error in
            XCTAssertEqual(error as? TorchError, .protocolRejected)
        }
        XCTAssertFalse(controller.isRunning)
        XCTAssertEqual(torch.current, 0)
    }

    func testStaysOffDuringPreparationThenUsesPlanBrightness() throws {
        try controller.start(fixturePlan)
        XCTAssertEqual(torch.current, 0)
        advance(to: 1.5)
        XCTAssertEqual(torch.current, 0)
        advance(to: 2.0)
        XCTAssertEqual(torch.current, 0.5, accuracy: 0.0001)
        advance(to: 2.5)
        XCTAssertEqual(torch.current, 0)
        XCTAssertTrue(torch.levels.allSatisfy { $0 <= fixturePlan.peakTorchLevel })
    }

    func testFollowsLowerSystemLimitButNeverCompensatesUpward() throws {
        try controller.start(fixturePlan)
        torch.maxAvailableLevel = 0.01
        advance(to: 2.0)
        XCTAssertEqual(torch.current, 0.01, accuracy: 0.0001)
    }

    func testBrightnessCanChangeWhileRunning() throws {
        try controller.start(fixturePlan)
        advance(to: 2.0)
        XCTAssertEqual(torch.current, 0.5, accuracy: 0.0001)
        controller.setPeakLevel(0.2)
        advance(to: 2.5)
        advance(to: 3.0)
        XCTAssertEqual(torch.current, 0.2, accuracy: 0.0001)
        controller.setPeakLevel(5)
        advance(to: 3.5)
        advance(to: 4.0)
        XCTAssertEqual(torch.current, 1, accuracy: 0.0001, "Never above the hardware ceiling")
    }

    func testResumeHoldsDarkThenContinuesFromTheSessionPoint() throws {
        try controller.start(fixturePlan, at: 5.2, holdOff: 3)
        XCTAssertEqual(torch.current, 0)
        advance(to: 2.9)
        XCTAssertEqual(torch.current, 0, "Still in the dark hold")
        advance(to: 3.01)
        XCTAssertEqual(torch.current, 0.5, accuracy: 0.0001, "5.21 s into the plan is an on phase")
        XCTAssertEqual(controller.planElapsed ?? 0, 5.21, accuracy: 1e-9)
    }

    func testRefusesToStartAfterThePlanEnded() {
        XCTAssertThrowsError(try controller.start(fixturePlan, at: 12))
        XCTAssertFalse(controller.isRunning)
    }

    func testFinishesAndTurnsOff() throws {
        var reasons: [TorchStopReason] = []
        controller.onStop = { reasons.append($0) }
        try controller.start(fixturePlan)
        advance(to: 2.2)
        advance(to: 12)
        XCTAssertFalse(controller.isRunning)
        XCTAssertEqual(torch.current, 0)
        XCTAssertEqual(reasons, [.finished])
    }

    func testHardTimeoutOverridesPlan() throws {
        try controller.start(fixturePlan)
        advance(to: TorchController.hardTimeout)
        XCTAssertFalse(controller.isRunning)
        XCTAssertEqual(controller.lastStopReason, .timeout)
    }

    func testHardStopIsImmediateIdempotentAndFinal() throws {
        try controller.start(fixturePlan)
        advance(to: 2.1)
        XCTAssertGreaterThan(torch.current, 0)
        controller.hardStop()
        controller.hardStop()
        XCTAssertEqual(torch.current, 0)
        XCTAssertEqual(controller.lastStopReason, .requested)
        advance(to: 4.1)
        XCTAssertEqual(torch.current, 0, "A late step after stop must never relight")
    }

    func testConfigurationErrorsLeaveTorchOff() throws {
        torch.hasTorch = false
        XCTAssertThrowsError(try controller.start(fixturePlan)) { error in
            XCTAssertEqual(error as? TorchError, .noTorch)
        }
        torch.hasTorch = true
        try controller.start(fixturePlan)
        torch.failNextOn = true
        advance(to: 2.0)
        XCTAssertFalse(controller.isRunning)
        XCTAssertEqual(controller.lastStopReason, .failure(.configurationFailed("busy")))
        XCTAssertEqual(torch.current, 0)
    }

    func testRefusesToStartWhenWarm() {
        thermal = .serious
        XCTAssertThrowsError(try controller.start(fixturePlan)) { error in
            XCTAssertEqual(error as? TorchError, .thermal)
        }
    }

    func testThermalRiseStops() throws {
        try controller.start(fixturePlan)
        advance(to: 2.0)
        thermal = .serious
        advance(to: 2.5)
        XCTAssertEqual(controller.lastStopReason, .thermal)
        XCTAssertEqual(torch.current, 0)
    }

    func testTorchBecomingUnavailableStops() throws {
        try controller.start(fixturePlan)
        torch.isTorchAvailable = false
        advance(to: 2.0)
        XCTAssertEqual(controller.lastStopReason, .failure(.torchUnavailable))
    }

    func testFailedOffCommandIsReportedNotHidden() throws {
        try controller.start(fixturePlan)
        advance(to: 2.0)
        torch.failOff = true
        controller.hardStop()
        XCTAssertFalse(controller.isRunning)
        XCTAssertEqual(controller.offCommandError, .configurationFailed("off rejected"))

        torch.failOff = false
        controller.hardStop()
        XCTAssertNil(controller.offCommandError)
        XCTAssertEqual(torch.current, 0)
    }

    func testRefusesToStartIfTorchCannotBeTurnedOff() {
        torch.failOff = true
        XCTAssertThrowsError(try controller.start(fixturePlan))
        XCTAssertFalse(controller.isRunning)
        XCTAssertTrue(torch.levels.isEmpty, "Never turned on")
    }

    func testSystemLimitOfZeroStops() throws {
        try controller.start(fixturePlan)
        advance(to: 2.0)
        torch.maxAvailableLevel = 0
        advance(to: 3.0)
        XCTAssertEqual(controller.lastStopReason, .thermal)
        XCTAssertEqual(torch.current, 0)
    }
}
