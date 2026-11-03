import AVFoundation
import os

/// Abstraction over audio output so `SessionPlayer` can be unit tested with a fake.
protocol AmbientAudioControlling: AnyObject {
    /// Called on the main queue when output stopped for a reason the player did not request
    /// (media services reset, engine failed to restart after a route/configuration change).
    var onUnexpectedStop: ((String) -> Void)? { get set }

    /// `mixWithOthers` keeps the user's own music playing underneath Afterglow.
    func prepare(soundscape: Soundscape, volume: Float, mixWithOthers: Bool) throws
    func play(fadeIn: TimeInterval) throws
    func pause(fadeOut: TimeInterval)
    /// Plays the closing chime, fades out, then releases the audio session.
    func finish(withChime: Bool)
    /// Immediate teardown and audio session deactivation. Safe to call repeatedly.
    func stop()
    func setVolume(_ volume: Float)
}

/// Bridges main-thread control to the render thread without blocking it: the render thread
/// only ever *tries* the lock and keeps using its previous parameters if it is contended.
final class SynthRenderer {
    private struct Pending {
        var gain: Double?
        var fade: Double = 0
        var chime = false
    }

    private var synth: AmbientSynth
    private let lock: UnsafeMutablePointer<os_unfair_lock>
    private var pending = Pending()

    init(synth: AmbientSynth) {
        self.synth = synth
        lock = .allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock())
    }

    deinit {
        lock.deinitialize(count: 1)
        lock.deallocate()
    }

    func setGain(_ gain: Double, fade: Double) {
        os_unfair_lock_lock(lock)
        pending.gain = gain
        pending.fade = fade
        os_unfair_lock_unlock(lock)
    }

    func triggerChime() {
        os_unfair_lock_lock(lock)
        pending.chime = true
        os_unfair_lock_unlock(lock)
    }

    /// Render thread only.
    func render(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>?, frameCount: Int) {
        if os_unfair_lock_trylock(lock) {
            if let gain = pending.gain {
                synth.setTargetGain(gain, fade: pending.fade)
                pending.gain = nil
            }
            if pending.chime {
                synth.triggerChime()
                pending.chime = false
            }
            os_unfair_lock_unlock(lock)
        }
        synth.render(left: left, right: right, frameCount: frameCount)
    }
}

final class AmbientAudioEngine: AmbientAudioControlling {
    var onUnexpectedStop: ((String) -> Void)?

    private let session = AVAudioSession.sharedInstance()
    private var engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private var renderer: SynthRenderer?
    private var soundscape: Soundscape?
    private var volume: Float = 0.7
    private var wantsPlayback = false
    private var categoryOptions: AVAudioSession.CategoryOptions = []
    private var pendingWork: DispatchWorkItem?
    private var observers: [NSObjectProtocol] = []
    private let center: NotificationCenter
    private let log = Logger(subsystem: "Afterglow", category: "audio")

    init(notificationCenter: NotificationCenter = .default) {
        center = notificationCenter
        observeSystemEvents()
    }

    deinit {
        removeObservers()
        pendingWork?.cancel()
        engine.stop()
    }

    func prepare(soundscape: Soundscape, volume: Float, mixWithOthers: Bool) throws {
        pendingWork?.cancel()
        teardownGraph()
        self.soundscape = soundscape
        self.volume = min(max(volume, 0), 1)
        categoryOptions = mixWithOthers ? [.mixWithOthers] : []
        try session.setCategory(.playback, mode: .default, options: categoryOptions)
        try buildGraph(for: soundscape)
    }

    func play(fadeIn: TimeInterval) throws {
        pendingWork?.cancel()
        if renderer == nil, let soundscape {
            try buildGraph(for: soundscape)
        }
        guard let renderer else { throw AudioError.notPrepared }
        try session.setActive(true)
        if !engine.isRunning {
            try engine.start()
        }
        wantsPlayback = true
        renderer.setGain(1, fade: fadeIn)
    }

    func pause(fadeOut: TimeInterval) {
        wantsPlayback = false
        renderer?.setGain(0, fade: fadeOut)
        schedule(after: fadeOut + 0.1) { [weak self] in
            self?.engine.pause()
        }
    }

    func finish(withChime: Bool) {
        wantsPlayback = false
        let tail: TimeInterval
        if withChime {
            renderer?.triggerChime()
            renderer?.setGain(0, fade: 5)
            tail = 8
        } else {
            renderer?.setGain(0, fade: 1.5)
            tail = 1.7
        }
        schedule(after: tail) { [weak self] in self?.stop() }
    }

    func stop() {
        pendingWork?.cancel()
        pendingWork = nil
        wantsPlayback = false
        teardownGraph()
        do {
            try session.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            // Deactivation fails harmlessly if other I/O is still running; nothing to recover.
            log.debug("Audio session deactivation failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func setVolume(_ volume: Float) {
        self.volume = min(max(volume, 0), 1)
        engine.mainMixerNode.outputVolume = self.volume
    }

    // MARK: - Graph

    private func buildGraph(for soundscape: Soundscape) throws {
        let hardwareRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let sampleRate = hardwareRate > 0 ? hardwareRate : 48_000
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else {
            throw AudioError.formatUnavailable
        }
        let renderer = SynthRenderer(synth: AmbientSynth(soundscape: soundscape, sampleRate: sampleRate))
        let node = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard let left = buffers.first?.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            let right = buffers.count > 1 ? buffers[1].mData?.assumingMemoryBound(to: Float.self) : nil
            renderer.render(left: left, right: right, frameCount: Int(frameCount))
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = volume
        engine.prepare()
        self.renderer = renderer
        sourceNode = node
    }

    private func teardownGraph() {
        engine.stop()
        if let sourceNode {
            engine.detach(sourceNode)
        }
        sourceNode = nil
        renderer = nil
    }

    private func schedule(after delay: TimeInterval, _ work: @escaping () -> Void) {
        pendingWork?.cancel()
        let item = DispatchWorkItem(block: work)
        pendingWork = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    // MARK: - System events

    private func observeSystemEvents() {
        observers.append(center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.handleMediaServicesReset() })
        observers.append(center.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in self?.handleConfigurationChange() })
    }

    private func removeObservers() {
        for observer in observers {
            center.removeObserver(observer)
        }
        observers.removeAll()
    }

    /// The engine stops itself when the hardware format changes (e.g. new route). Restart it if
    /// the session should still be audible.
    private func handleConfigurationChange() {
        guard wantsPlayback else { return }
        do {
            try engine.start()
        } catch {
            wantsPlayback = false
            onUnexpectedStop?("Audio output changed and could not be restarted.")
        }
    }

    /// After a media services reset every audio object is invalid and must be recreated.
    private func handleMediaServicesReset() {
        let wasPlaying = wantsPlayback
        pendingWork?.cancel()
        wantsPlayback = false
        removeObservers()
        sourceNode = nil
        renderer = nil
        engine = AVAudioEngine()
        observeSystemEvents()
        if let soundscape {
            try? session.setCategory(.playback, mode: .default, options: categoryOptions)
            try? buildGraph(for: soundscape)
        }
        if wasPlaying {
            onUnexpectedStop?("The system audio service restarted.")
        }
    }

    enum AudioError: LocalizedError {
        case notPrepared
        case formatUnavailable

        var errorDescription: String? {
            switch self {
            case .notPrepared: return "Audio was not prepared."
            case .formatUnavailable: return "This device's audio format is not supported."
            }
        }
    }
}
