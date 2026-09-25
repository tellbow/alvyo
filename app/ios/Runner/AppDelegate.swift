import AVFoundation
import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let speech = Speech()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Off-route warnings are local notifications (flutter_local_notifications).
    UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
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
