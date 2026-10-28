import Foundation

public enum EntryGroupMode: String, Sendable { case none, modified, created, kind }
public struct EntryGroup: Sendable {
  public let id: String
  public let title: String
  public let entries: [FileEntry]
}
public enum EntryGrouping {
  /// Calendar intervals respect locale, time zone, daylight saving, and week boundaries.
  public static func apply(_ entries: [FileEntry], mode: EntryGroupMode, newestFirst: Bool = true,
                           foldersFirst: Bool = true, now: Date = Date(), calendar: Calendar = .current) -> [EntryGroup] {
    guard mode != .none else { return [] }
    let today = calendar.startOfDay(for: now)
    let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
    let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
    let week = calendar.dateInterval(of: .weekOfYear, for: now)!.start
    let lastWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: week)!
    let month = calendar.dateInterval(of: .month, for: now)!.start
    let lastMonth = calendar.date(byAdding: .month, value: -1, to: month)!
    func bucket(_ entry: FileEntry) -> (String, String, Int) {
      if foldersFirst && entry.isDirectory { return ("folders", NL("文件夹"), -1) }
      if mode == .kind { return ("kind:" + entry.kind, entry.kind, 0) }
      guard let date = mode == .created ? entry.created : entry.modified else { return ("unknown", NL("日期未知"), 8) }
      if date >= tomorrow { return ("future", NL("将来"), 0) }
      if date >= today { return ("today", NL("今天"), 1) }
      if date >= yesterday { return ("yesterday", NL("昨天"), 2) }
      if date >= week { return ("week", NL("本周早些时候"), 3) }
      if date >= lastWeek { return ("last-week", NL("上周"), 4) }
      if date >= month { return ("month", NL("本月早些时候"), 5) }
      if date >= lastMonth { return ("last-month", NL("上个月"), 6) }
      return ("older", NL("更早"), 7)
    }
    var buckets: [String: [FileEntry]] = [:], titles: [String: String] = [:], ranks: [String: Int] = [:]
    for entry in entries {
      let (key, title, rank) = bucket(entry)
      buckets[key, default: []].append(entry); titles[key] = title; ranks[key] = rank
    }
    let keys = buckets.keys.sorted { a, b in
      if a == "folders" || b == "folders" { return a == "folders" }
      if a == "unknown" || b == "unknown" { return b == "unknown" }
      if mode == .kind {
        let comparison = titles[a]!.localizedStandardCompare(titles[b]!)
        return newestFirst ? comparison == .orderedDescending : comparison == .orderedAscending
      }
      return newestFirst ? ranks[a]! < ranks[b]! : ranks[a]! > ranks[b]!
    }
    return keys.map { EntryGroup(id: $0, title: titles[$0]!, entries: buckets[$0]!) }
  }
}
