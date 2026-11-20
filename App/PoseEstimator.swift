import CoreMedia
import DrillCore
import Vision

/// Apple's on-device body tracker, turned into the joints the analyzer uses.
final class PoseEstimator {
    private let request = VNDetectHumanBodyPoseRequest()
    private static let map: [(Joint, VNHumanBodyPoseObservation.JointName)] = [
        (.nose, .nose), (.lShoulder, .leftShoulder), (.rShoulder, .rightShoulder), (.lElbow, .leftElbow), (.rElbow, .rightElbow),
        (.lWrist, .leftWrist), (.rWrist, .rightWrist), (.lHip, .leftHip), (.rHip, .rightHip), (.lKnee, .leftKnee), (.rKnee, .rightKnee),
        (.lAnkle, .leftAnkle), (.rAnkle, .rightAnkle),
    ]

    /// Returns the skeleton of the most confidently seen person, with x scaled by the picture's width/height so distances are true.
    func estimate(_ pixelBuffer: CVPixelBuffer, time: Double) -> PoseFrame? {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        guard (try? handler.perform([request])) != nil, let people = request.results, !people.isEmpty else { return nil }
        let aspect = Double(CVPixelBufferGetWidth(pixelBuffer)) / Double(max(CVPixelBufferGetHeight(pixelBuffer), 1))
        var best: (score: Float, joints: [Pt])?
        for person in people {
            guard let pts = try? person.recognizedPoints(.all) else { continue }
            var joints = [Pt](repeating: Pt(0, 0, 0), count: Joint.allCases.count)
            var score: Float = 0
            for (j, name) in Self.map {
                if let p = pts[name] {
                    joints[j.rawValue] = Pt(Double(p.location.x) * aspect, Double(p.location.y), Double(p.confidence))
                    score += p.confidence
                }
            }
            if best == nil || score > best!.score { best = (score, joints) }
        }
        guard let b = best else { return nil }
        return PoseFrame(t: time, j: b.joints)
    }
}
