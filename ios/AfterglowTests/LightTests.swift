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

/// Test-only fixture. These numbers are arbitrary and are NOT proposed light parameters.
let lightFixture = LightProtocol(
    id: "fixture",
    version: 1,
    name: "Fixture",
    status: .unvalidatedEngineeringTest(rationale: "unit-test fixture only"),
    peakTorchLevel: 0.05,
    preparationDelay: 2,
    steps: [.init(relativeLevel: 1, duration: 1), .init(relativeLevel: 0, duration: 1)],
    lightDuration: 10
)

final class LightPolicyTests: XCTestCase {
    func testNothingIsMarkedValidated() {
        XCTAssertTrue(LightProtocolCatalog.validated.isEmpty)
        XCTAssertFalse(LightProtocolCatalog.engineeringSmokeTest.status.isValidated)
        XCTAssertFalse(LightProtocolCatalog.available.contains { $0.status.isValidated })
    }

    func testAvailabilityFollowsBuildFlag() {
        // Debug (tests) sets AFTERGLOW_LIGHT_RESEARCH; Release never does.
        XCTAssertEqual(LightFeature.isAvailable, LightFeature.buildAllowsLight)
        XCTAssertEqual(LightProtocolCatalog.experimental.isEmpty, !LightFeature.buildAllowsLight)
        if LightFeature.isAvailable {
            XCTAssertTrue(LightFeature.isExperimentalOnly)
            XCTAssertEqual(LightFeature.statusExplanation, LightFeature.experimentalDisclosure)
        } else {
            XCTAssertEqual(LightFeature.statusExplanation, LightFeature.releaseExplanation)
        }
    }

    func testEngineeringSmokeTestMatchesSpecifiedSettings() {
        let test = LightProtocolCatalog.engineeringSmokeTest
        XCTAssertEqual(test.peakTorchLevel, 0.02)
        XCTAssertEqual(test.preparationDelay, 10)
        XCTAssertEqual(test.lightDuration, 30)
        XCTAssertEqual(1 / test.cycleDuration, 3, accuracy: 0.0001, "nominal 3 Hz")
        let onTime = test.steps.filter { $0.relativeLevel > 0 }.reduce(0) { $0 + $1.duration }
        XCTAssertEqual(onTime / test.cycleDuration, 0.5, accuracy: 0.0001, "50% duty")
        XCTAssertTrue(test.isWellFormed(minimumStepDuration: TorchController.minimumStepDuration, levelCeiling: TorchController.brightnessCeiling, maximumLightDuration: TorchController.maximumLightDuration))
    }

    func testLevelsFollowDelayStepsAndEnd() {
        XCTAssertEqual(lightFixture.relativeLevel(at: 0), 0, "Off during preparation")
        XCTAssertEqual(lightFixture.relativeLevel(at: 1.9), 0)
        XCTAssertEqual(lightFixture.relativeLevel(at: 2.0), 1)
        XCTAssertEqual(lightFixture.relativeLevel(at: 3.5), 0)
        XCTAssertEqual(lightFixture.relativeLevel(at: 4.2), 1)
        XCTAssertNil(lightFixture.relativeLevel(at: 12))
        XCTAssertNil(lightFixture.relativeLevel(at: 99))
    }

    func testBoundariesAreAbsoluteAndDriftFree() {
        XCTAssertEqual(lightFixture.nextBoundary(after: 0), 2)
        XCTAssertEqual(lightFixture.nextBoundary(after: 2), 3)
        XCTAssertEqual(lightFixture.nextBoundary(after: 2.999), 3)
        XCTAssertEqual(lightFixture.nextBoundary(after: 3), 4)
        XCTAssertEqual(lightFixture.nextBoundary(after: 11.5), 12)
        XCTAssertNil(lightFixture.nextBoundary(after: 12))

        let smoke = LightProtocolCatalog.engineeringSmokeTest
        var t = 0.0
        var count = 0
        while let next = smoke.nextBoundary(after: t) {
            XCTAssertGreaterThan(next, t)
            t = next
            count += 1
        }
        XCTAssertEqual(t, 40, accuracy: 1e-6)
        XCTAssertEqual(count, 1 + 180, "One delay boundary, then 90 on and 90 off edges")
    }

