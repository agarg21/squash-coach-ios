import Foundation

/// What was measured on one repetition of a swing (with or without a ball).
public struct RepStats: Codable, Identifiable, Equatable {
    public var id = UUID()
    /// Time the racket arm came up (forearm pointing up, hand at chest height or higher).
    public var tUp: Double
    /// Time of the fastest point of the swing (taken as contact).
    public var tContact: Double
    /// Seconds the racket hand was up before contact. Professionals: about 0.45 to 0.56.
    public var lead: Double
    /// Highest point of the hitting hand before the swing, relative to its shoulder, in torso lengths (0 = shoulder height).
    public var handHeight: Double
    /// Elbow angle at that highest point, in degrees.
    public var elbowTop: Double
    /// Smallest knee angle (either leg) around contact, in degrees.
    public var kneeMin: Double
    /// Seconds between the hand going up and the stepping foot landing. Positive = racket up first. Nil if no step was seen.
    public var upBeforeFoot: Double?
    /// Peak hand speed, in torso lengths per second.
    public var peakSpeed: Double
}

public struct AnalyzerConfig: Codable, Equatable {
    public var rightHanded = true
    /// The racket arm counts as "up" when the forearm points upward: wrist higher than elbow by this much (torso lengths)...
    public var forearmUp = 0.05
    /// ...and the hand is at least this high relative to the shoulder (torso lengths; 0 = shoulder height).
    /// On a backhand the hand sits at chest height by the opposite shoulder while the racket head is above it, so this is negative.
    public var minHandHeight = -0.45
    /// A raised arm that comes down without a swing is forgotten after this many seconds down.
    public var downDwell = 0.4
    /// Hand speed that counts as a swing (torso lengths per second).
    public var swingSpeed = 5.0
    public var minConfidence = 0.3
    /// Give up on a raised hand that never swings after this many seconds.
    public var upTimeout = 5.0
    public init() {}
}

public struct SessionSummary: Codable, Equatable {
    public var reps: Int
    public var lead: Double
    public var leadSpread: Double
    public var handHeight: Double
    public var elbowTop: Double
    public var kneeMin: Double
    /// Share of reps (0...1) where the racket hand was up before the foot landed; nil if no steps were seen.
    public var upBeforeFootShare: Double?

    public static func from(_ r: [RepStats]) -> SessionSummary {
        let leads = r.map { $0.lead }
        let m = median(leads)
        let spread = median(leads.map { abs($0 - m) })
        let steps = r.compactMap { $0.upBeforeFoot }
        return SessionSummary(reps: r.count, lead: m, leadSpread: spread, handHeight: median(r.map { $0.handHeight }),
                              elbowTop: median(r.map { $0.elbowTop }), kneeMin: median(r.map { $0.kneeMin }),
                              upBeforeFootShare: steps.isEmpty ? nil : Double(steps.filter { $0 > 0 }.count) / Double(steps.count))
    }
}

/// Provisional reference ranges: this same analyzer run over the skeletons of about 1,700 professional backhand drives from broadcast footage
/// (range of the players' medians). It found a rep in fewer than half of those clips, so treat these as a starting point, not a standard.
public enum ProRange {
    public static let lead: ClosedRange<Double> = 0.32...0.44
    public static let elbowTop: ClosedRange<Double> = 43...63
}

/// Turns a stream of skeleton frames into repetitions. Pure logic: no camera, no UI.
public final class RepAnalyzer {
    public enum Event: Equatable { case handUp(Double), rep(RepStats) }
    enum Phase { case ready, up, swinging, recover }

    public var config: AnalyzerConfig
    public private(set) var reps: [RepStats] = []
    public var onEvent: ((Event) -> Void)?

    private var phase = Phase.ready
    private var window: [(t: Double, f: PoseFrame, h: Double, speed: Double, foot: Double)] = []
    private var torso = Double.nan
    private var last: (t: Double, hand: Pt, lAnk: Pt, rAnk: Pt)?
    private var upCount = 0
    private var tUp = 0.0, topH = -Double.infinity, elbowTop = Double.nan
    private var peak = 0.0, tPeak = 0.0
    private var tDown: Double?

    public init(config: AnalyzerConfig = AnalyzerConfig()) { self.config = config }

    public func reset() { reps = []; phase = .ready; window = []; last = nil; upCount = 0; torso = .nan }

