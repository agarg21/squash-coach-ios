import XCTest
@testable import DrillCore

final class RepAnalyzerTests: XCTestCase {
    /// A simple right-handed figure, 1 unit of torso, standing at the origin. `hand` is the wrist position; `foot` shifts the right ankle sideways.
    func frame(_ t: Double, hand: (Double, Double), foot: Double = 0) -> PoseFrame {
        var j = [Pt](repeating: Pt(0, 0, 0), count: Joint.allCases.count)
        j[Joint.nose.rawValue] = Pt(0, 1.3)
        j[Joint.lShoulder.rawValue] = Pt(-0.2, 1); j[Joint.rShoulder.rawValue] = Pt(0.2, 1)
        j[Joint.lHip.rawValue] = Pt(-0.15, 0); j[Joint.rHip.rawValue] = Pt(0.15, 0)
        j[Joint.lElbow.rawValue] = Pt(-0.3, 0.5); j[Joint.lWrist.rawValue] = Pt(-0.3, 0.1)
        j[Joint.rElbow.rawValue] = Pt((0.2 + hand.0) / 2 + 0.1, (1 + hand.1) / 2)
        j[Joint.rWrist.rawValue] = Pt(hand.0, hand.1)
        j[Joint.lKnee.rawValue] = Pt(-0.15, -0.6); j[Joint.lAnkle.rawValue] = Pt(-0.15, -1.2)
        j[Joint.rKnee.rawValue] = Pt(0.25 + foot / 2, -0.55); j[Joint.rAnkle.rawValue] = Pt(0.15 + foot, -1.2)
        return PoseFrame(t: t, j: j)
    }

    /// One rep: hand low until 1.0 s, up by 1.2 s, held, swing peaking near 1.8 s, then back down.
    func rep(start: Double, hold: Double, fps: Double = 60) -> [PoseFrame] {
        var out: [PoseFrame] = []
        let n = Int((hold + 2.6) * fps)
        for i in 0..<n {
            let s = Double(i) / fps
            var hand = (0.3, 0.4)
            var foot = 0.0
            if s < 1.0 { hand = (0.3, 0.4) }
            else if s < 1.2 { let a = (s - 1.0) / 0.2; hand = (0.3, 0.4 + 0.9 * a) }          // lift
            else if s < 1.2 + hold { hand = (0.3, 1.3) }                                      // held at the top
            else if s < 1.2 + hold + 0.12 { let a = (s - 1.2 - hold) / 0.12; hand = (0.3 + 0.9 * a, 1.3 - 1.4 * a) }  // swing down and out
            else if s < 1.2 + hold + 0.3 { let a = (s - 1.2 - hold - 0.12) / 0.18; hand = (1.2 - 0.6 * a, -0.1 + 1.0 * a) }  // follow-through up
            else { let a = min(1, (s - 1.2 - hold - 0.3) / 0.5); hand = (0.6 - 0.3 * a, 0.9 - 0.5 * a) }            // back to ready
            if s > 1.25 && s < 1.45 { foot = 0.5 * (s - 1.25) / 0.2 } else if s >= 1.45 { foot = 0.5 }                // step lands at 1.45 s
            out.append(frame(start + s, hand: hand, foot: foot))
        }
        return out
    }

    func testDemoLoopIsCountedRepByRep() {
        // the app's demo mode and the screen tests rely on this scripted figure being counted correctly
        let a = RepAnalyzer()
        DemoPoses.loop(holds: [0.55, 0.45, 0.2, 0.5], fps: 30).forEach { a.add($0) }
        XCTAssertEqual(a.reps.count, 4)
        XCTAssertLessThan(a.reps[2].lead, a.reps[0].lead)   // the third rep is the late one
    }