    func testMalformedProtocolsAreRejected() {
        func wellFormed(_ change: (inout LightProtocol) -> Void) -> Bool {
            var light = lightFixture
            change(&light)
            return light.isWellFormed(minimumStepDuration: 0.1, levelCeiling: 0.2, maximumLightDuration: 60)
        }
        XCTAssertTrue(wellFormed { _ in })
        XCTAssertFalse(wellFormed { $0.steps = [] })
        XCTAssertFalse(wellFormed { $0.peakTorchLevel = 0.5 })
        XCTAssertFalse(wellFormed { $0.peakTorchLevel = .nan })
        XCTAssertFalse(wellFormed { $0.steps[0].duration = 0.01 })
        XCTAssertFalse(wellFormed { $0.steps[0].duration = .infinity })
        XCTAssertFalse(wellFormed { $0.steps[0].relativeLevel = 2 })
        XCTAssertFalse(wellFormed { $0.lightDuration = 600 })
        XCTAssertFalse(wellFormed { $0.preparationDelay = -1 })
    }

    func testScreeningRequiresEveryAnswerAndNoContraindication() {
        var screening = LightScreening()
        XCTAssertFalse(screening.isEligible)
        for question in LightScreening.Question.allCases { screening.answers[question] = false }
        XCTAssertTrue(screening.isEligible)
        screening.answers[.seizureHistory] = true
        XCTAssertFalse(screening.isEligible)
    }

    func testGateOrder() {
        func gate(build: Bool = true, catalog: [LightProtocol] = [lightFixture], id: String? = nil, screening: Bool = true, consent: Bool = true, thermal: ProcessInfo.ThermalState = .nominal) -> LightUnavailableReason? {
            if case .failure(let reason) = LightGate.evaluate(buildAllowsLight: build, protocolID: id, catalog: catalog, screeningPassed: screening, consentedThisSession: consent, thermal: thermal) {
                return reason
            }
            return nil
        }
        XCTAssertEqual(gate(build: false), .disabledInThisBuild)
        XCTAssertEqual(gate(catalog: []), .noProtocolAvailable)
        XCTAssertEqual(gate(id: "unknown"), .unknownProtocol)
        XCTAssertEqual(gate(screening: false), .screeningNotPassed)
        XCTAssertEqual(gate(consent: false), .consentMissing)
        XCTAssertEqual(gate(thermal: .serious), .deviceThermalState)
        XCTAssertEqual(gate(thermal: .critical), .deviceThermalState)
        XCTAssertNil(gate())
        XCTAssertNil(gate(id: "fixture", thermal: .fair))
    }

    func testReleaseBuildGateRefuses() {
        let result = LightGate.evaluate(buildAllowsLight: false, protocolID: nil, catalog: [LightProtocolCatalog.engineeringSmokeTest], screeningPassed: true, consentedThisSession: true, thermal: .nominal)
        XCTAssertEqual(result, .failure(.disabledInThisBuild))
    }
}

@MainActor
final class TorchControllerTests: XCTestCase {
    private var now: TimeInterval = 0
    private var thermal: ProcessInfo.ThermalState = .nominal
    private var torch: FakeTorch!
    private var controller: TorchController!
    private let catalog = [lightFixture]

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

    func testRejectsProtocolsOutsideAllowedCatalog() {
        XCTAssertThrowsError(try controller.start(lightFixture, allowedCatalog: [])) { error in
            XCTAssertEqual(error as? TorchError, .protocolRejected)
        }
        XCTAssertFalse(controller.isRunning)
        XCTAssertEqual(torch.current, 0)
    }

