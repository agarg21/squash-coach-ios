import AVFoundation
import AudioToolbox
import DrillCore
import SwiftUI

struct Session: Codable, Identifiable {
    var id = UUID()
    var date: Date
    var rightHanded: Bool
    var reps: [RepStats]
    var summary: SessionSummary
}

/// Saved sessions (Documents/sessions.json).
final class Store: ObservableObject {
    @Published private(set) var sessions: [Session] = []
    private let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("sessions.json")

    init() {
        if let data = try? Data(contentsOf: url), let s = try? Coding.decoder().decode([Session].self, from: data) { sessions = s }
    }

    func add(_ s: Session) {
        sessions.append(s)
        if let data = try? Coding.encoder().encode(sessions) { try? data.write(to: url, options: .atomic) }
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
    @Published var frontCamera: Bool = UserDefaults.standard.bool(forKey: "frontCamera") { didSet { UserDefaults.standard.set(frontCamera, forKey: "frontCamera") } }
    @Published var debugRecording: Bool = (UserDefaults.standard.object(forKey: "debugRecording") as? Bool) ?? true { didSet { UserDefaults.standard.set(debugRecording, forKey: "debugRecording") } }
    @Published var lastDebugFolder: String?

    let camera = Camera()
    private let estimator = PoseEstimator()
    private let analyzer = RepAnalyzer()
    private let recorder = DebugRecorder()
    private let speech = AVSpeechSynthesizer()
    private var active = false                   // touched on the camera queue only
    private var recording = false

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
        AVCaptureDevice.requestAccess(for: .video) { [weak self] ok in
            guard ok, let self = self else { return }
            self.camera.start(position: self.frontCamera ? .front : .back)
        }
    }

    func flipCamera() { frontCamera.toggle(); camera.start(position: frontCamera ? .front : .back) }

    private func handle(_ sample: CMSampleBuffer) {
        guard let pb = CMSampleBufferGetImageBuffer(sample) else { return }
        let t = CMSampleBufferGetPresentationTimeStamp(sample).seconds
        let pose = estimator.estimate(pb, time: t)
        if active {
            if let p = pose { analyzer.add(p) }
            if recording { recorder.add(sample, pose: pose) }
        }
        let aspect = Double(CVPixelBufferGetWidth(pb)) / Double(max(CVPixelBufferGetHeight(pb), 1))
        let pts = pose?.j.map { Pt($0.x / aspect, $0.y, $0.c) } ?? []
        DispatchQueue.main.async { self.joints = pts }
    }

    func start() {
        var c = AnalyzerConfig(); c.rightHanded = rightHanded
        analyzer.config = c; analyzer.reset()
        repCount = 0; lastRep = nil; summary = nil
        recording = debugRecording
        if recording { recorder.begin() }
        active = true; running = true
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func stop(store: Store) {
        active = false; running = false
        UIApplication.shared.isIdleTimerDisabled = false
        let reps = analyzer.reps
        if recording { lastDebugFolder = recorder.folder?.lastPathComponent; recorder.end(reps: reps, config: analyzer.config) }
        let s = SessionSummary.from(reps)
        summary = s
        if !reps.isEmpty { store.add(Session(date: Date(), rightHanded: rightHanded, reps: reps, summary: s)) }
    }
}
