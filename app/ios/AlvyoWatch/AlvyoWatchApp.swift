import SwiftUI

/// Alvyo on the wrist: the hike the iPhone navigates and records, with
/// pause and stop, and tours to start. The phone does the work (GPS,
/// recording, upload); the watch shows and controls.
@main
struct AlvyoWatchApp: App {
  @StateObject private var link = PhoneLink()

  var body: some Scene {
    WindowGroup {
      Group {
        if let hike = link.hike {
          HikeView(hike: hike)
        } else {
          StartView()
        }
      }
      .environmentObject(link)
      .task { link.activate() }
    }
  }
}

/// No hike on the phone: start one, on a tour or without.
struct StartView: View {
  @EnvironmentObject private var link: PhoneLink
  @State private var starting = false

  var body: some View {
    NavigationStack {
      List {
        if let answer = link.started, let text = startText(answer) {
          Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .listRowBackground(Color.clear)
        }
        Button {
          start(nil, title: "")
        } label: {
          Label("Ohne Tour aufzeichnen", systemImage: "record.circle")
        }
        .disabled(starting)
        .accessibilityIdentifier("record")
        if link.tours.isEmpty {
          Text("Noch keine geplanten Touren. Plane eine in Alvyo auf dem iPhone.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        } else {
          Section("Einer Tour folgen") {
            ForEach(link.tours) { tour in
              Button {
                start(tour.id, title: tour.title)
              } label: {
                VStack(alignment: .leading) {
                  Text(tour.title).lineLimit(2)
                  Text("\(formatDistance(tour.distanceM)) · \(formatDuration(tour.durationS))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
              }
              .disabled(starting)
              .accessibilityIdentifier("tour-\(tour.id)")
            }
          }
        }
      }
      .navigationTitle("Alvyo")
    }
  }

  private func start(_ routeId: String?, title: String) {
    starting = true
    Task {
      var args: [String: Any] = ["title": title]
      args["routeId"] = routeId
      link.started = await link.send("start", args)
      starting = false
    }
  }

  private func startText(_ answer: Answer) -> LocalizedStringKey? {
    switch answer {
    case .ok, .busy: return "Die Wanderung beginnt auf dem iPhone …"
    case .openPhone:
      return "Öffne Alvyo auf dem iPhone: Die Wanderung beginnt, sobald die App offen ist."
    case .notReady: return "Melde dich in Alvyo auf dem iPhone an."
    case .unreachable: return "iPhone nicht erreichbar"
    case .none, .failed, .unknown: return "Das hat nicht geklappt. Starte die Wanderung auf dem iPhone."
    }
  }
}