    /// Height of the hitting hand above its shoulder for the latest frame, in torso lengths (for a live gauge).
    public private(set) var liveHandHeight = Double.nan

    @discardableResult
    public func add(_ f: PoseFrame) -> RepStats? {
        let c = config.minConfidence
        let ls = f[.lShoulder], rs = f[.rShoulder], lh = f[.lHip], rh = f[.rHip]
        guard ls.c >= c, rs.c >= c, lh.c >= c, rh.c >= c else { return nil }
        let hip = mid(lh, rh)
        let l = dist(mid(ls, rs), hip)
        guard l > 1e-6 else { return nil }
        torso = torso.isNaN ? l : 0.9 * torso + 0.1 * l
        let wrist = config.rightHanded ? f[.rWrist] : f[.lWrist]
        let shoulder = config.rightHanded ? rs : ls
        let elbow = config.rightHanded ? f[.rElbow] : f[.lElbow]
        guard wrist.c >= c else { return nil }
        let h = (wrist.y - shoulder.y) / torso
        liveHandHeight = h
        let u = elbow.c >= c ? (wrist.y - elbow.y) / torso : -1
        let isUp = u > config.forearmUp && h > config.minHandHeight
        let hand = Pt(wrist.x - hip.x, wrist.y - hip.y)
        var speed = 0.0, foot = 0.0
        if let p = last, f.t > p.t {
            let dt = f.t - p.t
            speed = dist(hand, p.hand) / torso / dt
            let la = f[.lAnkle], ra = f[.rAnkle]
            if la.c >= c, ra.c >= c { foot = max(dist(la, p.lAnk), dist(ra, p.rAnk)) / torso / dt }
        }
        last = (f.t, hand, f[.lAnkle], f[.rAnkle])
        // light smoothing of the speed over three frames
        let prev = window.suffix(2).map { $0.speed }
        let sm = (prev.reduce(0, +) + speed) / Double(prev.count + 1)
        window.append((f.t, f, h, sm, foot))
        while let first = window.first, f.t - first.t > 3.0 { window.removeFirst() }

        switch phase {
        case .ready:
            upCount = isUp ? upCount + 1 : 0
            if upCount == 2 {
                phase = .up; tUp = window[window.count - 2].t; topH = h; elbowTop = angle(shoulder, elbow, wrist); tDown = nil
                onEvent?(.handUp(tUp))
            }
        case .up:
            if h > topH { topH = h; elbowTop = angle(shoulder, elbow, wrist) }
            if sm > config.swingSpeed && h < topH - 0.15 { phase = .swinging; peak = sm; tPeak = f.t }
            else if f.t - tUp > config.upTimeout { phase = .ready; upCount = 0 }
            else if u < 0 {
                if let d = tDown { if f.t - d > config.downDwell { phase = .ready; upCount = 0 } } else { tDown = f.t }
            } else { tDown = nil }
        case .swinging:
            if sm > peak { peak = sm; tPeak = f.t }
            else if sm < 0.5 * peak {
                let rep = finish()
                phase = .recover
                reps.append(rep); onEvent?(.rep(rep))
                return rep
            }
        case .recover:
            if u < 0 && sm < config.swingSpeed { phase = .ready; upCount = 0 }
        }
        return nil
    }

    private func finish() -> RepStats {
        // knee bend around contact
        var knee = Double.infinity
        for w in window where w.t >= tPeak - 0.3 && w.t <= tPeak + 0.1 {
            let f = w.f
            for (hp, kn, an) in [(Joint.lHip, Joint.lKnee, Joint.lAnkle), (.rHip, .rKnee, .rAnkle)] {
                if f[hp].c >= config.minConfidence, f[kn].c >= config.minConfidence, f[an].c >= config.minConfidence {
                    let a = angle(f[hp], f[kn], f[an]); if a.isFinite { knee = min(knee, a) }
                }
            }
        }
        // the step: the last moment before contact that a foot stops after moving
        var land: Double?
        var moving = false
        for w in window where w.t >= tUp - 1.0 && w.t <= tPeak {
            if w.foot > 1.5 { moving = true } else if moving && w.foot < 0.6 { land = w.t; moving = false }
        }
        return RepStats(tUp: tUp, tContact: tPeak, lead: tPeak - tUp, handHeight: topH, elbowTop: elbowTop,
                        kneeMin: knee.isFinite ? knee : .nan, upBeforeFoot: land.map { $0 - tUp }, peakSpeed: peak)
    }
}
