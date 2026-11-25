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
    @State private var showDetails = false

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
        .sheet(isPresented: $showDetails) { SetDetailsView(model: model) }
        .sheet(isPresented: Binding(get: { model.summary != nil }, set: { if !$0 { model.summary = nil } })) {
            if let s = model.summary { SummaryView(summary: s, label: model.lastLabel, debugFolder: model.lastDebugFolder) }
        }
    }

    // Before a set: one line saying whether the phone can see the whole body.
    private var readyHeader: some View {
        Label(model.bodyInView ? "Whole body in view" : "Step back until I can see you head to feet",
              systemImage: model.bodyInView ? "checkmark.circle.fill" : "figure.stand")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(model.bodyInView ? Color.green.opacity(0.75) : Color.black.opacity(0.55), in: Capsule())
            .accessibilityIdentifier("bodyStatus")
    }

    // During a set: the count, and the last rep's number.
    private var runningHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(model.repCount)").font(.system(size: 84, weight: .bold, design: .rounded)).monospacedDigit()
                .accessibilityIdentifier("repCount")
            Text(model.plannedReps > 0 ? "of \(model.plannedReps) reps" : "reps").font(.title3.weight(.medium)).opacity(0.85)
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

    private var setTitle: String {
        let side = model.side == "forehand" ? "Forehand" : "Backhand"
        return model.plannedReps > 0 ? "\(side) · \(model.plannedReps) reps" : side
    }

    private var setSubtitle: String {
        let how: String = model.style == "normal" ? "Normal swings" : model.style.prefix(1).uppercased() + String(model.style.dropFirst())
        var parts: [String] = [how]
        parts.append(model.swingDirection == "across" ? "swing across the phone" : "swing away from the phone")
        if model.racketInHand { parts.append("racket in hand") }
        return parts.joined(separator: " · ")
    }

    // Before a set: what the set is (tap to change), and the start button.
    private var readyCard: some View {
        VStack(spacing: 12) {
            Button { showDetails = true } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(setTitle).font(.headline)
                        Text(setSubtitle).font(.caption).opacity(0.8).multilineTextAlignment(.leading)
                    }
                    Spacer()
                    Image(systemName: "slider.horizontal.3")
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("setDetails")
            Button { model.start() } label: {
                Text("Start set").font(.title2.bold()).foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(Color.orange, in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("startSet")
        }
        .padding(14)
        .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 24))
    }
}

/// Everything adjustable, kept off the main screen: what this set is, and how the phone is set up.
struct SetDetailsView: View {
    @ObservedObject var model: DrillModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Side", selection: $model.side) { Text("Backhand").tag("backhand"); Text("Forehand").tag("forehand") }.pickerStyle(.segmented)
                    Stepper("Planned reps: \(model.plannedReps)", value: $model.plannedReps, in: 0...40)
                    Picker("How", selection: $model.style) {
                        Text("Normal swings").tag("normal")
                        Text("Arm up late on purpose").tag("arm up late on purpose")
                        Text("Standing tall on purpose").tag("standing tall on purpose")
                    }
                    Picker("Swing goes", selection: $model.swingDirection) {
                        Text("Away from the phone").tag("away")
                        Text("Across the phone").tag("across")
                    }
                    Toggle("Racket in hand", isOn: $model.racketInHand)
                } header: { Text("This set") } footer: { Text("Saved with the set, so the tracking can be checked against what you actually did.") }
                Section("Setup") {
                    Picker("Playing hand", selection: $model.rightHanded) { Text("Right").tag(true); Text("Left").tag(false) }.pickerStyle(.segmented)
                    Toggle("Use the front camera", isOn: $model.frontCamera)
                    Toggle("Save video and skeleton for checking", isOn: $model.debugRecording)
                }
            }
            .navigationTitle("Set details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onChange(of: model.frontCamera) { _, _ in model.applyCamera() }
        }
    }
}

struct SummaryView: View {
    let summary: SessionSummary
    let label: SetLabel?
    let debugFolder: String?
    @Environment(\.dismiss) private var dismiss

    private var countNote: String? {
        guard let planned = label?.plannedReps, planned > 0 else { return nil }
        return summary.reps == planned ? "All \(planned) planned reps were counted." : "You planned \(planned)."
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(summary.reps == 1 ? "1 rep" : "\(summary.reps) reps").font(.system(size: 44, weight: .bold, design: .rounded))
                        if let n = countNote { Text(n).foregroundStyle(.secondary) }
                    }
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
                if let d = debugFolder {
                    Section("Saved for checking") { Text("Files › On My iPhone › Squash Coach › debug › \(d)").font(.footnote) }
                }
                Section { Text("These numbers come from the phone's body tracking, without the racket. They are a first version and have not yet been checked against the offline analysis.").font(.footnote).foregroundStyle(.secondary) }
            }
            .navigationTitle("Set summary")
            .navigationBarTitleDisplayMode(.inline)
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
