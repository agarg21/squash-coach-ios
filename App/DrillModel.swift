import AVFoundation
import AudioToolbox
import DrillCore
import SwiftUI

/// What a set was, saved with it and with its recording.
struct SetLabel: Codable, Equatable {
    var side: String            // "backhand" or "forehand"
    var frontCamera: Bool
}

struct Session: Codable, Identifiable {
    var id = UUID()
    var date: Date
    var rightHanded: Bool
    var reps: [RepStats]
    var summary: SessionSummary
    var label: SetLabel?
}

/// Demo mode (launch argument `-demo`): a scripted figure replaces the camera and nothing is saved.
/// It lets the screens be exercised where there is no camera, such as the simulator and the automated screen tests.
enum AppMode {
    static let demo = ProcessInfo.processInfo.arguments.contains("-demo")
}

/// Saved sessions (Documents/sessions.json).
final class Store: ObservableObject {
    @Published private(set) var sessions: [Session] = []
    private let demo: Bool
    private let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("sessions.json")

    init(demo: Bool = false) {
        self.demo = demo
        if demo { sessions = Store.sample(); return }
        if let data = try? Data(contentsOf: url), let s = try? Coding.decoder().decode([Session].self, from: data) { sessions = s }
    }

    func add(_ s: Session) {
        sessions.append(s)
        if demo { return }
        if let data = try? Coding.encoder().encode(sessions) { try? data.write(to: url, options: .atomic) }
    }

    /// Made-up earlier sets for demo mode, so the progress screen has something to show.
    private static func sample() -> [Session] {
        let leads = [0.24, 0.27, 0.26, 0.31, 0.34, 0.37]
        return leads.enumerated().map { i, lead in
            let reps = (0..<10).map { k in RepStats(lead: lead + 0.01 * Double(k % 3 - 1), handHeight: -0.1, elbowTop: 70 - Double(i) * 2, kneeMin: 140 - Double(i) * 3, upBeforeFoot: 0.1) }
            let day = Date().addingTimeInterval(-86400 * Double(2 * (leads.count - i)))
            return Session(date: day, rightHanded: true, reps: reps, summary: SessionSummary.from(reps), label: nil)
        }
    }
}

/// Glue between the camera, the body tracker, the rep analyzer and the screen.
final class DrillModel: ObservableObject {
    @Published var running = false
    @Published var repCount = 0
    @Published var lastRep: RepStats?
    @Published var joints: [Pt] = []            // normalised 0...1, y up, for drawing
    @Published var summary: SessionSummary?
    @Published var rightHanded: Bool = (UserDefaults.standard.object(forKey: "rightHanded") as? Bool) ?? true { didSet { UserDefaults.standard.set(rightHanded, forKey: "rightHanded") } }
    @Published var frontCamera: Bool = (UserDefaults.standard.object(forKey: "frontCamera") as? Bool) ?? true { didSet { UserDefaults.standard.set(frontCamera, forKey: "frontCamera") } }
    @Published var debugRecording: Bool = (UserDefaults.standard.object(forKey: "debugRecording") as? Bool) ?? true { didSet { UserDefaults.standard.set(debugRecording, forKey: "debugRecording") } }
    @Published var lastRecording: URL?          // the finished recording of the last set, once every file is complete
    @Published var side: String = UserDefaults.standard.string(forKey: "side") ?? "backhand" { didSet { UserDefaults.standard.set(side, forKey: "side") } }
    private let lock = NSLock()                  // the analyzer is fed from the camera queue and read from the screen
    @Published var bodyInView = false            // head, shoulders, hips and both ankles are seen

    let demo = AppMode.demo
    private var demoTimer: Timer?
    private var demoFrames: [PoseFrame] = []
    private var demoIndex = 0

    let camera = Camera()
    private let estimator = PoseEstimator()
    private let analyzer = RepAnalyzer()
    private let recorder = DebugRecorder()
    private let speech = AVSpeechSynthesizer()
    private var active = false                   // touched on the camera queue only
    private var recording = false
    private var recordingFolder: URL?
    private var label: SetLabel?

