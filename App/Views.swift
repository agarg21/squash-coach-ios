import Charts
import DrillCore
import SwiftUI

@main
struct SquashCoachApp: App {
    @StateObject private var store = Store()
    var body: some Scene {
        WindowGroup {
            TabView {
                DrillView().tabItem { Label("Drill", systemImage: "figure.racquetball") }
                HistoryView().tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }
            }
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

    var body: some View {
        ZStack {
            CameraPreview(session: model.camera.session).ignoresSafeArea(edges: .top)
            SkeletonOverlay(joints: model.joints, mirrored: model.frontCamera).ignoresSafeArea(edges: .top)
            VStack {
                HStack(alignment: .top) {
                    VStack(alignment: .leading) {
                        Text("\(model.repCount)").font(.system(size: 72, weight: .bold, design: .rounded)).monospacedDigit()
                        Text("reps").font(.headline)
                    }
                    Spacer()
                    if let r = model.lastRep {
                        VStack(alignment: .trailing) {
                            Text("\(fmt(r.lead)) s").font(.system(size: 36, weight: .bold, design: .rounded)).monospacedDigit()
                                .foregroundStyle(r.lead >= ProRange.lead.lowerBound ? Color.green : Color.orange)
                            Text("racket arm up before the hit").font(.caption)
                        }
                    }
                }
                .padding().background(.black.opacity(0.45)).foregroundStyle(.white)
                Spacer()
                VStack(spacing: 10) {
                    if !model.running {
                        HStack {
                            Picker("Hand", selection: $model.rightHanded) { Text("Right-handed").tag(true); Text("Left-handed").tag(false) }.pickerStyle(.segmented)
                            Button { model.flipCamera() } label: { Image(systemName: "camera.rotate").font(.title2) }
                        }
                        Toggle("Save debug video and skeleton", isOn: $model.debugRecording).font(.subheadline)
                        // what this set is, so the tracking can be checked against it
                        Picker("Side", selection: $model.side) { Text("Backhand").tag("backhand"); Text("Forehand").tag("forehand") }.pickerStyle(.segmented)
                        Stepper("Planned reps: \(model.plannedReps)", value: $model.plannedReps, in: 0...40).font(.subheadline)
                        HStack {
                            Picker("How", selection: $model.style) {
                                Text("Normal swings").tag("normal")
                                Text("Arm up late on purpose").tag("arm up late on purpose")
                                Text("Standing tall on purpose").tag("standing tall on purpose")
                            }
                            Spacer()
                            Picker("Phone", selection: $model.swingDirection) {
                                Text("Swing away from phone").tag("away")
                                Text("Swing across phone").tag("across")
                            }
                        }
                        .pickerStyle(.menu).tint(.orange)
                        Toggle("Racket in hand", isOn: $model.racketInHand).font(.subheadline)
                    }
                    Button(model.running ? "Stop" : "Start set") { if model.running { model.stop(store: store) } else { model.start() } }
                        .font(.title2.bold()).frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(model.running ? Color.red : Color.orange).foregroundStyle(.white).clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding().background(.black.opacity(0.55)).foregroundStyle(.white)
            }
        }
        .onAppear { model.startCamera() }
        .sheet(isPresented: Binding(get: { model.summary != nil }, set: { if !$0 { model.summary = nil } })) {
            if let s = model.summary { SummaryView(summary: s, planned: model.lastLabel?.plannedReps ?? 0, debugFolder: model.lastDebugFolder) }
        }
    }
}

struct SummaryView: View {
    let summary: SessionSummary
    let planned: Int
    let debugFolder: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("This set") {
                    row("Reps", "\(summary.reps)", planned > 0 ? "you planned \(planned)" : nil)
                    row("Racket arm up before the hit", "\(fmt(summary.lead)) s", "pros \(fmt(ProRange.lead.lowerBound))–\(fmt(ProRange.lead.upperBound)) s (provisional)")
                    row("How much that varies", "± \(fmt(summary.leadSpread)) s", "smaller is better")
                    row("Elbow at the top", "\(fmt(summary.elbowTop, 0))°", "pros \(fmt(ProRange.elbowTop.lowerBound, 0))–\(fmt(ProRange.elbowTop.upperBound, 0))° (provisional)")
                    row("Hand height at the top", fmt(summary.handHeight), "torso lengths from shoulder height")
                    row("Deepest knee bend", "\(fmt(summary.kneeMin, 0))°", nil)
                    if let s = summary.upBeforeFootShare { row("Arm up before the foot lands", "\(Int((s * 100).rounded()))% of reps", "aim for all of them") }
                }
                if let d = debugFolder {
                    Section("Debug") { Text("Saved to Files › On My iPhone › Squash Coach › debug › \(d)").font(.footnote) }
                }
                Section { Text("These numbers come from the phone's body tracking, without the racket. They are a first version and have not yet been checked against the offline analysis.").font(.footnote).foregroundStyle(.secondary) }
            }
            .navigationTitle("Set summary")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
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
