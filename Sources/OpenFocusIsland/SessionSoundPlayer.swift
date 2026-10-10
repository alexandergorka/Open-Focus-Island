import AVFoundation

enum SessionSoundEvent: String, CaseIterable {
    case focusCompleted, breakCompleted

    var filename: String {
        switch self {
        case .focusCompleted: "focus-completed.caf"
        case .breakCompleted: "break-completed.caf"
        }
    }
}

enum SessionSoundPlayerError: Error, Equatable, LocalizedError {
    case missingResource(String)
    case invalidAudio(String)
    case playbackFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingResource(let filename): "Sound file missing: \(filename)"
        case .invalidAudio(let filename): "Sound file is invalid: \(filename)"
        case .playbackFailed(let filename): "Sound could not be played: \(filename)"
        }
    }
}

@MainActor
protocol SessionSoundPlaying: AnyObject {
    func play(_ event: SessionSoundEvent, enabled: Bool) throws
}

@MainActor
final class SessionSoundPlayer: SessionSoundPlaying {
    private let bundle: Bundle
    private let playback: (AVAudioPlayer) -> Bool
    private var currentPlayer: AVAudioPlayer?

    init(bundle: Bundle = .main, playback: @escaping (AVAudioPlayer) -> Bool = { $0.play() }) {
        self.bundle = bundle
        self.playback = playback
    }

    func play(_ event: SessionSoundEvent, enabled: Bool) throws {
        guard enabled else { return }
        guard let url = bundle.url(forResource: event.filename, withExtension: nil, subdirectory: "Sounds") else {
            throw SessionSoundPlayerError.missingResource(event.filename)
        }
        let player: AVAudioPlayer
        do {
            player = try AVAudioPlayer(contentsOf: url)
        } catch {
            throw SessionSoundPlayerError.invalidAudio(event.filename)
        }
        player.volume = 1
        currentPlayer = player
        guard playback(player) else {
            throw SessionSoundPlayerError.playbackFailed(event.filename)
        }
    }
}
