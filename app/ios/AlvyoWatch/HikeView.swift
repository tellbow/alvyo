import SwiftUI

/// The hike on the phone: the map with the next turn, then the numbers with
/// pause and stop (swiped up).
struct HikeView: View {
  let hike: Hike

  var body: some View {
    TabView {
      MapPage(hike: hike)
      ControlsPage(hike: hike)
    }
    .tabViewStyle(.verticalPage)
  }
}

private struct MapPage: View {
  @EnvironmentObject private var link: PhoneLink
  let hike: Hike
  /// The whole line instead of the surroundings.
  @State private var whole = false

  var body: some View {
    VStack(spacing: 4) {
      Status(hike: hike, reachable: link.reachable)
      RouteMap(line: hike.line, position: hike.position, whole: whole || hike.position == nil)
        .contentShape(Rectangle())
        .onTapGesture { whole.toggle() }
        .accessibilityLabel(whole ? Text("Ganze Route") : Text("Um dich herum"))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("map")
      if let left = hike.remainingM {
        HStack {
          Text(formatDistance(left))
          Spacer()
          if let s = hike.remainingS { Text(formatDuration(s)) }
        }
        .font(.headline.monospacedDigit())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Noch \(formatDistance(left))"))
      } else if let done = hike.doneM {
        TimelineView(.periodic(from: .now, by: 1)) { t in
          HStack {
            Text(formatDistance(done))
            Spacer()
            Text(formatClock(hike.elapsed(t.date)))
          }
          .font(.headline.monospacedDigit())
        }
      }
    }
    .padding(.horizontal, 4)
  }
}

/// What matters most now: a problem, the pause, off the route, the
/// arrival, or the next turn.
private struct Status: View {
  let hike: Hike
  let reachable: Bool

  var body: some View {
    Group {
      if !reachable {
        line("iphone.slash", Text("iPhone nicht erreichbar"), .gray)
      } else if let gps = hike.gps {
        line("location.slash", gpsText(gps), .red)
      } else if hike.paused {
        line("pause.fill", Text("Pausiert"), .gray)
      } else if hike.offRoute {
        line("exclamationmark.triangle.fill", Text("\(hike.offRouteM) m neben der Route"), .red)
      } else if hike.arrived {
        line("flag.checkered", Text("Ziel erreicht"), .green)
      } else if let turn = hike.turn, let inM = hike.turnInM {
        HStack(spacing: 6) {
          Image(systemName: turnSymbol(turn)).font(.title2.bold())
          VStack(alignment: .leading, spacing: 0) {
            Text(formatDistance(inM)).font(.headline.monospacedDigit())
            turnText(turn).font(.footnote).lineLimit(1)
          }
          Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
      }
    }
  }

  private func line(_ symbol: String, _ text: Text, _ color: Color) -> some View {
    HStack(spacing: 6) {
      Image(systemName: symbol)
      text.font(.footnote.bold()).lineLimit(2)
      Spacer(minLength: 0)
    }
    .padding(.vertical, 4)
    .padding(.horizontal, 6)
    .background(color.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
  }
}

private struct ControlsPage: View {
  @EnvironmentObject private var link: PhoneLink
  let hike: Hike
  @State private var asking = false
  @State private var failed: Answer?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 8) {
        Text(hike.title).font(.headline).lineLimit(2)
        TimelineView(.periodic(from: .now, by: 1)) { t in
          Stat(label: "Unterwegs", value: formatClock(hike.elapsed(t.date)))
        }
        if let done = hike.doneM { Stat(label: "Gegangen", value: formatDistance(done)) }
        if let up = hike.ascentRemainingM { Stat(label: "Noch aufwärts", value: "↑ \(formatHeight(up))") }
        HStack {
          Button {
            press(hike.paused ? "resume" : "pause")
          } label: {
            Image(systemName: hike.paused ? "play.fill" : "pause.fill")
          }
          .accessibilityLabel(hike.paused ? Text("Weiter") : Text("Pause"))
          .accessibilityIdentifier("pause")
          .tint(.orange)
          Button(role: .destructive) {
            asking = true
          } label: {
            Image(systemName: "stop.fill")
          }
          .accessibilityLabel(Text("Beenden"))
          .accessibilityIdentifier("stop")
        }
        if failed != nil {
          Text("iPhone nicht erreichbar").font(.footnote).foregroundStyle(.secondary)
        }
      }
    }
    .confirmationDialog("Wanderung beenden und die Aufzeichnung speichern?", isPresented: $asking) {
      Button("Beenden", role: .destructive) { press("stop") }
      Button("Weitergehen", role: .cancel) {}
    }
  }

  private func press(_ command: String) {
    Task {
      let answer = await link.send(command)
      failed = answer == .ok ? nil : answer
    }
  }
}

private struct Stat: View {
  let label: LocalizedStringKey
  let value: String

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(label).font(.footnote).foregroundStyle(.secondary)
      Text(value).font(.title3.monospacedDigit())
    }
    .accessibilityElement(children: .combine)
  }
}

/// The route line (or track) and one's position, north up, without map
/// tiles: around the position, or the whole line.
struct RouteMap: View {
  let line: [(Double, Double)]
  let position: (Double, Double)?
  let whole: Bool

  /// Across the screen around the position.
  private static let aroundM = 800.0
  private static let mPerDeg = 111_320.0

  var body: some View {
    Canvas { ctx, size in
      guard let first = line.first ?? position else { return }
      let cosLat = cos(first.1 * .pi / 180)
      // Local metres from the first point.
      func metres(_ p: (Double, Double)) -> CGPoint {
        CGPoint(x: (p.0 - first.0) * cosLat * Self.mPerDeg, y: (p.1 - first.1) * Self.mPerDeg)
      }
      let pts = line.map(metres)
      let all = pts + (position.map { [metres($0)] } ?? [])
      let center: CGPoint, span: Double
      if whole || position == nil {
        let xs = all.map(\.x), ys = all.map(\.y)
        center = CGPoint(x: (xs.min()! + xs.max()!) / 2, y: (ys.min()! + ys.max()!) / 2)
        span = max(xs.max()! - xs.min()!, (ys.max()! - ys.min()!) * size.width / size.height, 200) * 1.1
      } else {
        center = metres(position!)
        span = Self.aroundM
      }
      let scale = size.width / span
      func screen(_ m: CGPoint) -> CGPoint {
        CGPoint(x: size.width / 2 + (m.x - center.x) * scale, y: size.height / 2 - (m.y - center.y) * scale)
      }
      var path = Path()
      if let start = pts.first { path.move(to: screen(start)) }
      for p in pts.dropFirst() { path.addLine(to: screen(p)) }
      let round = StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round)
      ctx.stroke(path, with: .color(.white), style: round)
      ctx.stroke(path, with: .color(Color(red: 0.49, green: 0.13, blue: 0.81)), style: round.with(width: 3.5))
      if let position {
        let p = screen(metres(position))
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - 7, y: p.y - 7, width: 14, height: 14)), with: .color(.white))
        ctx.fill(
          Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)),
          with: .color(Color(red: 0.15, green: 0.39, blue: 0.92)))
      }
    }
  }
}

extension StrokeStyle {
  fileprivate func with(width: CGFloat) -> StrokeStyle {
    var s = self
    s.lineWidth = width
    return s
  }
}
