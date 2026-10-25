import AVFoundation
import AuthenticationServices
import CryptoKit
import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let speech = Speech()
  private let peakMotion = PeakMotion()
  private let appleSignIn = AppleSignIn()
  private let watch = WatchBridge()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Off-route warnings are local notifications (flutter_local_notifications).
    UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    watch.activate()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // Offline maps can be downloaded again: keep them out of iCloud backups.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AlvyoBackup") {
      let channel = FlutterMethodChannel(name: "alvyo/backup", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        guard call.method == "exclude", let path = call.arguments as? String else {
          result(FlutterMethodNotImplemented)
          return
        }
        var url = URL(fileURLWithPath: path)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        do {
          try url.setResourceValues(values)
          result(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup ?? false)
        } catch {
          result(FlutterError(code: "backup", message: error.localizedDescription, details: nil))
        }
      }
    }
    // Recognising mountains: the camera's picture and the phone's attitude.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AlvyoPeaks") {
      registrar.register(PeakCameraFactory(), withId: "alvyo/peak-camera")
      // Whether the camera may be used (asks the first time).
      FlutterMethodChannel(name: "alvyo/camera", binaryMessenger: registrar.messenger())
        .setMethodCallHandler { call, result in
          guard call.method == "access" else {
            result(FlutterMethodNotImplemented)
            return
          }
          AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async { result(granted) }
          }
        }
      FlutterEventChannel(name: "alvyo/peak-motion", binaryMessenger: registrar.messenger())
        .setStreamHandler(peakMotion)
    }
    // Bug reports (lib/bug_report.dart): the window as shown, with the maps,
    // which Flutter's own picture leaves empty; nil if there is none.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AlvyoScreenshot") {
      FlutterMethodChannel(name: "alvyo/screenshot", binaryMessenger: registrar.messenger())
        .setMethodCallHandler { call, result in
          guard call.method == "window" else {
            result(FlutterMethodNotImplemented)
            return
          }
          let window = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
          guard let window else {
            result(nil)
            return
          }
          // Twice the size in points, as the Flutter picture was.
          let format = UIGraphicsImageRendererFormat()
          format.scale = 2
          let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
          }
          result(image.pngData().map { FlutterStandardTypedData(bytes: $0) })
        }
    }
    // Sign in with Apple (lib/apple_sign_in.dart): the system's sheet.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AlvyoAppleSignIn") {
      FlutterMethodChannel(name: "alvyo/apple-sign-in", binaryMessenger: registrar.messenger())
        .setMethodCallHandler { [appleSignIn] call, result in
          guard call.method == "signIn", let nonce = call.arguments as? String else {
            result(FlutterMethodNotImplemented)
            return
          }
          appleSignIn.start(nonce: nonce, result: result)
        }
    }
    // The Apple Watch app (WatchBridge.swift).
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AlvyoWatch") {
      watch.attach(registrar.messenger())
    }
    // Turn-by-turn prompts.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AlvyoSpeech") {
      let channel = FlutterMethodChannel(name: "alvyo/speech", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { [speech] call, result in
        guard call.method == "say", let args = call.arguments as? [String: String],
          let text = args["text"], let language = args["language"]
        else {
          result(FlutterMethodNotImplemented)
          return
        }
        do {
          try speech.say(text, language: language)
          result(nil)
        } catch {
          result(FlutterError(code: "speech", message: error.localizedDescription, details: nil))
        }
      }
    }
  }
}

/// Sign in with Apple: asks for name and e-mail address and hands the
/// identity token and authorization code to Dart. The token carries the
/// SHA-256 of the nonce the API checks.
final class AppleSignIn: NSObject, ASAuthorizationControllerDelegate,
  ASAuthorizationControllerPresentationContextProviding
{
  private var result: FlutterResult?

  func start(nonce: String, result: @escaping FlutterResult) {
    self.result?(FlutterError(code: "busy", message: nil, details: nil))
    self.result = result
    let request = ASAuthorizationAppleIDProvider().createRequest()
    request.requestedScopes = [.fullName, .email]
    request.nonce = SHA256.hash(data: Data(nonce.utf8)).map { String(format: "%02x", $0) }.joined()
    let controller = ASAuthorizationController(authorizationRequests: [request])
    controller.delegate = self
    controller.presentationContextProvider = self
    controller.performRequests()
  }

  func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
    UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
      ?? ASPresentationAnchor()
  }

  func authorizationController(
    controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization
  ) {
    guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
      let token = credential.identityToken.flatMap({ String(data: $0, encoding: .utf8) }),
      let code = credential.authorizationCode.flatMap({ String(data: $0, encoding: .utf8) })
    else {
      finish(FlutterError(code: "failed", message: "no token", details: nil))
      return
    }
    // The name comes only the first time.
    let name = credential.fullName.map { PersonNameComponentsFormatter().string(from: $0) } ?? ""
    finish(["identityToken": token, "authorizationCode": code, "name": name])
  }

  func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
    let canceled = (error as? ASAuthorizationError)?.code == .canceled
    finish(FlutterError(code: canceled ? "canceled" : "failed", message: error.localizedDescription, details: nil))
  }

  private func finish(_ value: Any) {
    result?(value)
    result = nil
  }
}

/// Spoken navigation prompts. Other audio is turned down while one plays,
/// also with the screen locked (UIBackgroundModes audio), and the silent
/// switch does not mute them.
final class Speech: NSObject, AVSpeechSynthesizerDelegate {
  private let synthesizer = AVSpeechSynthesizer()

  override init() {
    super.init()
    synthesizer.delegate = self
  }

  func say(_ text: String, language: String) throws {
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(
      .playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
    try session.setActive(true)
    let utterance = AVSpeechUtterance(string: text)
    // A Swiss voice if there is one, else the language's usual one.
    let usual = ["de": "de-DE", "fr": "fr-FR", "it": "it-IT"][language] ?? "en-GB"
    utterance.voice =
      AVSpeechSynthesisVoice(language: "\(language)-CH") ?? AVSpeechSynthesisVoice(language: usual)
    synthesizer.speak(utterance)
  }

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
    release()
  }

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
    release()
  }

  /// Other audio back to full volume once nothing is being said. Right after
  /// the last word the session can still be busy, so a moment later.
  private func release() {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
      guard let self, !self.synthesizer.isSpeaking else { return }
      try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
  }
}
