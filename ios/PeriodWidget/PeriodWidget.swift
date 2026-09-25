import SwiftUI
import WidgetKit

/// What the app hands the widget. See WidgetBridge in AppDelegate.swift and
/// lib/presentation/widget/widget_sync.dart; the two must agree on this shape.
struct Snapshot: Decodable {
  /// The app lock is on: show nothing of hers.
  let locked: Bool
  /// She chose the detailed widget in Settings.
  let detailed: Bool
  /// "natural", "pregnancy", ...
  let mode: String
  /// The last period start, "yyyy-MM-dd", or nil if none.
  let lastStart: String?
  /// Her usual cycle length, only to fill the ring's arc.
  let typicalLength: Int?
  /// "Day {day}" in the app's language.
  let dayLabel: String
  /// "{weeks}+{days}" in the app's language.
  let pregnancyLabel: String
  /// A second line, only when detailed, already in the app's language.
  let detailLine: String?
}

struct Entry: TimelineEntry {
  let date: Date
  let snapshot: Snapshot?
}

enum SnapshotStore {
  static func read() -> Snapshot? {
    guard
      let prefix = Bundle.main.object(forInfoDictionaryKey: "AppIdentifierPrefix") as? String
    else { return nil }
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "app.period.widget",
      kSecAttrAccount as String: "snapshot",
      kSecAttrAccessGroup as String: prefix + "app.period.shared",
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
      let data = item as? Data
    else { return nil }
    return try? JSONDecoder().decode(Snapshot.self, from: data)
  }
}

struct Provider: TimelineProvider {
  func placeholder(in context: Context) -> Entry {
    Entry(date: Date(), snapshot: nil)
  }

  func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
    // The widget gallery shows this preview to anyone browsing widgets: never
    // her data there.
    completion(Entry(date: Date(), snapshot: context.isPreview ? nil : SnapshotStore.read()))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
    let snapshot = SnapshotStore.read()
    // One entry now and one at each of the next seven midnights: the day
    // number changes at midnight, local time, and nowhere else.
    let calendar = Calendar.current
    var dates = [Date()]
    var midnight = calendar.startOfDay(for: Date())
    for _ in 0..<7 {
      midnight = calendar.date(byAdding: .day, value: 1, to: midnight)!
      dates.append(midnight)
    }
    completion(Timeline(entries: dates.map { Entry(date: $0, snapshot: snapshot) }, policy: .atEnd))
  }
}

/// Days since the last start, by calendar day in the phone's own time zone:
/// the same "a cycle day is a calendar day" rule as the app (CLAUDE.md §3).
func daysSince(_ iso: String, on date: Date) -> Int? {
  let parts = iso.split(separator: "-").compactMap { Int($0) }
  guard parts.count == 3 else { return nil }
  let calendar = Calendar.current
  guard
    let start = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
  else { return nil }
  return calendar.dateComponents(
    [.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: date)
  ).day
}

struct PeriodWidgetView: View {
  let entry: Entry
  @Environment(\.colorScheme) private var scheme

  private var rose: Color { Color(red: 0.71, green: 0.41, blue: 0.50) }
  private var track: Color {
    scheme == .dark ? Color.white.opacity(0.12) : Color(red: 0.94, green: 0.88, blue: 0.90)
  }

  /// The centre text and the arc's fill, or nil for an empty ring.
  private var content: (text: String, fraction: Double)? {
    guard let snap = entry.snapshot, !snap.locked, let start = snap.lastStart,
      let elapsed = daysSince(start, on: entry.date), elapsed >= 0
    else { return nil }
    if snap.mode == "pregnancy" {
      // Stops past 44+0, as in the app (docs/cycle-logic.md §6).
      guard elapsed <= 44 * 7 else { return nil }
      let text = snap.pregnancyLabel
        .replacingOccurrences(of: "{weeks}", with: String(elapsed / 7))
        .replacingOccurrences(of: "{days}", with: String(elapsed % 7))
      return (text, min(Double(elapsed) / 280.0, 1))
    }
    let day = elapsed + 1
    let text = snap.dayLabel.replacingOccurrences(of: "{day}", with: String(day))
    let fraction = snap.typicalLength.map { min(Double(day) / Double(max($0, 1)), 1) } ?? 0
    return (text, fraction)
  }

  var body: some View {
    VStack(spacing: 6) {
      ZStack {
        Circle().stroke(track, lineWidth: 9)
        if let content {
          Circle()
            .trim(from: 0, to: content.fraction)
            .stroke(rose, style: StrokeStyle(lineWidth: 9, lineCap: .round))
            .rotationEffect(.degrees(-90))
          Text(content.text)
            .font(.system(size: 22, weight: .bold, design: .rounded))
            .monospacedDigit()
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .padding(.horizontal, 10)
        }
      }
      .padding(4)
      if let line = entry.snapshot?.detailLine, entry.snapshot?.detailed == true,
        entry.snapshot?.locked == false
      {
        Text(line)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(2)
          .multilineTextAlignment(.center)
          .minimumScaleFactor(0.8)
      }
    }
    .containerBackground(for: .widget) {
      scheme == .dark ? Color(red: 0.09, green: 0.07, blue: 0.08) : Color.white
    }
    // One label for VoiceOver, or none when there is nothing to say.
    .accessibilityElement(children: .combine)
  }
}

struct PeriodWidget: Widget {
  let kind = "PeriodWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: Provider()) { entry in
      PeriodWidgetView(entry: entry)
    }
    .configurationDisplayName("Period.")
    .description("")
    // Home screen only: the lock screen families would show it to anyone who
    // glances at the phone without unlocking it.
    .supportedFamilies([.systemSmall])
  }
}
