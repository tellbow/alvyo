import Foundation
import WatchConnectivity
import WatchKit

/// A hike on the iPhone, as lib/navigation/watch.dart sends it.
struct Hike {
  let title: String
  let routeId: String?
  let paused: Bool
  let elapsedS: Double
  /// When the phone sent it.
  let at: Date
  /// The route's line, or the track so far without a route: (lon, lat).
  let line: [(Double, Double)]
  let position: (Double, Double)?
  let doneM: Double?
  let remainingM: Double?
  let remainingS: Double?
  let ascentRemainingM: Double?
  let offRoute: Bool
  let offRouteM: Int
  let arrived: Bool
  let turn: String?
  let turnInM: Double?
  /// lost, denied or off (GpsProblem).
  let gps: String?

  init?(_ d: [String: Any]?) {
    guard let d, let title = d["title"] as? String else { return nil }
    self.title = title
    routeId = d["routeId"] as? String
    paused = d["paused"] as? Bool ?? false
    elapsedS = (d["elapsedS"] as? NSNumber)?.doubleValue ?? 0
    at = Date(timeIntervalSince1970: ((d["at"] as? NSNumber)?.doubleValue ?? 0) / 1000)
    let flat = (d["line"] as? [NSNumber])?.map(\.doubleValue) ?? []
    line = stride(from: 0, to: flat.count - 1, by: 2).map { (flat[$0], flat[$0 + 1]) }
    let p = (d["position"] as? [NSNumber])?.map(\.doubleValue) ?? []
    position = p.count == 2 ? (p[0], p[1]) : nil
    doneM = (d["doneM"] as? NSNumber)?.doubleValue
    remainingM = (d["remainingM"] as? NSNumber)?.doubleValue
    remainingS = (d["remainingS"] as? NSNumber)?.doubleValue
    ascentRemainingM = (d["ascentRemainingM"] as? NSNumber)?.doubleValue
    offRoute = d["offRoute"] as? Bool ?? false
    offRouteM = (d["offRouteM"] as? NSNumber)?.intValue ?? 0
    arrived = d["arrived"] as? Bool ?? false
    turn = d["turn"] as? String
    turnInM = (d["turnInM"] as? NSNumber)?.doubleValue
    gps = d["gps"] as? String
  }

  /// Hiked by [now], without the pauses: the phone's time counted on.
  func elapsed(_ now: Date) -> Double {
    paused ? elapsedS : elapsedS + max(0, now.timeIntervalSince(at))
  }
}

/// A tour to start, from the phone's list.
struct Tour: Identifiable {
  let id: String
  let title: String
  let distanceM: Double
  let durationS: Double

  init?(_ d: [String: Any]) {
    guard let id = d["id"] as? String, let title = d["title"] as? String else { return nil }
    self.id = id
    self.title = title
    distanceM = (d["distanceM"] as? NSNumber)?.doubleValue ?? 0
    durationS = (d["durationS"] as? NSNumber)?.doubleValue ?? 0
  }
}

/// What the phone answered to a button (WatchLink._call, WatchBridge).
enum Answer: String {
  case ok, busy, none, notReady, openPhone, failed, unknown
  /// No answer: the phone out of reach.
  case unreachable
}

/// The iPhone app over WatchConnectivity (WatchBridge.swift there): it sends
/// the hike and the tours as the application context; buttons go back as
/// messages.
@MainActor
final class PhoneLink: NSObject, ObservableObject, WCSessionDelegate {
  @Published private(set) var hike: Hike?
  @Published private(set) var tours: [Tour] = []
  @Published private(set) var reachable = false

  /// The answer to the last start, while there is no hike yet.
  @Published var started: Answer?

  /// UI tests without a phone (AlvyoWatchUITests): a made-up one.
  private let fake = ProcessInfo.processInfo.arguments.contains("-fakePhone")

  func activate() {
    if fake {
      reachable = true
      apply(["tours": [["id": "r1", "title": "Napf", "distanceM": 11100, "durationS": 14100]]])
      return
    }
    guard WCSession.isSupported() else { return }
    WCSession.default.delegate = self
    WCSession.default.activate()
  }

  func send(_ command: String, _ args: [String: Any] = [:]) async -> Answer {
    if fake { return fakeAnswer(command, args) }
    guard WCSession.default.activationState == .activated else { return .unreachable }
    return await withCheckedContinuation { done in
      WCSession.default.sendMessage(
        args.merging(["command": command]) { a, _ in a },
        replyHandler: { reply in
          done.resume(returning: Answer(rawValue: reply["answer"] as? String ?? "") ?? .failed)
        },
        errorHandler: { _ in done.resume(returning: .unreachable) })
    }
  }

  private func apply(_ context: [String: Any]) {
    let next = Hike(context["hike"] as? [String: Any])
    // The phone warns too (a notification while it is locked); this is for
    // the wrist when the app is on screen.
    if let next, next.offRoute, !next.paused, !(hike?.offRoute ?? false) {
      WKInterfaceDevice.current().play(.failure)
    }
    if next != nil { started = nil }
    hike = next
    tours = (context["tours"] as? [[String: Any]] ?? []).compactMap(Tour.init)
  }

  /// What the made-up phone does with a button: as the app would, at once.
  private func fakeAnswer(_ command: String, _ args: [String: Any]) -> Answer {
    var hike: [String: Any] = [
      "title": args["title"] as? String ?? "Napf", "elapsedS": 600, "at": Date().timeIntervalSince1970 * 1000,
      "line": [8.0, 47.0, 8.005, 47.002, 8.01, 47.001], "position": [8.004, 47.0016],
      "doneM": 400, "remainingM": 10700, "remainingS": 13500, "ascentRemainingM": 700,
      "turn": "left", "turnInM": 120,
    ]
    let tours = (self.tours.map { ["id": $0.id, "title": $0.title, "distanceM": $0.distanceM, "durationS": $0.durationS] })
    switch command {
    case "start": break
    case "pause", "resume":
      guard let current = self.hike else { return .none }
      hike["title"] = current.title
      hike["paused"] = command == "pause"
    case "stop":
      guard self.hike != nil else { return .none }
      apply(["tours": tours])
      return .ok
    default: return .unknown
    }
    apply(["tours": tours, "hike": hike])
    return .ok
  }

  nonisolated func session(
    _ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?
  ) {
    let context = session.receivedApplicationContext, reachable = session.isReachable
    Task { @MainActor in
      self.reachable = reachable
      self.apply(context)
    }
  }

  nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
    Task { @MainActor in self.apply(context) }
  }

  nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
    let reachable = session.isReachable
    Task { @MainActor in self.reachable = reachable }
  }
}
