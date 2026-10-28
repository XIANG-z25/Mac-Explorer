import Foundation

@main struct GroupingChecks {
  static func main() throws {
    var checks = 0
    func expect(_ value: Bool, _ message: String) throws {
      guard value else { throw NSError(domain: "GroupingChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }; checks += 1
    }
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!; calendar.firstWeekday = 2
    let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 14))!
    func date(_ days: Int) -> Date { calendar.date(byAdding: .day, value: days, to: now)! }
    func entry(_ name: String, _ modified: Date?, folder: Bool = false) -> FileEntry {
      FileEntry(url: URL(fileURLWithPath: "/fixture/" + name), name: name, isDirectory: folder, isSymbolicLink: false, isPackage: false, size: 1, modified: modified, isHidden: false, created: date(-90))
    }
    let input = [entry("old-folder", date(-100), folder: true), entry("file10.txt", now), entry("file2.txt", now), entry("yesterday.txt", date(-1)), entry("week.txt", date(-3)), entry("last-week.txt", date(-10)), entry("month.txt", date(-20)), entry("last-month.txt", date(-35)), entry("older.txt", date(-100)), entry("future.txt", date(2)), entry("unknown.txt", nil)]
    for sort in EntrySort.allCases { for ascending in [true, false] {
      let ordered = EntryQuery.apply(input, showHidden: false, query: "", sort: sort, ascending: ascending)
      for newest in [true, false] {
        let groups = EntryGrouping.apply(ordered, mode: .modified, newestFirst: newest, now: now, calendar: calendar)
        try expect(groups.first?.id == "folders", "Folders are pinned in every sort direction")
        try expect(groups.last?.id == "unknown", "Unknown dates are always last")
        try expect(groups.flatMap(\.entries).count == input.count, "Grouping preserves every entry")
        try expect(Set(groups.flatMap(\.entries).map(\.id)).count == input.count, "Grouping never duplicates entries")
        for group in groups { try expect(group.entries == ordered.filter { candidate in group.entries.contains { $0.id == candidate.id } }, "Group order retains the independent file sort") }
      }
    } }
    let groups = EntryGrouping.apply(input, mode: .modified, now: now, calendar: calendar)
    try expect(groups.map(\.id) == ["folders", "future", "today", "yesterday", "week", "last-week", "month", "last-month", "older", "unknown"], "Date intervals have no overlaps or gaps")
    try expect(EntryGrouping.apply(input, mode: .none).isEmpty, "None produces no artificial groups")
    try expect(EntryGrouping.apply([], mode: .modified).isEmpty, "Empty directories produce no empty headers")
    let inline = EntryGrouping.apply(input, mode: .modified, foldersFirst: false, now: now, calendar: calendar)
    try expect(!inline.contains { $0.id == "folders" } && inline.first { $0.id == "older" }?.entries.contains { $0.isDirectory } == true, "Unpinned folders use their actual modified date")
    try expect(EntryGrouping.apply(input, mode: .created, now: now, calendar: calendar).map(\.id) == ["folders", "older"], "Created grouping reads creation dates")
    let kinds = [entry("a.txt", now), entry("b.jpg", now), entry("c.zip", now)]
    let forward = EntryGrouping.apply(kinds, mode: .kind, newestFirst: false)
    let backward = EntryGrouping.apply(kinds, mode: .kind, newestFirst: true)
    try expect(forward.map(\.id) == backward.reversed().map(\.id), "Type group direction agrees with ascending and descending menus")
    var pacific = calendar; pacific.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    let dstNow = pacific.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 12))!
    let previous = pacific.date(byAdding: .day, value: -1, to: dstNow)!
    let dst = EntryGrouping.apply([entry("today", dstNow), entry("previous", previous)], mode: .modified, now: dstNow, calendar: pacific)
    try expect(dst.map(\.id) == ["today", "yesterday"], "DST uses calendar days instead of 24-hour arithmetic")
    let midnight = calendar.startOfDay(for: now)
    try expect(EntryGrouping.apply([entry("boundary", midnight)], mode: .modified, now: now, calendar: calendar).first?.id == "today", "Midnight belongs to today")
    let large = (0..<10000).map { entry("file-\($0).txt", date(-($0 % 100))) }
    let started = Date()
    let sorted = EntryQuery.apply(large, showHidden: false, query: "", sort: .modified, ascending: false)
    let largeGroups = EntryGrouping.apply(sorted, mode: .modified, now: now, calendar: calendar)
    try expect(largeGroups.flatMap(\.entries).count == 10000, "10,000 entries retain complete grouped content")
    print("GroupingChecks: \(checks) assertions passed; sort and group 10,000 entries: \(Date().timeIntervalSince(started) * 1000) ms")
  }
}
