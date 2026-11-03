import Foundation
import MediaPlayer

/// Lock screen / Control Center integration so a session can be paused and resumed without
/// unlocking the phone.
@MainActor
final class NowPlayingController {
    var onPlay: (@MainActor () -> Void)?
    var onPause: (@MainActor () -> Void)?

    private let commands = MPRemoteCommandCenter.shared()
    private let info = MPNowPlayingInfoCenter.default()
    private var targets: [(MPRemoteCommand, Any)] = []

    init() {
        setCommandsEnabled(false)
        register(commands.playCommand) { $0.onPlay?() }
        register(commands.pauseCommand) { $0.onPause?() }
        register(commands.togglePlayPauseCommand) { controller in
            if controller.isPlaying { controller.onPause?() } else { controller.onPlay?() }
        }
    }

    deinit {
        for (command, target) in targets { command.removeTarget(target) }
    }

    private var isPlaying = false

    func update(configuration: SessionConfiguration?, elapsed: TimeInterval, isPlaying: Bool) {
        self.isPlaying = isPlaying
        setCommandsEnabled(configuration != nil)
        guard let configuration else {
            info.nowPlayingInfo = nil
            return
        }
        info.nowPlayingInfo = [
            MPMediaItemPropertyTitle: configuration.title,
            MPMediaItemPropertyArtist: "Afterglow",
            MPMediaItemPropertyPlaybackDuration: configuration.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue
        ]
    }

    private func setCommandsEnabled(_ enabled: Bool) {
        commands.playCommand.isEnabled = enabled
        commands.pauseCommand.isEnabled = enabled
        commands.togglePlayPauseCommand.isEnabled = enabled
    }

    private func register(_ command: MPRemoteCommand, action: @escaping @MainActor (NowPlayingController) -> Void) {
        // The handler's calling thread is not documented, so hop explicitly to the main actor.
        let target = command.addTarget { [weak self] _ in
            guard self != nil else { return .commandFailed }
            Task { @MainActor [weak self] in
                guard let self else { return }
                action(self)
            }
            return .success
        }
        targets.append((command, target))
    }
}
