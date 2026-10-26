import AppKit
import ExplorerCore

@MainActor
enum NativeNetworkDeleteChecks {
  private static func until(_ predicate: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(10)
    while !predicate() { guard Date() < deadline else { throw NativeSmoke.Failure(description: "Network deletion policy timed out") }; try await Task.sleep(nanoseconds: 20_000_000) }
  }
  static func run(output: URL) async throws -> [String] {
#if EXPLORER_DELETION_TESTS
    let fm = FileManager.default, root = fm.temporaryDirectory.appendingPathComponent("native-network-delete-" + UUID().uuidString)
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    let suite = "native-network-delete." + UUID().uuidString, defaults = UserDefaults(suiteName: suite)!
    defaults.set(false, forKey: "versionControl"); defaults.set(true, forKey: "skipTrashConfirmation")
    let browser = BrowserController(initial: root, defaults: defaults)
    browser.home = root; browser.filePasteboard = NSPasteboard(name: .init(suite))
    let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 1050, height: 700), styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentViewController = browser
    let trash = root.appendingPathComponent("simulated-trash"); try fm.createDirectory(at: trash, withIntermediateDirectories: true)
    var recycleCalls = 0
    browser.deletionNetworkLocation = { $0.lastPathComponent.hasPrefix("remote") }
    browser.prepareDeletionItems = { sources in
      try sources.flatMap { source in
        try PreparedDeletion.fixtures([source], root: root, classification: { parent in
          if source.lastPathComponent == "remote-unknown" { return nil }
          return source.lastPathComponent.hasPrefix("remote") || parent.lastPathComponent == "remote-parent" ? .network : .local
        })
      }
    }
    browser.recycleItem = { source, _, _ in
      recycleCalls += 1
      let result = FileActions.trash([source], testTrash: trash)
      guard let destination = result.changes.first?.destination else { throw NativeSmoke.Failure(description: result.errors.joined(separator: "\n")) }
      return destination
    }
    defer { browser.stopObserving(); window.close(); browser.filePasteboard.releaseGlobally(); defaults.removePersistentDomain(forName: suite); try? fm.removeItem(at: root) }
    var checks: [String] = []
    func check(_ value: Bool, _ text: String) throws { guard value else { throw NativeSmoke.Failure(description: text) }; checks.append(text) }
    func file(_ name: String) throws -> URL { let url = root.appendingPathComponent(name); try Data(name.utf8).write(to: url); return url }
    func select(_ sources: [URL]) async throws {
      browser.reload(); try await until { !browser.loading && sources.allSatisfy { source in browser.entries.contains { $0.url.path == source.path } } }
      browser.selectedPaths = Set(sources.map(\.path)); browser.updateMode(persist: false)
    }
    func rejected(_ sources: [URL]) async throws {
      try await select(sources); browser.executeAction("trash")
      try await until { !browser.busy && !browser.loading && browser.lastError != nil }
      try check(!ExplorerDialogs.isPresenting(in: window) && sources.allSatisfy { fm.fileExists(atPath: $0.path) }, "Network deletion opens no confirmation and preserves every selected item")
    }
    let remote = try file("remote-file"), local = try file("local-file")
    try await select([remote]); browser.executeAction("cut"); let version = browser.filePasteboard.changeCount
    try check(browser.contextItems().first { $0.title == NL("删除") }?.enabled == false, "Known network selections disable the context-menu Delete action")
    try await rejected([remote])
    try check(recycleCalls == 0 && browser.filePasteboard.changeCount == version, "Keyboard deletion cannot bypass the policy or consume the clipboard")
    try await rejected([local, remote]); try check(recycleCalls == 0, "Mixed selections stop before moving any local item")
    let unknown = try file("remote-unknown"); try await rejected([unknown]); try check(recycleCalls == 0, "Unknown classification cannot fall back to Trash")
    try await select([local]); browser.executeAction("trash")
    try await until { !browser.busy && !browser.loading && !fm.fileExists(atPath: local.path) }
    try check(recycleCalls == 1 && fm.fileExists(atPath: trash.appendingPathComponent(local.lastPathComponent).path), "Local items still move into the simulated Trash")
    let remoteParent = root.appendingPathComponent("remote-parent"), alias = root.appendingPathComponent("local-alias")
    try fm.createDirectory(at: remoteParent, withIntermediateDirectories: true); try Data("keep".utf8).write(to: remoteParent.appendingPathComponent("item")); try fm.createSymbolicLink(at: alias, withDestinationURL: remoteParent)
    browser.navigate(to: alias); try await until { !browser.loading && browser.entries.count == 1 }
    try await rejected([alias.appendingPathComponent("item")]); try check(recycleCalls == 1, "A local-looking alias cannot bypass actual-parent network classification")
    browser.navigate(to: root); try await until { !browser.loading }
    var large: [URL] = []
    for i in 0..<65 { large.append(try file("batch-\(i)")) }
    browser.prepareDeletionItems = PreparedDeletion.prepare
    try await select(large); browser.executeAction("trash")
    try await until { !browser.busy && !browser.loading }
    try check(large.allSatisfy { !fm.fileExists(atPath: $0.path) } && recycleCalls == 66, "Actual preparation and AppKit workflow recycle 65 local files in one operation")
    try check(!window.isVisible, "Deletion policy checks never display or focus a window")
    return checks
#else
    return ["SKIP network deletion injection: validation build required"]
#endif
  }
}
