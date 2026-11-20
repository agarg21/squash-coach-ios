import AVFoundation
import SwiftUI

/// Camera capture: delivers upright portrait frames to a handler on a background queue.
final class Camera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    var onFrame: ((CMSampleBuffer) -> Void)?
    private let queue = DispatchQueue(label: "camera.frames")
    private let output = AVCaptureVideoDataOutput()
    private(set) var position: AVCaptureDevice.Position = .back

    func start(position: AVCaptureDevice.Position) {
        self.position = position
        queue.async { [self] in
            session.beginConfiguration()
            session.sessionPreset = .hd1280x720
            session.inputs.forEach { session.removeInput($0) }
            if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
               let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) {
                session.addInput(input)
                // ask for 60 frames a second when the camera offers it at this size
                if let range = device.activeFormat.videoSupportedFrameRateRanges.first(where: { $0.maxFrameRate >= 60 }), (try? device.lockForConfiguration()) != nil {
                    _ = range
                    device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 60)
                    device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 60)
                    device.unlockForConfiguration()
                }
            }
            if session.outputs.isEmpty {
                output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                output.alwaysDiscardsLateVideoFrames = true
                output.setSampleBufferDelegate(self, queue: queue)
                if session.canAddOutput(output) { session.addOutput(output) }
            }
            if let c = output.connection(with: .video), c.isVideoRotationAngleSupported(90) { c.videoRotationAngle = 90 }
            session.commitConfiguration()
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() { queue.async { [self] in if session.isRunning { session.stopRunning() } } }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        onFrame?(sampleBuffer)
    }
}

/// Live camera picture, letterboxed (never cropped) so that drawn points line up with it.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.previewLayer.session = session
        v.previewLayer.videoGravity = .resizeAspect
        v.backgroundColor = .black
        return v
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}