    init() {
        analyzer.onEvent = { [weak self] event in
            switch event {
            case .handUp: AudioServicesPlaySystemSound(1104)
            case .rep(let r):
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.repCount += 1; self.lastRep = r
                    if r.lead < ProRange.lead.lowerBound { self.speech.speak(AVSpeechUtterance(string: "late")) }
                }
            }
        }
        camera.onFrame = { [weak self] sample in self?.handle(sample) }
    }

    func startCamera() {
        if demo { startDemo(); return }
        AVCaptureDevice.requestAccess(for: .video) { [weak self] ok in
            guard ok, let self = self else { return }
            self.camera.start(position: self.frontCamera ? .front : .back)
        }
    }

    /// The button from the Camera app: switch between the front and back camera.
    func flipCamera() {
        frontCamera.toggle()
        if !demo { camera.start(position: frontCamera ? .front : .back) }
    }

    /// Demo mode: a scripted figure doing reps (one of every four with the arm up late), fed through the same path as camera frames.
    private func startDemo() {
        guard demoTimer == nil else { return }
        demoFrames = DemoPoses.loop(holds: [0.55, 0.45, 0.2, 0.5], fps: 30)
        demoTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            guard let self = self, !self.demoFrames.isEmpty else { return }
            let f = self.demoFrames[self.demoIndex % self.demoFrames.count]
            self.demoIndex += 1
            self.ingest(PoseFrame(t: Double(self.demoIndex) / 30, j: f.j), aspect: 9.0 / 16.0)
        }
    }

    /// One skeleton (or none) for one moment: counted if a set is running, and drawn.
    private func ingest(_ pose: PoseFrame?, aspect: Double) {
        lock.lock()
        if active, let p = pose {
            analyzer.add(p)
            if recording && demo { recorder.addPose(p) }
        }
        lock.unlock()
        let pts = pose?.j.map { Pt($0.x / aspect, $0.y, $0.c) } ?? []
        let needed: [DrillCore.Joint] = [.nose, .lShoulder, .rShoulder, .lHip, .rHip, .lAnkle, .rAnkle]
        let inView = pose.map { p in needed.allSatisfy { p[$0].c >= 0.3 } } ?? false
        DispatchQueue.main.async {
            self.joints = pts
            if self.bodyInView != inView { self.bodyInView = inView }
        }
    }

    private func handle(_ sample: CMSampleBuffer) {
        guard let pb = CMSampleBufferGetImageBuffer(sample) else { return }
        let t = CMSampleBufferGetPresentationTimeStamp(sample).seconds
        let pose = estimator.estimate(pb, time: t)
        if active && recording { recorder.add(sample, pose: pose) }
        ingest(pose, aspect: Double(CVPixelBufferGetWidth(pb)) / Double(max(CVPixelBufferGetHeight(pb), 1)))
    }

    func start() {
        var c = AnalyzerConfig(); c.rightHanded = rightHanded
        repCount = 0; lastRep = nil; summary = nil; lastRecording = nil
        label = SetLabel(side: side, frontCamera: frontCamera)
        lock.lock()
        analyzer.config = c; analyzer.reset()
        recording = debugRecording
        recordingFolder = recording ? recorder.begin() : nil
        active = true
        lock.unlock()
        running = true
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func stop(store: Store) {
        lock.lock()
        active = false
        let reps = analyzer.reps
        let config = analyzer.config
        lock.unlock()
        running = false
        UIApplication.shared.isIdleTimerDisabled = false
        if recording, let dir = recordingFolder {
            recorder.end(reps: reps, config: config, label: label) { DispatchQueue.main.async { self.lastRecording = dir } }
        }
        let s = SessionSummary.from(reps)
        summary = s
        if !reps.isEmpty { store.add(Session(date: Date(), rightHanded: rightHanded, reps: reps, summary: s, label: label)) }
    }
}
