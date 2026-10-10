// Audits the Open Focus Island completion sounds against manifest.json and the S1 sound policy.
// Usage: swift scripts/check-sounds.swift [directory containing manifest.json]   (default: Assets/Sounds)
// Works on the source assets or on an app bundle's Contents/Resources/Sounds. Every listed file is fully
// decoded with AVFoundation. Exit 0 only if everything passes; 1 on any check failure; 2 on usage error.
import AVFoundation
import CryptoKit
import Foundation

// Design limits from the S1 policy. The manifest must declare exactly these values.
struct Policy: Decodable, Equatable {
    let container: String
    let sample_rates_hz: [Double]
    let duration_s_min: Double
    let duration_s_max: Double
    let sample_peak_dbfs_max: Double
    let clip_abs_threshold: Double
    let edge_sample_dbfs_max: Double
    let rise_ms_min: Double
    let rms_pair_diff_db_max: Double
}
let limits = Policy(container: "caf", sample_rates_hz: [44100, 48000], duration_s_min: 0.3, duration_s_max: 2.0,
                    sample_peak_dbfs_max: -1, clip_abs_threshold: 0.999, edge_sample_dbfs_max: -60,
                    rise_ms_min: 10, rms_pair_diff_db_max: 2)
let requiredEvents = ["focusCompleted", "breakCompleted"]

struct Entry: Decodable { let event, file, source, license, attribution, sha256: String }
struct Manifest: Decodable { let policy: Policy; let sounds: [Entry] }

func amp(_ dB: Double) -> Double { pow(10, dB / 20) }
func dB(_ x: Double) -> String { x <= 0 ? "-inf" : String(format: "%.4f", 20 * log10(x)) }

/// Checks one file; returns problems (empty = pass), a measurement summary and the audible-span RMS.
func check(_ e: Entry, in dir: URL) -> (problems: [String], summary: String, rms: Double?) {
    guard !e.file.isEmpty, !e.file.contains("/"), e.file != ".", e.file != ".." else {
        return (["file must be a plain file name inside the manifest directory"], "", nil)
    }
    var problems: [String] = []
    if e.source.isEmpty || e.license.isEmpty { problems.append("source/license missing in manifest") }
    let url = dir.appendingPathComponent(e.file)
    guard let data = try? Data(contentsOf: url) else { return (problems + ["file missing or unreadable"], "", nil) }
    let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    if hash != e.sha256.lowercased() { problems.append("sha256 \(hash) differs from manifest \(e.sha256)") }
    guard data.prefix(4) == Data("caff".utf8) else { return (problems + ["not a CAF container"], "", nil) }

    let file: AVAudioFile
    do { file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false) }
    catch { return (problems + ["cannot decode: \(error.localizedDescription)"], "", nil) }
    let d = file.fileFormat.streamDescription.pointee
    let rate = d.mSampleRate
    let isFloat = d.mFormatFlags & kAudioFormatFlagIsFloat != 0
    let format = "LPCM=\(d.mFormatID == kAudioFormatLinearPCM) \(isFloat ? "float" : "int")\(d.mBitsPerChannel) channels=\(d.mChannelsPerFrame) rate=\(Int(rate))"
    guard d.mFormatID == kAudioFormatLinearPCM, !isFloat, d.mBitsPerChannel == 16, d.mChannelsPerFrame == 1,
          limits.sample_rates_hz.contains(rate) else {
        return (problems + ["format \(format), expected Linear PCM int16 mono 44100/48000 Hz"], "", nil)
    }

    // Validate untrusted CAF frame counts before narrowing to AVAudioFrameCount or allocating.
    guard file.length > 0 else { return (problems + ["no audio frames"], "", nil) }
    let maxFrames = Int64(rate * limits.duration_s_max)
    guard file.length <= maxFrames else {
        return (problems + ["declared frame count \(file.length) exceeds \(maxFrames) frames (duration limit)"], "", nil)
    }
    // Decode the complete content.
    guard let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
        return (problems + ["no audio frames"], "", nil)
    }
    do { try file.read(into: buf) } catch { return (problems + ["decode failed: \(error.localizedDescription)"], "", nil) }
    guard Int64(buf.frameLength) == file.length else {
        return (problems + ["decoded \(buf.frameLength) of \(file.length) frames (truncated?)"], "", nil)
    }
    let s = UnsafeBufferPointer(start: buf.floatChannelData![0], count: Int(buf.frameLength)).map { Double(abs($0)) }
    let n = s.count

    let duration = Double(n) / rate
    let peak = s.max() ?? 0
    let clipped = s.filter { $0 >= limits.clip_abs_threshold }.count
    let edge = amp(limits.edge_sample_dbfs_max)
    // Rise (S2 definition): onset at global peak -40 dB, then first sample >= local peak -1 dB within 100 ms.
    let onset = s.firstIndex { $0 >= peak * amp(-40) } ?? 0
    let window = onset..<min(n, onset + Int(rate * 0.1))
    let localPeak = s[window].max() ?? 0
    let reach = window.first { s[$0] >= localPeak * amp(-1) } ?? onset
    let rise = Double(reach - onset) / rate * 1000
    // RMS over the audible span (> -60 dBFS).
    var rms: Double?
    if let first = s.firstIndex(where: { $0 > edge }), let last = s.lastIndex(where: { $0 > edge }) {
        rms = sqrt(s[first...last].reduce(0) { $0 + $1 * $1 } / Double(last - first + 1))
    }

    if duration < limits.duration_s_min || duration > limits.duration_s_max {
        problems.append(String(format: "duration %.6f s outside %.1f-%.1f s", duration, limits.duration_s_min, limits.duration_s_max))
    }
    if peak > amp(limits.sample_peak_dbfs_max) { problems.append("sample peak \(dB(peak)) dBFS > \(limits.sample_peak_dbfs_max) dBFS") }
    if clipped > 0 { problems.append("\(clipped) clipped samples (|x| >= \(limits.clip_abs_threshold))") }
    if s[0] > edge || s[n - 1] > edge { problems.append("first/last sample \(dB(s[0]))/\(dB(s[n - 1])) dBFS not silent (<= \(limits.edge_sample_dbfs_max))") }
    if rise < limits.rise_ms_min { problems.append(String(format: "rise %.4f ms < %.0f ms (abrupt onset)", rise, limits.rise_ms_min)) }
    if rms == nil { problems.append("no audible content") }

    let summary = String(format: "CAF int16 mono %d Hz, frames=%d duration_s=%.6f ", Int(rate), n, duration)
        + "sample_peak_dbfs=\(dB(peak)) clipped=\(clipped) first_dbfs=\(dB(s[0])) last_dbfs=\(dB(s[n - 1])) "
        + String(format: "rise_ms=%.4f ", rise) + "rms_dbfs=\(dB(rms ?? 0))"
    return (problems, summary, rms)
}

