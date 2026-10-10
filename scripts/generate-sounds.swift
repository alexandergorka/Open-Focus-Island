// Generates the two Open Focus Island completion sounds by pure synthesis (no samples, no network).
// Usage: swift scripts/generate-sounds.swift <output-directory>
// Writes focus-completed.caf and break-completed.caf (CAF, Linear PCM Int16, mono, 44.1 kHz).
// Byte-identical output is verified on one machine/toolchain only; the checked-in hashes are authoritative.
import AVFoundation
import Foundation

struct Sound {
    let file: String
    let total: Double                                   // seconds
    let notes: [(t: Double, hz: Double)]                // onset (s after lead), frequency
    let partials: [(mult: Double, amp: Double, decay: Double)] // frequency factor, amplitude, decay 1/s
}

let rate = 44100.0, lead = 0.005, attack = 0.015, fadeOut = 0.15, peakDBFS: Float = -3

let sounds = [
    // focusCompleted: 2 ascending notes C5 -> G5, partials 1x and 4x
    Sound(file: "focus-completed.caf", total: 1.2,
          notes: [(0.0, 523.25), (0.18, 783.99)],
          partials: [(1, 1.0, 3.5), (4, 0.25, 12)]),
    // breakCompleted: 3 descending notes G5 -> E5 -> C5, same marimba partials as focusCompleted (1x, 4x)
    Sound(file: "break-completed.caf", total: 1.4,
          notes: [(0.0, 783.99), (0.18, 659.25), (0.36, 523.25)],
          partials: [(1, 1.0, 3.5), (4, 0.25, 12)]),
]

func synthesize(_ sound: Sound) -> [Float] {
    var s = [Float](repeating: 0, count: Int(sound.total * rate))
    for note in sound.notes {
        let start = Int((lead + note.t) * rate)
        for i in start..<s.count {
            let t = Double(i - start) / rate
            let a = t < attack ? 0.5 - 0.5 * cos(Double.pi * t / attack) : 1 // raised-cosine attack
            var v = 0.0
            for p in sound.partials { v += p.amp * exp(-p.decay * t) * sin(2 * Double.pi * note.hz * p.mult * t) }
            s[i] += Float(a * v)
        }
    }
    let fo = Int(fadeOut * rate) // raised-cosine fade-out to exactly 0
    for i in 0..<fo { s[s.count - 1 - i] *= 0.5 - 0.5 * cos(Float.pi * Float(i) / Float(fo)) }
    let peak = s.map(abs).max() ?? 0
    let gain = pow(10, peakDBFS / 20) / peak // peak-normalize to -3 dBFS
    for i in s.indices { s[i] *= gain }
    return s
}

func writeCAF(_ s: [Float], to url: URL) throws {
    let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: 1,
                                   AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
    if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    let f = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
    guard let buf = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: AVAudioFrameCount(s.count)) else {
        throw CocoaError(.fileWriteUnknown)
    }
    buf.frameLength = AVAudioFrameCount(s.count)
    for i in 0..<s.count { buf.floatChannelData![0][i] = s[i] }
    try f.write(from: buf)
    f.close()
}

let args = CommandLine.arguments.dropFirst()
guard args.count == 1, let dir = args.first, !dir.isEmpty else {
    FileHandle.standardError.write("usage: swift scripts/generate-sounds.swift <output-directory>\n".data(using: .utf8)!)
    exit(2)
}
let outDir = URL(fileURLWithPath: dir, isDirectory: true)
var target = outDir.path
do {
    try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    for sound in sounds {
        let url = outDir.appendingPathComponent(sound.file)
        target = url.path
        do {
            try writeCAF(synthesize(sound), to: url)
        } catch {
            try? FileManager.default.removeItem(at: url) // no partial file left behind
            throw error
        }
        print("wrote \(url.path)")
    }
} catch {
    FileHandle.standardError.write("error: \(target): \(error.localizedDescription)\n".data(using: .utf8)!)
    exit(1)
}
