import SwiftUI

/// «12.3 km», below a kilometre «850 m» (as the app's format.dart).
func formatDistance(_ m: Double) -> String {
  if m < 1000 { return formatHeight(m) }
  return "\((m / 1000).formatted(.number.precision(.fractionLength(1)))) km"
}

func formatHeight(_ m: Double) -> String { "\(Int(m.rounded())) m" }

/// Hiking times in steps of 5 minutes: «3 h 25 min».
func formatDuration(_ s: Double) -> String {
  let minutes = Int((s / 60 / 5).rounded()) * 5
  let h = minutes / 60, m = minutes % 60
  if h == 0 { return "\(m) min" }
  return m == 0 ? "\(h) h" : "\(h) h \(m) min"
}

/// The time underway, ticking: «1:07:32».
func formatClock(_ s: Double) -> String {
  let t = Int(s)
  return String(format: "%d:%02d:%02d", t / 3600, t / 60 % 60, t % 60)
}

/// The turn kinds of lib/navigation/turns.dart.
func turnText(_ kind: String) -> Text {
  switch kind {
  case "sharp_left": Text("Scharf links abbiegen")
  case "left": Text("Links abbiegen")
  case "slight_left": Text("Leicht links abbiegen")
  case "keep_left": Text("Links halten")
  case "u_turn": Text("Umkehren")
  case "slight_right": Text("Leicht rechts abbiegen")
  case "right": Text("Rechts abbiegen")
  case "sharp_right": Text("Scharf rechts abbiegen")
  case "keep_right": Text("Rechts halten")
  default: Text(kind)
  }
}

func turnSymbol(_ kind: String) -> String {
  switch kind {
  case "sharp_left": "arrow.down.left"
  case "left": "arrow.turn.up.left"
  case "slight_left", "keep_left": "arrow.up.left"
  case "u_turn": "arrow.uturn.down"
  case "slight_right", "keep_right": "arrow.up.right"
  case "right": "arrow.turn.up.right"
  case "sharp_right": "arrow.down.right"
  default: "arrow.up"
  }
}

/// Why the phone has no position (GpsProblem in gps.dart).
func gpsText(_ problem: String) -> Text {
  switch problem {
  case "denied": Text("Alvyo darf den Standort nicht verwenden.")
  case "off": Text("Der Standort ist ausgeschaltet.")
  default: Text("Warte auf GPS …")
  }
}
