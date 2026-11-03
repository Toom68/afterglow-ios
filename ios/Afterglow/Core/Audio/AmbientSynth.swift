import Foundation

/// Real-time-safe procedural ambient generator. Every Afterglow sound is synthesised here from
/// sine oscillators and filtered noise, so the app ships no recorded or third-party audio.
///
/// `render` performs no allocation, locking, or Objective-C messaging and is safe to call from
/// the audio render thread. All state is plain value storage.
struct AmbientSynth {
    struct Voice {
        var frequency: Double
        var amplitude: Double
        var pan: Double
        var lfoRate: Double
        var lfoDepth: Double
        var phase: Double = 0
        var lfoPhase: Double = 0
    }

    let sampleRate: Double
    let soundscape: Soundscape

    /// Linear output gain actually applied, smoothed toward `targetGain`.
    private(set) var gain: Double = 0
    private(set) var targetGain: Double = 0
    private var gainStep: Double = 0

    private var voices: (Voice, Voice, Voice, Voice)
    private var noiseLevel: Double
    private var noiseCutoffBase: Double
    private var noiseCutoffDepth: Double
    private var noiseLfoRate: Double
    private var noiseLfoPhase: Double = 0
    private var rng: UInt32 = 0x9E37_79B9
    private var pink = (b0: 0.0, b1: 0.0, b2: 0.0, b3: 0.0, b4: 0.0, b5: 0.0, b6: 0.0)
    private var lowpassL: Double = 0
    private var lowpassR: Double = 0

    private var chimeEnvelope: Double = 0
    private var chimeDecay: Double
    private var chimePhases = (0.0, 0.0, 0.0)
    private let chimeFrequencies = (659.25, 659.25 * 2.76, 659.25 * 5.40)

    init(soundscape: Soundscape, sampleRate: Double) {
        let rate = max(8_000, sampleRate)
        self.sampleRate = rate
        self.soundscape = soundscape
        chimeDecay = exp(-1.0 / (3.5 * rate))
        let silent = Voice(frequency: 0, amplitude: 0, pan: 0, lfoRate: 0, lfoDepth: 0)
        switch soundscape {
        case .ember:
            voices = (
                Voice(frequency: 65.41, amplitude: 0.22, pan: -0.2, lfoRate: 0.050, lfoDepth: 0.35),
                Voice(frequency: 65.71, amplitude: 0.18, pan: 0.2, lfoRate: 0.037, lfoDepth: 0.35),
                Voice(frequency: 130.81, amplitude: 0.07, pan: 0.0, lfoRate: 0.071, lfoDepth: 0.6),
                Voice(frequency: 196.00, amplitude: 0.035, pan: 0.3, lfoRate: 0.029, lfoDepth: 0.8)
            )
            noiseLevel = 0.02; noiseCutoffBase = 300; noiseCutoffDepth = 100; noiseLfoRate = 0.05
        case .tide:
            voices = (
                Voice(frequency: 87.31, amplitude: 0.05, pan: 0, lfoRate: 0.083, lfoDepth: 0.9),
                silent, silent, silent
            )
            noiseLevel = 0.32; noiseCutoffBase = 650; noiseCutoffDepth = 520; noiseLfoRate = 0.083
        case .drift:
            voices = (
                Voice(frequency: 110.00, amplitude: 0.13, pan: -0.35, lfoRate: 0.031, lfoDepth: 0.5),
                Voice(frequency: 164.81, amplitude: 0.10, pan: 0.35, lfoRate: 0.043, lfoDepth: 0.6),
                Voice(frequency: 220.00, amplitude: 0.06, pan: -0.1, lfoRate: 0.057, lfoDepth: 0.7),
                Voice(frequency: 329.63, amplitude: 0.03, pan: 0.15, lfoRate: 0.023, lfoDepth: 0.9)
            )
            noiseLevel = 0.025; noiseCutoffBase = 2_000; noiseCutoffDepth = 600; noiseLfoRate = 0.02
        case .hush:
            voices = (
                Voice(frequency: 55.00, amplitude: 0.06, pan: 0, lfoRate: 0.021, lfoDepth: 0.5),
                silent, silent, silent
            )
            noiseLevel = 0.22; noiseCutoffBase = 420; noiseCutoffDepth = 80; noiseLfoRate = 0.017
        }
    }

    /// Sets the level to ramp to over `fade` seconds (0 = immediate). Values are clamped to 0...1.
    mutating func setTargetGain(_ value: Double, fade: Double) {
        targetGain = min(max(value, 0), 1)
        let frames = max(1, fade * sampleRate)
        gainStep = abs(targetGain - gain) / frames
        if fade <= 0 { gain = targetGain; gainStep = 0 }
    }

    mutating func triggerChime() {
        chimeEnvelope = 1
        chimePhases = (0, 0, 0)
    }

