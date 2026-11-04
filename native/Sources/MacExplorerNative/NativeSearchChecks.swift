import AppKit
import ExplorerCore

@MainActor
enum NativeSearchChecks {
  static func run() async throws -> [String] {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("native-search-ui-" + UUID().uuidString)
    try fm.createDirectory(at: root, withIntermediateDirectories: false)
    let video = root.appendingPathComponent("clip.mp4"), text = root.appendingPathComponent("notes.txt")
    try Data("fixture video".utf8).write(to: video); try Data("fixture notes".utf8).write(to: text)
    let domain = "native-search-ui." + UUID().uuidString
    let defaults = UserDefaults(suiteName: domain)!
    let browser = BrowserController(initial: root, defaults: defaults)
    browser.home = root
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentViewController = browser
    browser.reload()
    defer { browser.stopObserving(); window.close(); defaults.removePersistentDomain(forName: domain); try? fm.removeItem(at: root) }
    var checks: [String] = []
    func check(_ condition: Bool, _ message: String) throws {
      guard condition else { throw NativeSmoke.Failure(description: message) }; checks.append(message)
    }
    try await until { !browser.loading && browser.entries.count == 2 }
    defaults.set("wildcard", forKey: "searchMode")
    browser.applySearchFilters(FileSearchFilters(kind: .video))
    try await until { !browser.loading && browser.entries.map(\.name) == ["clip.mp4"] }
    try check(browser.searchBox.filtersActive, "Filter-only wildcard search lists videos without a keyword")
    browser.applySearchFilters(FileSearchFilters())
    try await until { !browser.loading && browser.entries.count == 2 }
    try check(!browser.searchBox.filtersActive, "Clearing the last search filter restores the folder listing")
    let tagged = FinderTags.set(["fixture-tag"], on: [text])
    try check(tagged.errors.isEmpty, "Search UI fixture tags are created on temporary files")
    browser.applySearchFilters(FileSearchFilters(tag: "fixture-tag"))
    try await until { !browser.loading && browser.entries.map(\.name) == ["notes.txt"] }
    browser.applySearchFilters(FileSearchFilters(tag: ""))
    try await until { !browser.loading && browser.entries.count == 2 }
    try check(!browser.searchBox.filtersActive, "Removing the final tag filter exits stale search results")
    try check(try Data(contentsOf: video) == Data("fixture video".utf8), "Search filters leave file payloads unchanged")
    return checks
  }

  private static func until(_ condition: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(10)
    while !condition() {
      guard Date() < deadline else { throw NativeSmoke.Failure(description: "Search UI fixture timed out") }
      try await Task.sleep(nanoseconds: 20_000_000)
    }
  }
}