    func testStaysOffDuringPreparationThenUsesProtocolPeak() throws {
        try controller.start(lightFixture, allowedCatalog: catalog)
        XCTAssertEqual(torch.current, 0)
        advance(to: 1.5)
        XCTAssertEqual(torch.current, 0)
        advance(to: 2.0)
        XCTAssertEqual(torch.current, 0.05, accuracy: 0.0001)
        advance(to: 3.0)
        XCTAssertEqual(torch.current, 0)
        XCTAssertTrue(torch.levels.allSatisfy { $0 <= lightFixture.peakTorchLevel })
    }

    func testFollowsLowerSystemLimitButNeverCompensatesUpward() throws {
        try controller.start(lightFixture, allowedCatalog: catalog)
        torch.maxAvailableLevel = 0.01
        advance(to: 2.0)
        XCTAssertEqual(torch.current, 0.01, accuracy: 0.0001)
        XCTAssertTrue(torch.levels.allSatisfy { $0 <= TorchController.brightnessCeiling })
    }

    func testFinishesAndTurnsOff() throws {
        var reasons: [TorchStopReason] = []
        controller.onStop = { reasons.append($0) }
        try controller.start(lightFixture, allowedCatalog: catalog)
        advance(to: 2.5)
        advance(to: 12)
        XCTAssertFalse(controller.isRunning)
        XCTAssertEqual(torch.current, 0)
        XCTAssertEqual(reasons, [.finished])
    }

    func testHardTimeoutOverridesProtocol() throws {
        try controller.start(lightFixture, allowedCatalog: catalog)
        advance(to: TorchController.hardTimeout)
        XCTAssertFalse(controller.isRunning)
        XCTAssertEqual(controller.lastStopReason, .timeout)
    }

    func testHardStopIsImmediateIdempotentAndFinal() throws {
        try controller.start(lightFixture, allowedCatalog: catalog)
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
        XCTAssertThrowsError(try controller.start(lightFixture, allowedCatalog: catalog)) { error in
            XCTAssertEqual(error as? TorchError, .noTorch)
        }
        torch.hasTorch = true
        try controller.start(lightFixture, allowedCatalog: catalog)
        torch.failNextOn = true
        advance(to: 2.0)
        XCTAssertFalse(controller.isRunning)
        XCTAssertEqual(controller.lastStopReason, .failure(.configurationFailed("busy")))
        XCTAssertEqual(torch.current, 0)
    }

    func testRefusesToStartWhenWarm() {
        thermal = .serious
        XCTAssertThrowsError(try controller.start(lightFixture, allowedCatalog: catalog)) { error in
            XCTAssertEqual(error as? TorchError, .thermal)
        }
    }

    func testThermalRiseStops() throws {
        try controller.start(lightFixture, allowedCatalog: catalog)
        advance(to: 2.0)
        thermal = .serious
        advance(to: 2.5)
        XCTAssertEqual(controller.lastStopReason, .thermal)
        XCTAssertEqual(torch.current, 0)
    }

    func testTorchBecomingUnavailableStops() throws {
        try controller.start(lightFixture, allowedCatalog: catalog)
        torch.isTorchAvailable = false
        advance(to: 2.0)
        XCTAssertEqual(controller.lastStopReason, .failure(.torchUnavailable))
    }

    func testFailedOffCommandIsReportedNotHidden() throws {
        try controller.start(lightFixture, allowedCatalog: catalog)
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
        XCTAssertThrowsError(try controller.start(lightFixture, allowedCatalog: catalog))
        XCTAssertFalse(controller.isRunning)
        XCTAssertTrue(torch.levels.isEmpty, "Never turned on")
    }

    func testSystemLimitOfZeroStops() throws {
        try controller.start(lightFixture, allowedCatalog: catalog)
        advance(to: 2.0)
        torch.maxAvailableLevel = 0
        advance(to: 4.0)
        XCTAssertEqual(controller.lastStopReason, .thermal)
        XCTAssertEqual(torch.current, 0)
    }
}
