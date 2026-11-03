import XCTest
@testable import Afterglow

final class AmbientSynthTests: XCTestCase {
    private func render(_ synth: inout AmbientSynth, frames: Int) -> (left: [Float], right: [Float]) {
        var left = [Float](repeating: .nan, count: frames)
        var right = [Float](repeating: .nan, count: frames)
        left.withUnsafeMutableBufferPointer { l in
            right.withUnsafeMutableBufferPointer { r in
                synth.render(left: l.baseAddress!, right: r.baseAddress!, frameCount: frames)
            }
        }
        return (left, right)
    }

    func testEverySoundscapeIsFiniteBoundedAndAudible() {
        for soundscape in Soundscape.allCases {
            var synth = AmbientSynth(soundscape: soundscape, sampleRate: 48_000)
            synth.setTargetGain(1, fade: 0)
            let output = render(&synth, frames: 48_000)
            let samples = output.left + output.right
            XCTAssertTrue(samples.allSatisfy { $0.isFinite && abs($0) <= 1 }, "\(soundscape) produced invalid samples")
            let rms = sqrt(samples.reduce(0) { $0 + Double($1 * $1) } / Double(samples.count))
            XCTAssertGreaterThan(rms, 0.001, "\(soundscape) should be audible")
            XCTAssertLessThan(rms, 0.5, "\(soundscape) should stay gentle")
        }
    }

    func testSilentUntilFadedIn() {
        var synth = AmbientSynth(soundscape: .ember, sampleRate: 44_100)
        let output = render(&synth, frames: 1_024)
        XCTAssertTrue(output.left.allSatisfy { $0 == 0 })
        XCTAssertTrue(synth.isSilent)
    }

    func testFadeReachesTargetInRequestedTime() {
        var synth = AmbientSynth(soundscape: .drift, sampleRate: 1_000 * 8)
        synth.setTargetGain(1, fade: 1)
        _ = render(&synth, frames: 4_000)
        XCTAssertEqual(synth.gain, 0.5, accuracy: 0.01)
        _ = render(&synth, frames: 4_100)
        XCTAssertEqual(synth.gain, 1)

        synth.setTargetGain(0, fade: 0.5)
        _ = render(&synth, frames: 4_100)
        XCTAssertEqual(synth.gain, 0)
    }

    func testChimeSoundsEvenWhenAmbientIsSilentAndThenDecays() {
        var synth = AmbientSynth(soundscape: .hush, sampleRate: 8_000)
        synth.triggerChime()
        let start = render(&synth, frames: 800)
        XCTAssertGreaterThan(start.left.map(abs).max() ?? 0, 0.05)
        _ = render(&synth, frames: 8_000 * 60)
        XCTAssertTrue(synth.isSilent)
    }

    func testMonoOutputIsSupported() {
        var synth = AmbientSynth(soundscape: .tide, sampleRate: 48_000)
        synth.setTargetGain(1, fade: 0)
        var left = [Float](repeating: 0, count: 256)
        left.withUnsafeMutableBufferPointer { synth.render(left: $0.baseAddress!, right: nil, frameCount: 256) }
        XCTAssertTrue(left.allSatisfy(\.isFinite))
    }
}

final class SessionModelTests: XCTestCase {
    func testPresetCatalogIsConsistent() {
        let ids = PresetCatalog.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "Preset IDs must be unique; they are persisted in history")
        for preset in PresetCatalog.all {
            XCTAssertTrue(preset.durationOptionsMinutes.contains(preset.defaultMinutes), preset.id)
            XCTAssertEqual(PresetCatalog.preset(id: preset.id), preset)
        }
        XCTAssertNil(PresetCatalog.preset(id: "missing"))
    }

    func testConfigurationClampsDurationAndVolume() {
        let short = SessionConfiguration(presetID: "x", title: "x", soundscape: .ember, duration: 5, volume: 4)
        XCTAssertEqual(short.duration, SessionConfiguration.minimumDuration)
        XCTAssertEqual(short.volume, 1)
        let long = SessionConfiguration(presetID: "x", title: "x", soundscape: .ember, duration: 99_999, volume: -1)
        XCTAssertEqual(long.duration, SessionConfiguration.maximumDuration)
        XCTAssertEqual(long.volume, 0)

        let preset = PresetCatalog.all[0]
        XCTAssertEqual(SessionConfiguration(preset: preset).duration, TimeInterval(preset.defaultMinutes * 60))
        XCTAssertEqual(SessionConfiguration(preset: preset, minutes: 25).duration, 1_500)
    }

    func testRecordClampsListenedTime() {
        let record = SessionRecord(presetID: "x", title: "x", soundscape: .ember, startedAt: Date(), plannedDuration: 60, listenedDuration: 90, outcome: .completed)
        XCTAssertEqual(record.listenedDuration, 60)
    }

    func testArchiveRoundTripIsStable() throws {
        let archive = HistoryArchive(
            sessions: [SessionRecord(presetID: "settle", title: "Settle In", soundscape: .tide, startedAt: Date(timeIntervalSince1970: 1_700_000_000), plannedDuration: 600, listenedDuration: 600, outcome: .completed)],
            journal: [JournalEntry(createdAt: Date(timeIntervalSince1970: 1_700_000_100), mood: .bright, text: "ok")]
        )
        let data = try HistoryFile.makeEncoder().encode(archive)
        XCTAssertEqual(try HistoryFile.makeDecoder().decode(HistoryArchive.self, from: data), archive)
    }
}

@MainActor
final class SettingsStoreTests: XCTestCase {
    func testPersistsAndClamps() throws {
        let suite = "afterglow.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = SettingsStore(defaults: defaults)
        XCTAssertEqual(settings.defaultSoundscape, .ember)
        settings.defaultSoundscape = .hush
        settings.volume = 3
        settings.defaultMinutes = 500
        XCTAssertEqual(settings.volume, 1)
        XCTAssertEqual(settings.defaultMinutes, SettingsStore.minuteRange.upperBound)

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.defaultSoundscape, .hush)
        XCTAssertEqual(reloaded.volume, 1)
        XCTAssertEqual(reloaded.defaultMinutes, SettingsStore.minuteRange.upperBound)
    }
}
