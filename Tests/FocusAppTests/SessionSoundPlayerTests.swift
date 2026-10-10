import AVFoundation
import XCTest
@testable import OpenFocusIsland

@MainActor
final class SessionSoundPlayerTests: XCTestCase {
    func testBothEventsLoadAndPlayDecodedCAF() throws {
        let bundle = try makeBundle()
        var played: [AVAudioPlayer] = []
        let player = SessionSoundPlayer(bundle: bundle) { audioPlayer in
            played.append(audioPlayer)
            return true
        }

        try player.play(.focusCompleted, enabled: true)
        try player.play(.breakCompleted, enabled: true)

        XCTAssertEqual(played.count, 2)
        XCTAssertEqual(played.compactMap(\.url).map(\.lastPathComponent), [
            "focus-completed.caf",
            "break-completed.caf",
        ])
        for audioPlayer in played {
            XCTAssertEqual(audioPlayer.volume, 1)
            XCTAssertEqual(audioPlayer.numberOfChannels, 1)
            XCTAssertEqual(audioPlayer.duration, 0.1, accuracy: 0.02)
        }
    }

    func testSelectedAssetsDecodeFromTemporaryBundle() throws {
        let bundle = try makeBundle(withFiles: false)
        let sourceSounds = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Assets/Sounds", isDirectory: true)
        let destination = try XCTUnwrap(bundle.resourceURL).appendingPathComponent("Sounds", isDirectory: true)
        for filename in ["focus-completed.caf", "break-completed.caf"] {
            try FileManager.default.copyItem(at: sourceSounds.appendingPathComponent(filename),
                                             to: destination.appendingPathComponent(filename))
        }

        var played: [AVAudioPlayer] = []
        let player = SessionSoundPlayer(bundle: bundle) { audioPlayer in
            played.append(audioPlayer)
            return true
        }
        try player.play(.focusCompleted, enabled: true)
        try player.play(.breakCompleted, enabled: true)

        XCTAssertEqual(played.map { $0.url?.lastPathComponent }, ["focus-completed.caf", "break-completed.caf"])
        for (audioPlayer, expectedDuration) in zip(played, [1.2, 1.4]) {
            XCTAssertEqual(audioPlayer.duration, expectedDuration, accuracy: 0.02)
            XCTAssertEqual(audioPlayer.numberOfChannels, 1)
        }
    }

    func testRetainsCurrentPlayerAfterPlaybackCall() throws {
        weak var playedPlayer: AVAudioPlayer?
        let player = SessionSoundPlayer(bundle: try makeBundle()) { audioPlayer in
            playedPlayer = audioPlayer
            return true
        }
        try player.play(.focusCompleted, enabled: true)
        XCTAssertNotNil(playedPlayer)
    }

    func testDisabledDoesNotLookUpResourcesOrPlay() throws {
        let player = SessionSoundPlayer(bundle: try makeBundle(withFiles: false)) { _ in
            XCTFail("disabled playback must not run")
            return false
        }
        XCTAssertNoThrow(try player.play(.focusCompleted, enabled: false))
    }

    func testMissingFileReportsMissingResource() throws {
        let player = SessionSoundPlayer(bundle: try makeBundle(withFiles: false))
        XCTAssertThrowsError(try player.play(.focusCompleted, enabled: true)) { error in
            XCTAssertEqual(error as? SessionSoundPlayerError, .missingResource("focus-completed.caf"))
        }
    }

    func testCorruptFileReportsInvalidAudio() throws {
        let bundle = try makeBundle()
        try Data("not a CAF".utf8).write(to: bundle.resourceURL!.appendingPathComponent("Sounds/focus-completed.caf"))
        let player = SessionSoundPlayer(bundle: bundle)
        XCTAssertThrowsError(try player.play(.focusCompleted, enabled: true)) { error in
            XCTAssertEqual(error as? SessionSoundPlayerError, .invalidAudio("focus-completed.caf"))
        }
    }

    func testFalsePlaybackReportsPlaybackFailure() throws {
        let player = SessionSoundPlayer(bundle: try makeBundle()) { _ in false }
        XCTAssertThrowsError(try player.play(.focusCompleted, enabled: true)) { error in
            XCTAssertEqual(error as? SessionSoundPlayerError, .playbackFailed("focus-completed.caf"))
        }
    }

    private func makeBundle(withFiles: Bool = true) throws -> Bundle {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let bundleURL = root.appendingPathComponent("Fixture.bundle", isDirectory: true)
        let soundsURL = bundleURL.appendingPathComponent("Contents/Resources/Sounds", isDirectory: true)
        try FileManager.default.createDirectory(at: soundsURL, withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": "test.SessionSoundPlayer.\(UUID().uuidString)", "CFBundlePackageType": "BNDL"]
        let plistData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try plistData.write(to: bundleURL.appendingPathComponent("Contents/Info.plist"))
        if withFiles {
            try writeCAF(to: soundsURL.appendingPathComponent("focus-completed.caf"))
            try writeCAF(to: soundsURL.appendingPathComponent("break-completed.caf"))
        }
        return try XCTUnwrap(Bundle(url: bundleURL))
    }

    private func writeCAF(to url: URL) throws {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44_100, channels: 1, interleaved: false)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let frames: AVAudioFrameCount = 4_410
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let samples = buffer.floatChannelData![0]
        for index in 0..<Int(frames) { samples[index] = sin(Float(index) * 0.04) * 0.1 }
        try file.write(from: buffer)
    }
}