let args = CommandLine.arguments.dropFirst()
guard args.count <= 1 else {
    FileHandle.standardError.write("usage: swift scripts/check-sounds.swift [directory with manifest.json]\n".data(using: .utf8)!)
    exit(2)
}
let dir = URL(fileURLWithPath: args.first ?? "Assets/Sounds", isDirectory: true)
let manifestURL = dir.appendingPathComponent("manifest.json")
print("check-sounds: \(manifestURL.path)")

let manifest: Manifest
do { manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL)) }
catch { print("FAIL manifest.json: missing or invalid: \(error)"); exit(1) }

var failures = 0
func fail(_ message: String) { print("FAIL " + message); failures += 1 }

if manifest.policy != limits { fail("manifest.json: policy limits differ from the check's limits \(limits)") }
let events = manifest.sounds.map(\.event)
for ev in requiredEvents where !events.contains(ev) { fail("manifest.json: event \(ev) missing") }
for ev in Set(events) where events.filter({ $0 == ev }).count > 1 { fail("manifest.json: event \(ev) listed more than once") }
for ev in Set(events) where !requiredEvents.contains(ev) { fail("manifest.json: unknown event \(ev)") }

var rmsByEvent: [String: Double] = [:]
for entry in manifest.sounds {
    let r = check(entry, in: dir)
    if r.problems.isEmpty { print("PASS \(entry.file) (\(entry.event)): \(r.summary)") }
    else { fail("\(entry.file) (\(entry.event)): " + r.problems.joined(separator: "; ") + (r.summary.isEmpty ? "" : " [\(r.summary)]")) }
    if let rms = r.rms { rmsByEvent[entry.event] = rms }
}
if let a = rmsByEvent["focusCompleted"], let b = rmsByEvent["breakCompleted"] {
    let diff = abs(20 * log10(a / b))
    if diff > limits.rms_pair_diff_db_max { fail(String(format: "pair: RMS difference %.4f dB > %.1f dB", diff, limits.rms_pair_diff_db_max)) }
    else { print(String(format: "PASS pair: RMS difference %.4f dB <= %.1f dB", diff, limits.rms_pair_diff_db_max)) }
}

print(failures == 0 ? "RESULT: PASS" : "RESULT: FAIL (\(failures) problem(s))")
exit(failures == 0 ? 0 : 1)
