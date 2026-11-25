import Foundation

/// A scripted figure doing drive preparations and swings.
/// Used by the app's demo mode (no camera needed, for example in the simulator) and by tests.
public enum DemoPoses {
    /// A simple right-handed figure with a torso of length 1 and hips at the origin. `hand` is the right wrist; `foot` shifts the right ankle sideways.
    public static func frame(_ t: Double, hand: (Double, Double), foot: Double = 0) -> PoseFrame {
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

    /// One rep in torso units: hand low until 1.0 s, up by 1.2 s, held for `hold`, swing, follow-through, back to ready. Lasts `hold` + 2.6 s.
    public static func rep(start: Double, hold: Double, fps: Double = 60) -> [PoseFrame] {
        var out: [PoseFrame] = []
        let n = Int((hold + 2.6) * fps)
        for i in 0..<n {
            let s = Double(i) / fps
            var hand = (0.3, 0.4)
            var foot = 0.0
            if s < 1.0 { hand = (0.3, 0.4) }
            else if s < 1.2 { let a = (s - 1.0) / 0.2; hand = (0.3, 0.4 + 0.9 * a) }                                         // lift
            else if s < 1.2 + hold { hand = (0.3, 1.3) }                                                                     // held at the top
            else if s < 1.2 + hold + 0.12 { let a = (s - 1.2 - hold) / 0.12; hand = (0.3 + 0.9 * a, 1.3 - 1.4 * a) }         // swing down and out
            else if s < 1.2 + hold + 0.3 { let a = (s - 1.2 - hold - 0.12) / 0.18; hand = (1.2 - 0.6 * a, -0.1 + 1.0 * a) }  // follow-through up
            else { let a = min(1, (s - 1.2 - hold - 0.3) / 0.5); hand = (0.6 - 0.3 * a, 0.9 - 0.5 * a) }                     // back to ready
            if s > 1.25 && s < 1.45 { foot = 0.5 * (s - 1.25) / 0.2 } else if s >= 1.45 { foot = 0.5 }                       // step lands at 1.45 s
            out.append(frame(start + s, hand: hand, foot: foot))
        }
        return out
    }

    /// Places a torso-unit figure in a portrait picture the way the camera reports it: x in 0...9/16, y in 0...1, y up.
    public static func onScreen(_ f: PoseFrame) -> PoseFrame {
        PoseFrame(t: f.t, j: f.j.map { Pt(0.2 + 0.22 * $0.x, 0.42 + 0.22 * $0.y, $0.c) })
    }

    /// Consecutive reps, one per entry of `holds`, starting at t = 0, placed on screen. The last frame leads back into the first, so it can loop.
    public static func loop(holds: [Double], fps: Double = 30) -> [PoseFrame] {
        var out: [PoseFrame] = []
        var t = 0.0
        for h in holds {
            let r = rep(start: t, hold: h, fps: fps)
            out += r
            t = (r.last?.t ?? t) + 1 / fps
        }
        return out.map(onScreen)
    }
}

extension RepStats {
    /// For sample data (the app's demo mode).
    public init(lead: Double, handHeight: Double, elbowTop: Double, kneeMin: Double, upBeforeFoot: Double? = nil, peakSpeed: Double = 10) {
        self.init(tUp: 0, tContact: lead, lead: lead, handHeight: handHeight, elbowTop: elbowTop, kneeMin: kneeMin, upBeforeFoot: upBeforeFoot, peakSpeed: peakSpeed)
    }
}