    func testCountsRepsAndMeasuresLead() {
        let a = RepAnalyzer()
        var events: [RepAnalyzer.Event] = []
        a.onEvent = { events.append($0) }
        var t = 0.0
        for _ in 0..<3 {
            let frames = rep(start: t, hold: 0.5)
            frames.forEach { a.add($0) }
            t = frames.last!.t + 1.0 / 60
        }
        XCTAssertEqual(a.reps.count, 3)
        for r in a.reps {
            XCTAssertEqual(r.lead, 0.65, accuracy: 0.15)          // forearm up at about 1.15 s, fastest at about 1.8 s
            XCTAssertGreaterThan(r.handHeight, 0.2)
            XCTAssertNotNil(r.upBeforeFoot)
            XCTAssertGreaterThan(r.upBeforeFoot ?? -1, 0)         // the hand was up before the step landed
        }
        XCTAssertEqual(events.filter { if case .handUp = $0 { return true } else { return false } }.count, 3)
        let s = SessionSummary.from(a.reps)
        XCTAssertEqual(s.reps, 3)
        XCTAssertEqual(s.upBeforeFootShare, 1.0)
    }

    func testLateRacketGivesShortLead() {
        let a = RepAnalyzer()
        rep(start: 0, hold: 0.05).forEach { a.add($0) }
        XCTAssertEqual(a.reps.count, 1)
        XCTAssertLessThan(a.reps[0].lead, 0.45)
    }

    func testRaisedHandWithoutSwingIsNotARep() {
        let a = RepAnalyzer()
        for i in 0..<240 { a.add(frame(Double(i) / 60, hand: (0.3, i < 60 ? 0.4 : 1.3))) }
        XCTAssertEqual(a.reps.count, 0)
    }

    func testLowConfidenceFramesAreIgnored() {
        let a = RepAnalyzer()
        var f = frame(0, hand: (0.3, 1.3)); f.j[Joint.rShoulder.rawValue].c = 0.1
        XCTAssertNil(a.add(f))
        XCTAssertTrue(a.liveHandHeight.isNaN)
    }

    /// A real swing: the skeleton of one professional backhand drive, as found by the offline pipeline.
    func testRealProfessionalSwing() throws {
        struct Fixture: Decodable { var frames: [PoseFrame] }
        let url = try XCTUnwrap(Bundle.module.url(forResource: "pro_backhand", withExtension: "json", subdirectory: "Fixtures"))
        let fx = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
        let a = RepAnalyzer()
        fx.frames.forEach { a.add($0) }
        print("real swing:", a.reps.map { "lead \($0.lead) hand \($0.handHeight) elbow \($0.elbowTop) knee \($0.kneeMin) contact \($0.tContact) peak \($0.peakSpeed) foot \(String(describing: $0.upBeforeFoot))" })
        XCTAssertEqual(a.reps.count, 1)
        let r = try XCTUnwrap(a.reps.first)
        XCTAssertEqual(r.tContact, 0.64, accuracy: 0.08)
        XCTAssertGreaterThan(r.lead, 0.3)
        XCTAssertLessThan(r.kneeMin, 140)
    }

    /// Not a test of correctness: runs the analyzer over many recorded swings (JSON lines: {"name","stroke","frames"}) and prints what it measured,
    /// so the app's reference ranges come from the same definitions it uses live.  DRILLREF_INPUT=/path/file.jsonl swift test --filter Bulk
    func testBulkReference() throws {
        guard let path = ProcessInfo.processInfo.environment["DRILLREF_INPUT"] else { throw XCTSkip("no input") }
        struct Clip: Decodable { var name: String; var stroke: String; var frames: [PoseFrame] }
        let text = try String(contentsOfFile: path, encoding: .utf8)
        var out = ""
        for line in text.split(separator: "\n") {
            guard let clip = try? JSONDecoder().decode(Clip.self, from: Data(line.utf8)) else { continue }
            let a = RepAnalyzer(); clip.frames.forEach { a.add($0) }
            let r = a.reps.first
            out += "\(clip.name),\(clip.stroke),\(a.reps.count),\(r?.lead ?? .nan),\(r?.handHeight ?? .nan),\(r?.elbowTop ?? .nan),\(r?.kneeMin ?? .nan),\(r?.tContact ?? .nan),\(r?.upBeforeFoot ?? .nan)\n"
        }
        try out.write(toFile: path + ".out.csv", atomically: true, encoding: .utf8)
    }
}
