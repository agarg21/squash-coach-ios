import Charts
import DrillCore
import SwiftUI

@main
struct SquashCoachApp: App {
    @StateObject private var store = Store(demo: AppMode.demo)
    var body: some Scene {
        WindowGroup {
            TabView {
                DrillView().tabItem { Label("Drill", systemImage: "figure.racquetball") }
                HistoryView().tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }
            }
            .tint(.orange)
            .preferredColorScheme(.dark)   // one dark look everywhere: the camera screen sets the tone
            .environmentObject(store)
        }
    }
}

func fmt(_ v: Double, _ digits: Int = 2) -> String { v.isFinite ? String(format: "%.\(digits)f", v) : "–" }

struct SkeletonOverlay: View {
    let joints: [Pt]
    let mirrored: Bool
    private let bones: [(Joint, Joint)] = [(.lShoulder, .rShoulder), (.lHip, .rHip), (.lShoulder, .lHip), (.rShoulder, .rHip), (.lShoulder, .lElbow), (.lElbow, .lWrist),
                                           (.rShoulder, .rElbow), (.rElbow, .rWrist), (.lHip, .lKnee), (.lKnee, .lAnkle), (.rHip, .rKnee), (.rKnee, .rAnkle)]
    var body: some View {
        Canvas { ctx, size in
            guard joints.count == Joint.allCases.count else { return }
            // the camera picture is 9:16 and letterboxed inside this view
            let w = min(size.width, size.height * 9 / 16), h = w * 16 / 9
            let ox = (size.width - w) / 2, oy = (size.height - h) / 2
            func p(_ j: Joint) -> CGPoint? {
                let q = joints[j.rawValue]
                guard q.c >= 0.3 else { return nil }
                let x = mirrored ? 1 - q.x : q.x
                return CGPoint(x: ox + x * w, y: oy + (1 - q.y) * h)
            }
            for (a, b) in bones {
                if let pa = p(a), let pb = p(b) {
                    var path = Path(); path.move(to: pa); path.addLine(to: pb)
                    ctx.stroke(path, with: .color(.white.opacity(0.9)), lineWidth: 4)
                }
            }
            for j in Joint.allCases { if let q = p(j) { ctx.fill(Path(ellipseIn: CGRect(x: q.x - 4, y: q.y - 4, width: 8, height: 8)), with: .color(.orange)) } }
        }
        .allowsHitTesting(false)
    }
}

