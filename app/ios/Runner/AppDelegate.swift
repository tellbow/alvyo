import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
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
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "OdysgehBackup") {
      let channel = FlutterMethodChannel(name: "odysgeh/backup", binaryMessenger: registrar.messenger())
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
  }
}
