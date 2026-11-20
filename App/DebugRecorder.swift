import AVFoundation
import DrillCore

/// Debug mode: saves the video the phone saw, the skeleton it found on every frame, and the reps it counted,
/// into Documents/debug/<time>/ (visible in the Files app under "Squash Coach") so the vision can be checked offline.
final class DebugRecorder {
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var poses: FileHandle?
    private(set) var folder: URL?
    private var started = false
    private let encoder = Coding.encoder()

    func begin() {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("debug/\(f.string(from: Date()))")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        folder = dir
        let posesURL = dir.appendingPathComponent("poses.jsonl")
        FileManager.default.createFile(atPath: posesURL.path, contents: nil)
        poses = try? FileHandle(forWritingTo: posesURL)
        started = false; writer = nil; input = nil
    }

    func add(_ sample: CMSampleBuffer, pose: PoseFrame?) {
        guard let dir = folder, let pb = CMSampleBufferGetImageBuffer(sample) else { return }
        if writer == nil {
            let w = try? AVAssetWriter(outputURL: dir.appendingPathComponent("video.mp4"), fileType: .mp4)
            let settings: [String: Any] = [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: CVPixelBufferGetWidth(pb), AVVideoHeightKey: CVPixelBufferGetHeight(pb)]
            let i = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
            i.expectsMediaDataInRealTime = true
            if let w = w, w.canAdd(i) { w.add(i); writer = w; input = i }
        }
        guard let w = writer, let i = input else { return }
        if !started {
            guard w.startWriting() else { return }
            w.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sample)); started = true
        }
        if i.isReadyForMoreMediaData { i.append(sample) }
        if let p = pose, let data = try? encoder.encode(p) { poses?.write(data); poses?.write(Data("\n".utf8)) }
    }

    func end(reps: [RepStats], config: AnalyzerConfig) {
        guard let dir = folder else { return }
        try? poses?.close(); poses = nil
        if let data = try? encoder.encode(reps) { try? data.write(to: dir.appendingPathComponent("reps.json")) }
        if let data = try? encoder.encode(config) { try? data.write(to: dir.appendingPathComponent("config.json")) }
        input?.markAsFinished()
        let w = writer
        writer = nil; input = nil; folder = nil
        if started { w?.finishWriting {} }
    }
}
