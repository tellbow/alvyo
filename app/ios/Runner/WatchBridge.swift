import Flutter
import UIKit
import WatchConnectivity

/// The Apple Watch app (ios/AlvyoWatch): the hike on the phone's screen and
/// the tours to start come from Dart (lib/navigation/watch.dart) and go to
/// the watch; the watch's buttons come back to Dart. The phone navigates and
/// records, the watch shows and controls.
final class WatchBridge: NSObject, WCSessionDelegate {
  private var channel: FlutterMethodChannel?

  /// The hike and the tours, sent together: the watch keeps only the
  /// latest application context.
  private var context: [String: Any] = [:]

  /// A start asked for on the watch while the app was not open (the GPS
  /// starts only in the foreground): done once it is, if still recent.
  private var pending: (routeId: String?, title: String, at: Date)?
  private static let pendingFor: TimeInterval = 10 * 60

  /// Early at launch: the watch may have woken the app with a message.
  func activate() {
    guard WCSession.isSupported() else { return }
    WCSession.default.delegate = self
    WCSession.default.activate()
  }

  func attach(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "alvyo/watch", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      switch call.method {
      case "hike":
        self.context["hike"] = call.arguments as? [String: Any]
        self.send()
        result(nil)
      case "tours":
        self.context["tours"] = call.arguments as? [[String: Any]]
        self.send()
        result(nil)
      case "pendingStart":
        defer { self.pending = nil }
        guard let p = self.pending, Date().timeIntervalSince(p.at) < Self.pendingFor else {
          result(nil)
          return
        }
        var start: [String: Any] = ["title": p.title]
        start["routeId"] = p.routeId
        result(start)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.channel = channel
  }

  private func send() {
    let session = WCSession.default
    guard WCSession.isSupported(), session.activationState == .activated, session.isPaired,
      session.isWatchAppInstalled
    else { return }
    // A new context every time: «at» changes with each.
    try? session.updateApplicationContext(context)
  }

  // A button on the watch.
  func session(
    _ session: WCSession, didReceiveMessage message: [String: Any],
    replyHandler: @escaping ([String: Any]) -> Void
  ) {
    DispatchQueue.main.async { [self] in
      guard let command = message["command"] as? String else {
        replyHandler(["answer": "unknown"])
        return
      }
      if command == "start" && (UIApplication.shared.applicationState != .active || channel == nil) {
        pending = (message["routeId"] as? String, message["title"] as? String ?? "", Date())
        replyHandler(["answer": "openPhone"])
        return
      }
      guard let channel else {
        replyHandler(["answer": "openPhone"])
        return
      }
      channel.invokeMethod(command, arguments: message) { answer in
        replyHandler(["answer": answer as? String ?? "failed"])
      }
    }
  }

  func session(
    _ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?
  ) {
    DispatchQueue.main.async { self.send() }
  }

  // The watch app installed (or a watch paired) during a hike: it gets the
  // hike now, not only with the next position.
  func sessionWatchStateDidChange(_ session: WCSession) {
    DispatchQueue.main.async { self.send() }
  }

  func sessionDidBecomeInactive(_ session: WCSession) {}

  // Another watch paired: go on with it.
  func sessionDidDeactivate(_ session: WCSession) {
    WCSession.default.activate()
  }
}
