import AVFoundation
import CoreMotion
import Flutter
import UIKit

// Recognising mountains (requirement 68): the back camera's picture as a
// platform view, and the phone's attitude to true north with the camera's
// field of view as a stream. Flutter draws the summits over the picture.

/// Creates the camera views ("alvyo/peak-camera").
final class PeakCameraFactory: NSObject, FlutterPlatformViewFactory {
  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    PeakCameraView(frame: frame)
  }
}

/// The back camera's whole picture (4:3), filling the view.
final class PeakCameraView: NSObject, FlutterPlatformView {
  private let preview = PreviewView()
  private let session = AVCaptureSession()
  private let queue = DispatchQueue(label: "alvyo.peak-camera")

  init(frame: CGRect) {
    super.init()
    preview.frame = frame
    preview.backgroundColor = .black
    preview.previewLayer.session = session
    preview.previewLayer.videoGravity = .resizeAspectFill
    AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
      guard granted, let self else { return }
      self.queue.async { self.start() }
    }
  }

  func view() -> UIView { preview }

  private func start() {
    guard let device = PeakCamera.device, let input = try? AVCaptureDeviceInput(device: device) else { return }
    session.beginConfiguration()
    session.sessionPreset = .photo  // the sensor's whole field of view
    if session.canAddInput(input) { session.addInput(input) }
    session.commitConfiguration()
    session.startRunning()
  }

  deinit {
    let session = self.session
    queue.async { session.stopRunning() }
  }
}

final class PreviewView: UIView {
  override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
  var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

  // The picture upright on a screen turned with the device (the iPad
  // ignores the portrait lock; feedback issue 13).
  override func layoutSubviews() {
    super.layoutSubviews()
    guard let connection = previewLayer.connection,
      let orientation = window?.windowScene?.interfaceOrientation
    else { return }
    if #available(iOS 17.0, *) {
      let angle: CGFloat =
        switch orientation {
        case .landscapeLeft: 180
        case .landscapeRight: 0
        case .portraitUpsideDown: 270
        default: 90
        }
      if connection.isVideoRotationAngleSupported(angle) { connection.videoRotationAngle = angle }
    } else {
      let video: AVCaptureVideoOrientation =
        switch orientation {
        case .landscapeLeft: .landscapeLeft
        case .landscapeRight: .landscapeRight
        case .portraitUpsideDown: .portraitUpsideDown
        default: .portrait
        }
      if connection.isVideoOrientationSupported { connection.videoOrientation = video }
    }
  }
}

enum PeakCamera {
  static let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
}

/// The attitude 30 times a second ("alvyo/peak-motion"): the rotation matrix
/// from CoreMotion with x to true north and z up, row by row; the camera's
/// field of view along its picture's long side and that side over the
/// short one; the compass's accuracy (-1 uncalibrated, 0 low … 2 high).
final class PeakMotion: NSObject, FlutterStreamHandler {
  private let motion = CMMotionManager()

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    guard CMMotionManager.availableAttitudeReferenceFrames().contains(.xTrueNorthZVertical) else {
      return FlutterError(code: "no-compass", message: "this device has no compass", details: nil)
    }
    motion.deviceMotionUpdateInterval = 1.0 / 30
    motion.startDeviceMotionUpdates(using: .xTrueNorthZVertical, to: .main) { data, _ in
      guard let data else { return }
      // Read each time: the camera's format is the photo one once it runs.
      let format = PeakCamera.device?.activeFormat
      let fov = Double(format?.videoFieldOfView ?? 65)
      var aspect = 4.0 / 3
      if let f = format {
        let d = CMVideoFormatDescriptionGetDimensions(f.formatDescription)
        if min(d.width, d.height) > 0 { aspect = Double(max(d.width, d.height)) / Double(min(d.width, d.height)) }
      }
      let r = data.attitude.rotationMatrix
      events([
        "m": [r.m11, r.m12, r.m13, r.m21, r.m22, r.m23, r.m31, r.m32, r.m33],
        "fov": fov,
        "aspect": aspect,
        "accuracy": Int(data.magneticField.accuracy.rawValue),
      ])
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    motion.stopDeviceMotionUpdates()
    return nil
  }
}
