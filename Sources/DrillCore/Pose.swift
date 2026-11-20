import Foundation

/// A point in consistent units (x to the right, y up) with a confidence in 0...1.
public struct Pt: Codable, Equatable {
    public var x: Double
    public var y: Double
    public var c: Double
    public init(_ x: Double, _ y: Double, _ c: Double = 1) { self.x = x; self.y = y; self.c = c }
}

public enum Joint: Int, Codable, CaseIterable {
    case nose, lShoulder, rShoulder, lElbow, rElbow, lWrist, rWrist, lHip, rHip, lKnee, rKnee, lAnkle, rAnkle
}

/// One video frame's skeleton. `j` is indexed by `Joint.rawValue`.
public struct PoseFrame: Codable {
    public var t: Double
    public var j: [Pt]
    public init(t: Double, j: [Pt]) { self.t = t; self.j = j }
    public subscript(_ k: Joint) -> Pt { j[k.rawValue] }
}

func dist(_ a: Pt, _ b: Pt) -> Double { ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot() }
func mid(_ a: Pt, _ b: Pt) -> Pt { Pt((a.x + b.x) / 2, (a.y + b.y) / 2, min(a.c, b.c)) }

/// Angle at `b` between the segments b-a and b-c, in degrees (180 = straight).
func angle(_ a: Pt, _ b: Pt, _ c: Pt) -> Double {
    let ux = a.x - b.x, uy = a.y - b.y, vx = c.x - b.x, vy = c.y - b.y
    let d = (ux * ux + uy * uy).squareRoot() * (vx * vx + vy * vy).squareRoot()
    guard d > 1e-9 else { return .nan }
    return acos(max(-1, min(1, (ux * vx + uy * vy) / d))) * 180 / .pi
}

func median(_ v: [Double]) -> Double {
    let s = v.filter { $0.isFinite }.sorted()
    guard !s.isEmpty else { return .nan }
    return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
}

/// JSON coding that tolerates "not a number" (a measurement that could not be taken).
public enum Coding {
    public static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        e.dateEncodingStrategy = .iso8601
        return e
    }
    public static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
