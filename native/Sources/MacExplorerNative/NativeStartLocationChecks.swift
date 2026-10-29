import AppKit
import ExplorerCore

@MainActor
enum NativeStartLocationChecks {
  private static func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
  private static func children(_ window: NSWindow) -> [NSWindow] { (window.childWindows ?? []).flatMap { [$0] + children($0) } }
  private static func until(_ condition: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(12)
    while !condition() { guard Date() < deadline else { throw NativeSmoke.Failure(description: "Start location check timed out") }; try await Task.sleep(nanoseconds: 20_000_000) }
  }
  private static func choose(_ title: String, owner: NSWindow) throws {
    guard let row = children(owner).compactMap(\.contentView).flatMap(descendants).first(where: { $0.accessibilityRole() == .menuItem && $0.accessibilityLabel() == title }), let panel = row.window,
      let event = NSEvent.mouseEvent(with: .leftMouseUp, location: row.convert(NSPoint(x: 20, y: 16), to: nil), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 0) else { throw NativeSmoke.Failure(description: "Missing start location option: " + title) }
    row.mouseUp(with: event)
  }
  static func run(output: URL) async throws -> [String] {
    let fm = FileManager.default, root = fm.temporaryDirectory.appendingPathComponent("native-start-location-" + UUID().uuidString)
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    let suite = "local.macexplorer.native-start-location." + UUID().uuidString, defaults = UserDefaults(suiteName: suite)!
    defaults.set(false, forKey: "versionControl")
    let originalMenu = NSApp.mainMenu, originalWindowsMenu = NSApp.windowsMenu, originalKey = NSApp.keyWindow
    let delegate = ApplicationDelegate(), board = NSPasteboard(name: .init(suite))
    let fixture = BrowserController(initial: root, defaults: defaults); fixture.home = root; fixture.filePasteboard = board
    defer {
      ExplorerMenu.dismiss(); for window in Array(delegate.browserWindows) { ExplorerDialogs.close(in: window); window.close() }
      fixture.stopObserving(); board.releaseGlobally(); defaults.removePersistentDomain(forName: suite); defaults.synchronize(); try? fm.removeItem(at: root)
      NSApp.mainMenu = originalMenu; NSApp.windowsMenu = originalWindowsMenu; originalKey?.makeKeyAndOrderFront(nil)
    }
    let first = delegate.createWindow(tab: BrowserTab(history: [root]), source: fixture, at: NSPoint(x: 160, y: 800))
    let second = delegate.createWindow(tab: BrowserTab(history: [root]), source: fixture, at: NSPoint(x: 220, y: 800))
    let a = first.contentViewController as! BrowserController, b = second.contentViewController as! BrowserController
    try await until { !a.loading && !b.loading }
    var checks: [String] = []
    func check(_ ok: Bool, _ title: String) throws { guard ok else { throw NativeSmoke.Failure(description: title) }; checks.append(title); print("PASS start location: " + title) }
    func picker(in window: NSWindow) throws -> NSButton {
      guard let picker = children(window).compactMap(\.contentView).flatMap(descendants).compactMap({ $0 as? NSButton }).first(where: { $0.accessibilityLabel() == NL("默认打开") }) else { throw NativeSmoke.Failure(description: "Missing start location picker") }; return picker
    }
    a.executeAction("settings"); try await until { ExplorerDialogs.isPresenting(in: first) }
    let control = try picker(in: first)
    try check(control.title == NL("个人文件夹"), "General settings retain the existing personal-folder default")
    control.performClick(nil)
    let options = children(first).compactMap(\.contentView).flatMap(descendants).filter { $0.accessibilityRole() == .menuItem }.compactMap { $0.accessibilityLabel() }
    try check(options == [NL("此电脑"), NL("个人文件夹"), NL("自选文件夹…")], "Startup picker exposes This PC, Personal folder and Choose Folder")
    try choose(NL("此电脑"), owner: first)
    try check(defaults.string(forKey: NativeStartLocation.preferenceKey) == "computer" && control.title == NL("此电脑"), "Choosing This PC saves the stable setting value")
    try check(a.directory == root && b.directory == root && a.tabs.count == 1 && b.tabs.count == 1, "Changing the default leaves both existing windows and tabs in place")
    if let panel = control.window, let view = panel.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
      view.layoutSubtreeIfNeeded(); view.cacheDisplay(in: view.bounds, to: bitmap)
      if let data = bitmap.representation(using: .png, properties: [:]) { try data.write(to: output.appendingPathComponent("native-start-location-settings.png")) }
    }
    ExplorerDialogs.close(in: first); a.newTab(); b.newTab()
    try check(a.directory.absoluteString == "explorer://computer" && b.directory == a.directory, "New tabs in both windows immediately use the shared default")
    b.executeAction("settings"); try await until { ExplorerDialogs.isPresenting(in: second) }
    try check(try picker(in: second).title == NL("此电脑"), "Reopening settings in another window reads the saved value")
    ExplorerDialogs.close(in: second)
    guard let dock = delegate.applicationDockMenu(NSApp) else { throw NativeSmoke.Failure(description: "Missing Dock menu") }
    dock.performActionForItem(at: 0)
    try check(delegate.browserWindows.count == 3 && delegate.browser.directory.absoluteString == "explorer://computer", "New Window uses This PC while preserving existing windows")
    for window in Array(delegate.browserWindows) { window.close() }
    _ = delegate.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false)
    try await until { delegate.window != nil && !delegate.browser.loading }
    try check(delegate.browser.defaults === defaults && delegate.browser.tabs.count == 1 && delegate.browser.directory.absoluteString == "explorer://computer", "Reopen with no windows uses the selected page in the original preference domain")
    for window in Array(delegate.browserWindows) { window.close() }
    dock.performActionForItem(at: 1)
    try await until { delegate.window != nil && !delegate.browser.loading }
    try check(delegate.browser.tabs.count == 1 && delegate.browser.directory.absoluteString == "explorer://computer", "Dock New Tab with no windows creates exactly one selected landing page")
    for window in Array(delegate.browserWindows) { window.close() }
    let file = root.appendingPathComponent("explicit.txt"); try Data("preserve".utf8).write(to: file)
    delegate.application(NSApp, open: [file]); try await until { delegate.browser != nil && !delegate.browser.loading && delegate.browser.selectedPaths.contains(file.path) }
    try check(delegate.browser.directory.path == root.path, "An externally opened file overrides This PC and remains selected")
    let current = delegate.browser!, owner = delegate.window!
    current.executeAction("settings"); try await until { ExplorerDialogs.isPresenting(in: owner) }
    try picker(in: owner).performClick(nil); try choose(NL("个人文件夹"), owner: owner); ExplorerDialogs.close(in: owner)
    current.newTab(); try await until { !current.loading }
    try check(current.directory.path == root.path && defaults.string(forKey: NativeStartLocation.preferenceKey) == "home", "Choosing Personal folder applies to subsequent tabs")
    dock.performActionForItem(at: 0); try await until { !delegate.browser.loading }
    try check(delegate.browser.directory.path == root.appendingPathComponent("Downloads").path, "New windows follow the selected default location")
    try NativeSessions.save([NativeSavedWindow(locations: ["explorer://computer", root.absoluteString], frame: "")], to: defaults)
    let restored = NativeSessions.load(defaults)
    delegate.browser.restoreLocations(restored[0].locations)
    try check(delegate.browser.tabs.count == 2 && delegate.browser.tabs.first?.directory.path == root.path && delegate.browser.tabs.contains { $0.directory.absoluteString == "explorer://computer" }, "Saved-window restoration retains saved pages and the existing personal-folder anchor")
    defaults.set("computer", forKey: NativeStartLocation.preferenceKey); guard defaults.synchronize() else { throw NativeSmoke.Failure(description: "Cannot persist start-location fixture") }
    try await relaunch(root: root, suite: suite, output: output)
    try check(true, "Selected startup page survives a separate application process")
    try check(try Data(contentsOf: file) == Data("preserve".utf8), "Startup settings preserve all fixture file content")
    return checks
  }
  private static func relaunch(root: URL, suite: String, output: URL) async throws {
    let process = Process(); process.executableURL = Bundle.main.executableURL
    let report = output.appendingPathComponent("start-location-relaunch.json"), log = output.appendingPathComponent("start-location-relaunch.log")
    process.arguments = ["--smoke-test", root.path, "--report", report.path, "--start-location-settings", suite]
    FileManager.default.createFile(atPath: log.path, contents: nil); let handle = try FileHandle(forWritingTo: log); defer { try? handle.close() }
    process.standardOutput = handle; process.standardError = handle; try process.run(); defer { if process.isRunning { process.terminate() } }
    try await until { !process.isRunning }
    guard process.terminationStatus == 0, let data = try JSONSerialization.jsonObject(with: Data(contentsOf: report)) as? [String: Any], data["passed"] as? Bool == true else { throw NativeSmoke.Failure(description: "Start location relaunch failed") }
  }
  static func restore(root: URL, suite: String, window: NSWindow) async throws -> [String] {
    let prefix = "local.macexplorer.native-start-location."
    guard suite.hasPrefix(prefix), UUID(uuidString: String(suite.dropFirst(prefix.count))) != nil, root.lastPathComponent.hasPrefix("native-start-location-"), let defaults = UserDefaults(suiteName: suite), NativeStartLocation.load(defaults) == .computer else { throw NativeSmoke.Failure(description: "Invalid start-location fixture") }
    (window.contentViewController as? BrowserController)?.stopObserving()
    let initial = NativeStartLocation.initialURL(explicit: nil, defaults: defaults, home: root)
    let browser = BrowserController(initial: initial, defaults: defaults); browser.home = root; window.contentViewController = browser
    browser.executeAction("settings"); try await until { ExplorerDialogs.isPresenting(in: window) }
    guard initial.absoluteString == "explorer://computer", children(window).compactMap(\.contentView).flatMap(descendants).compactMap({ $0 as? NSButton }).contains(where: { $0.accessibilityLabel() == NL("默认打开") && $0.title == NL("此电脑") }) else { throw NativeSmoke.Failure(description: "Start location did not survive process restart") }
    ExplorerDialogs.close(in: window); browser.stopObserving()
    return ["Startup page preference survives process restart", "Settings and initial browser agree on the persisted page"]
  }
}