struct DrillView: View {
    @EnvironmentObject var store: Store
    @StateObject private var model = DrillModel()
    @State private var showSettings = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if !AppMode.demo { CameraPreview(session: model.camera.session).ignoresSafeArea() }
            SkeletonOverlay(joints: model.joints, mirrored: model.frontCamera).ignoresSafeArea()
            VStack(spacing: 12) {
                if model.running { runningHeader } else { readyHeader }
                Spacer()
                if model.running { stopButton } else { readyCard }
            }
            .padding()
        }
        .onAppear { model.startCamera() }
        .sheet(isPresented: $showSettings) { SettingsView(model: model) }
        .sheet(isPresented: Binding(get: { model.summary != nil }, set: { if !$0 { model.summary = nil } })) {
            if let s = model.summary { SummaryView(summary: s, recording: model.lastRecording) }
        }
    }

    private func circleButton(_ icon: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Color.black.opacity(0.55), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    // Before a set: settings, whether the phone can see the whole body, and the camera flip button.
    private var readyHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            circleButton("gearshape.fill", id: "settings") { showSettings = true }
            Spacer(minLength: 0)
            Label(model.bodyInView ? "Whole body in view" : "Step back: head to feet in view",
                  systemImage: model.bodyInView ? "checkmark.circle.fill" : "figure.stand")
                .font(.subheadline.weight(.medium))
                .lineLimit(1).minimumScaleFactor(0.8)
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(model.bodyInView ? Color.green.opacity(0.75) : Color.black.opacity(0.55), in: Capsule())
                .accessibilityIdentifier("bodyStatus")
            Spacer(minLength: 0)
            circleButton("arrow.triangle.2.circlepath.camera.fill", id: "flipCamera") { model.flipCamera() }
        }
    }

    // During a set: the count, and the last rep's number.
    private var runningHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(model.repCount)").font(.system(size: 84, weight: .bold, design: .rounded)).monospacedDigit()
                .accessibilityIdentifier("repCount")
            Text(model.repCount == 1 ? "rep" : "reps").font(.title3.weight(.medium)).opacity(0.85)
            Spacer()
            if let r = model.lastRep {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(fmt(r.lead)) s").font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(r.lead >= ProRange.lead.lowerBound ? Color.green : Color.orange)
                    Text("arm up before the hit").font(.caption)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18).padding(.vertical, 10)
        .background(Color.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 22))
    }

    private var stopButton: some View {
        Button { model.stop(store: store) } label: {
            Text("Stop").font(.title2.bold()).foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(Color.red, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("stopSet")
    }

    // Before a set: which side, how to stand, and the start button.
    private var readyCard: some View {
        VStack(spacing: 12) {
            Picker("Side", selection: $model.side) { Text("Backhand").tag("backhand"); Text("Forehand").tag("forehand") }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("side")
            Text("Stand facing the phone, about 3 metres back.")
                .font(.footnote).foregroundStyle(.white.opacity(0.8))
            Button { model.start() } label: {
                Text("Start").font(.title2.bold()).foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(Color.orange, in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("startSet")
        }
        .padding(14)
        .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 24))
    }
}

/// The two things that are set once and left alone.
struct SettingsView: View {
    @ObservedObject var model: DrillModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("Playing hand") {
                    Picker("Playing hand", selection: $model.rightHanded) { Text("Right").tag(true); Text("Left").tag(false) }.pickerStyle(.segmented)
                }
                Section {
                    Toggle("Record each set", isOn: $model.debugRecording)
                } footer: {
                    Text("Saves the video and the skeleton the phone found, so the tracking can be checked. Recordings stay on this phone (the newest 30 are kept) until you share one from the set summary.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

/// The system share sheet.
struct ActivityView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [url], applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct SummaryView: View {
    let summary: SessionSummary
    let recording: URL?
    @Environment(\.dismiss) private var dismiss
    @State private var packing = false
    @State private var shareItem: ShareItem?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(summary.reps == 1 ? "1 rep" : "\(summary.reps) reps").font(.system(size: 44, weight: .bold, design: .rounded))
                        .padding(.vertical, 4)
                }
                if summary.reps > 0 {
                    Section("Measured") {
                        row("Racket arm up before the hit", "\(fmt(summary.lead)) s", "pros \(fmt(ProRange.lead.lowerBound))–\(fmt(ProRange.lead.upperBound)) s (provisional)")
                        row("How much that varies", "± \(fmt(summary.leadSpread)) s", "smaller is better")
                        row("Elbow at the top", "\(fmt(summary.elbowTop, 0))°", "pros \(fmt(ProRange.elbowTop.lowerBound, 0))–\(fmt(ProRange.elbowTop.upperBound, 0))° (provisional)")
                        row("Hand height at the top", fmt(summary.handHeight), "torso lengths from shoulder height")
                        row("Deepest knee bend", "\(fmt(summary.kneeMin, 0))°", nil)
                        if let s = summary.upBeforeFootShare { row("Arm up before the foot lands", "\(Int((s * 100).rounded()))% of reps", "aim for all of them") }
                    }
                }
                if let dir = recording {
                    Section {
                        Button { share(dir) } label: {
                            HStack {
                                Label("Share this recording", systemImage: "square.and.arrow.up")
                                Spacer()
                                if packing { ProgressView() }
                            }
                        }
                        .disabled(packing)
                        .accessibilityIdentifier("shareRecording")
                    } footer: {
                        Text("The video and skeleton of this set in one file, for checking the tracking.")
                    }
                }
                Section { Text("These numbers come from the phone's body tracking, without the racket. They are a first version and have not yet been checked against the offline analysis.").font(.footnote).foregroundStyle(.secondary) }
            }
            .navigationTitle("Set summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $shareItem) { ActivityView(url: $0.url) }
        }
    }

    private func share(_ dir: URL) {
        packing = true
        DispatchQueue.global(qos: .userInitiated).async {
            let zipped = DebugRecorder.zip(dir)
            DispatchQueue.main.async {
                packing = false
                if let z = zipped { shareItem = ShareItem(url: z) }
            }
        }
    }

    private func row(_ title: String, _ value: String, _ note: String?) -> some View {
        HStack {
            VStack(alignment: .leading) { Text(title); if let n = note { Text(n).font(.caption).foregroundStyle(.secondary) } }
            Spacer()
            Text(value).font(.title3.bold()).monospacedDigit()
        }
    }
}

struct HistoryView: View {
    @EnvironmentObject var store: Store
    var body: some View {
        NavigationStack {
            List {
                if store.sessions.isEmpty { Text("No sets yet. Do a set on the Drill tab.").foregroundStyle(.secondary) } else {
                    Section("Racket arm up before the hit (seconds)") {
                        Chart {
                            RectangleMark(yStart: .value("Low", ProRange.lead.lowerBound), yEnd: .value("High", ProRange.lead.upperBound)).foregroundStyle(.green.opacity(0.15))
                            ForEach(store.sessions.filter { $0.summary.lead.isFinite }) { s in
                                LineMark(x: .value("Date", s.date), y: .value("Seconds", s.summary.lead)).foregroundStyle(.orange)
                                PointMark(x: .value("Date", s.date), y: .value("Seconds", s.summary.lead)).foregroundStyle(.orange)
                            }
                        }
                        .frame(height: 200)
                        Text("Green band: provisional professional range.").font(.caption).foregroundStyle(.secondary)
                    }
                    Section("Sets") {
                        ForEach(store.sessions.reversed()) { s in
                            HStack {
                                VStack(alignment: .leading) { Text(s.date, style: .date); Text(s.date, style: .time).font(.caption).foregroundStyle(.secondary) }
                                Spacer()
                                Text("\(s.summary.reps) reps · \(fmt(s.summary.lead)) s").monospacedDigit()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Progress")
        }
    }
}
