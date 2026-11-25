import AVFoundation
import DrillCore

/// Saves what the phone saw during a set, so the tracking can be checked offline:
/// the video, the skeleton found on every frame, the reps counted and the settings,
/// in Documents/debug/<time>/ (visible in the Files app under "Squash Coach"). The newest 30 sets are kept.
/// All work happens on one queue, so frames arriving from the camera and Stop arriving from the screen cannot collide.
final class DebugRecorder {
    private let queue = DispatchQueue(label: "debug-recorder")
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var poses: FileHandle?
    private var folder: URL?
    private var started = false
    private let encoder = Coding.encoder()

    static var root: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("debug") }

    /// Starts a new recording and returns its folder.
    @discardableResult
    func begin() -> URL {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let dir = DebugRecorder.root.appendingPathComponent(f.string(from: Date()))
        queue.sync {
            DebugRecorder.prune(keep: 29)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let posesURL = dir.appendingPathComponent("poses.jsonl")
            FileManager.default.createFile(atPath: posesURL.path, contents: nil)
            poses = try? FileHandle(forWritingTo: posesURL)
            folder = dir; started = false; writer = nil; input = nil
        }
        return dir
    }

    /// One camera frame and the skeleton found on it.
    func add(_ sample: CMSampleBuffer, pose: PoseFrame?) {
        queue.sync {
            guard let dir = folder, let pb = CMSampleBufferGetImageBuffer(sample) else { return }
            if writer == nil {
                let w = try? AVAssetWriter(outputURL: dir.appendingPathComponent("video.mp4"), fileType: .mp4)
                let settings: [String: Any] = [
                    AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: CVPixelBufferGetWidth(pb), AVVideoHeightKey: CVPixelBufferGetHeight(pb),
                    AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 3_000_000],   // about 22 MB a minute: enough to check the tracking, small enough to share
                ]
                let i = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
                i.expectsMediaDataInRealTime = true
                if let w = w, w.canAdd(i) { w.add(i); writer = w; input = i }
            }
            if let w = writer, let i = input {
                if !started, w.startWriting() {
                    w.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sample)); started = true
                }
                if started, i.isReadyForMoreMediaData { i.append(sample) }
            }
            write(pose)
        }
    }

    /// A skeleton without a camera frame (demo mode).
    func addPose(_ pose: PoseFrame) {
        queue.sync { if folder != nil { write(pose) } }
    }

    private func write(_ pose: PoseFrame?) {
        guard let p = pose, let h = poses, let data = try? encoder.encode(p) else { return }
        try? h.write(contentsOf: data)
        try? h.write(contentsOf: Data("\n".utf8))
    }

    /// Finishes the recording. `done` is called (on an arbitrary queue) once every file is complete.
    func end(reps: [RepStats], config: AnalyzerConfig, label: SetLabel?, done: @escaping () -> Void) {
        queue.async {
            guard let dir = self.folder else { done(); return }
            try? self.poses?.close(); self.poses = nil
            if let data = try? self.encoder.encode(reps) { try? data.write(to: dir.appendingPathComponent("reps.json")) }
            if let data = try? self.encoder.encode(config) { try? data.write(to: dir.appendingPathComponent("config.json")) }
            if let l = label, let data = try? self.encoder.encode(l) { try? data.write(to: dir.appendingPathComponent("label.json")) }
            self.input?.markAsFinished()
            let w = self.writer, wasStarted = self.started
            self.writer = nil; self.input = nil; self.folder = nil; self.started = false
            if wasStarted, let w = w { w.finishWriting { done() } } else { done() }
        }
    }

    /// Keeps only the newest `keep` recordings (folder names are timestamps, so sorting by name sorts by time).
    private static func prune(keep: Int) {
        guard let items = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return }
        items.sorted { $0.lastPathComponent > $1.lastPathComponent }.dropFirst(keep).forEach { try? FileManager.default.removeItem(at: $0) }
    }

    /// Packs a recording folder into one zip file in the temporary folder, for sharing. Returns nil if it could not be made.
    static func zip(_ dir: URL) -> URL? {
        var result: URL?
        var error: NSError?
        NSFileCoordinator().coordinate(readingItemAt: dir, options: [.forUploading], error: &error) { zipped in
            let dest = FileManager.default.temporaryDirectory.appendingPathComponent("squash-coach-\(dir.lastPathComponent).zip")
            try? FileManager.default.removeItem(at: dest)
            if (try? FileManager.default.copyItem(at: zipped, to: dest)) != nil { result = dest }
        }
        return result
    }
}