    var isSilent: Bool { gain <= 0.000_01 && targetGain <= 0.000_01 && chimeEnvelope < 0.000_1 }

    mutating func render(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>?, frameCount: Int) {
        let twoPi = 2 * Double.pi
        let inverseRate = 1 / sampleRate
        for frame in 0..<frameCount {
            advanceGain()

            var l = 0.0
            var r = 0.0
            Self.renderVoice(&voices.0, &l, &r, twoPi, inverseRate)
            Self.renderVoice(&voices.1, &l, &r, twoPi, inverseRate)
            Self.renderVoice(&voices.2, &l, &r, twoPi, inverseRate)
            Self.renderVoice(&voices.3, &l, &r, twoPi, inverseRate)

            if noiseLevel > 0 {
                noiseLfoPhase += noiseLfoRate * inverseRate
                if noiseLfoPhase >= 1 { noiseLfoPhase -= 1 }
                let swell = 0.5 - 0.5 * cos(twoPi * noiseLfoPhase)
                let cutoff = noiseCutoffBase + noiseCutoffDepth * (swell * 2 - 1)
                let coefficient = 1 - exp(-twoPi * max(20, cutoff) * inverseRate)
                let sourceL = nextPink()
                let sourceR = nextPink()
                lowpassL += coefficient * (sourceL - lowpassL)
                lowpassR += coefficient * (sourceR - lowpassR)
                let level = noiseLevel * (soundscape == .tide ? 0.25 + 0.75 * swell : 1)
                l += lowpassL * level
                r += lowpassR * level
            }

            var chime = 0.0
            if chimeEnvelope > 0.000_1 {
                chimePhases.0 += chimeFrequencies.0 * inverseRate
                chimePhases.1 += chimeFrequencies.1 * inverseRate
                chimePhases.2 += chimeFrequencies.2 * inverseRate
                chimePhases.0 -= chimePhases.0.rounded(.down)
                chimePhases.1 -= chimePhases.1.rounded(.down)
                chimePhases.2 -= chimePhases.2.rounded(.down)
                let e = chimeEnvelope
                chime = 0.18 * e * sin(twoPi * chimePhases.0)
                    + 0.06 * e * e * sin(twoPi * chimePhases.1)
                    + 0.025 * e * e * e * sin(twoPi * chimePhases.2)
                chimeEnvelope *= chimeDecay
            } else {
                chimeEnvelope = 0
            }

            left[frame] = Self.softClip((l * gain + chime) * 0.9)
            right?[frame] = Self.softClip((r * gain + chime) * 0.9)
        }
    }

    private mutating func advanceGain() {
        guard gain != targetGain else { return }
        if gain < targetGain {
            gain = min(targetGain, gain + gainStep)
        } else {
            gain = max(targetGain, gain - gainStep)
        }
    }

    /// Static so passing `&voices.n` never overlaps with an access to `self`.
    private static func renderVoice(_ voice: inout Voice, _ l: inout Double, _ r: inout Double, _ twoPi: Double, _ inverseRate: Double) {
        guard voice.amplitude > 0 else { return }
        voice.phase += voice.frequency * inverseRate
        voice.phase -= voice.phase.rounded(.down)
        voice.lfoPhase += voice.lfoRate * inverseRate
        voice.lfoPhase -= voice.lfoPhase.rounded(.down)
        let swell = 1 - voice.lfoDepth * (0.5 + 0.5 * cos(twoPi * voice.lfoPhase))
        let sample = sin(twoPi * voice.phase) * voice.amplitude * swell
        l += sample * (0.5 - 0.5 * voice.pan)
        r += sample * (0.5 + 0.5 * voice.pan)
    }

    /// Paul Kellet's refined pink noise filter over a xorshift white source.
    private mutating func nextPink() -> Double {
        rng ^= rng << 13
        rng ^= rng >> 17
        rng ^= rng << 5
        let white = Double(rng) / Double(UInt32.max) * 2 - 1
        pink.b0 = 0.99886 * pink.b0 + white * 0.0555179
        pink.b1 = 0.99332 * pink.b1 + white * 0.0750759
        pink.b2 = 0.96900 * pink.b2 + white * 0.1538520
        pink.b3 = 0.86650 * pink.b3 + white * 0.3104856
        pink.b4 = 0.55000 * pink.b4 + white * 0.5329522
        pink.b5 = -0.7616 * pink.b5 - white * 0.0168980
        let value = pink.b0 + pink.b1 + pink.b2 + pink.b3 + pink.b4 + pink.b5 + pink.b6 + white * 0.5362
        pink.b6 = white * 0.115926
        return value * 0.11
    }

    static func softClip(_ x: Double) -> Float {
        Float(tanh(x))
    }
}
