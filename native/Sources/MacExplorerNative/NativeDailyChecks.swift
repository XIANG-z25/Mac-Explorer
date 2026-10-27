import AppKit
import ExplorerCore

@MainActor
enum NativeDailyChecks {
  static func run(root: URL, output: URL) async throws -> [String] {
    var checks: [String] = []
    func expect(_ value: Bool, _ name: String) throws {
      guard value else { throw NativeSmoke.Failure(description: name) }; checks.append(name)
    }
    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    let suite = "local.zx.daily-check.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    ExplorerDailyProfile.configure(defaults, validation: false)
    let browser = BrowserController(initial: root, defaults: defaults)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 780), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentViewController = browser; window.center(); window.makeKeyAndOrderFront(nil)
    defer { browser.stopObserving(); window.orderOut(nil); window.contentViewController = nil }
    try await NativeSmoke.until { !browser.loading && browser.snapshot != nil }
    window.contentView?.layoutSubtreeIfNeeded()
    try expect(browser.dailyMode && browser.mode == .details, "Daily launch defaults to a details list")
    try expect(!defaults.bool(forKey: "versionControl"), "Repository status detection is disabled by default")
    func sidebarHas(_ title: String) -> Bool { descendants(browser.sidebar).contains { $0.accessibilityLabel() == title } }
    try expect(!sidebarHas(NL("网络")) && !sidebarHas(NL("隔空投送")), "Daily sidebar hides advanced locations")
    try expect(sidebarHas(NL("回收站")) && sidebarHas(NL("此电脑")), "Daily sidebar retains computer and Trash")
    try expect(!browser.contextItems().contains { $0.title == NL("在终端中打开") }, "Daily context menu hides terminal actions")
    for id in ["new-tab", "address", "cut", "copy", "paste", "quick-look", "search"] {
      try expect(!ExplorerShortcuts.bindings(id, overrides: [:]).isEmpty, "Daily workflow retains \(id) shortcuts")
    }
    try expect(ExplorerShortcuts.bindings("rename", overrides: [:]).contains("F2"), "F2 renames files")
    try expect(label("example.txt").font?.pointSize == 13, "File labels use readable 13 point type")
    try expect(browser.viewMenu().contains { $0.title == NL("设为新文件夹的默认视图") }, "View menu exposes a new-folder default")
    browser.setView(.icons, size: 48)
    browser.viewMenu().first { $0.title == NL("设为新文件夹的默认视图") }?.action?()
    let child = BrowserController(initial: root.appendingPathComponent("Folder 2"), defaults: defaults)
    try expect(child.mode == .icons && child.iconSize == 48, "New folders inherit the chosen default layout")
    browser.setView(.details)
    browser.viewMenu().first { $0.title == NL("应用到所有文件夹") }?.action?()
    let childAfterApply = BrowserController(initial: root.appendingPathComponent("Folder 2"), defaults: defaults)
    try expect(childAfterApply.mode == .details, "Apply to all folders clears prior layout overrides")
    defaults.set(15, forKey: ExplorerTypography.preferenceKey)
    try await NativeSmoke.until { browser.status.font?.pointSize == 14 }
    try expect(label("example.txt").font?.pointSize == 15, "Font setting changes visible labels without restart")
    defaults.set(13, forKey: ExplorerTypography.preferenceKey)
    try await NativeSmoke.until { browser.status.font?.pointSize == 12 }
    browser.table.selectRowIndexes(IndexSet([0, 1]), byExtendingSelection: false)
    try expect(browser.selectedPaths.count == 2, "Bulk rename receives the multiple selection")
    let bulkButton = browser.toolbarButton("batchRename")
    try expect(bulkButton != nil && bulkButton?.isHidden == false, "Bulk rename exists in the visible toolbar")
    try expect(bulkButton?.isEnabled == true, "Bulk rename toolbar action enables for multiple selection")
    browser.table.deselectAll(nil)
    browser.rememberServer("smb://example.invalid/share")
    try expect(defaults.stringArray(forKey: "recentSMBServers") == ["smb://example.invalid/share"], "Successful server endpoints can be remembered without credentials")
    browser.rememberServer("smb://user:secret@example.invalid/share")
    try expect(defaults.stringArray(forKey: "recentSMBServers") == ["smb://example.invalid/share"], "Credential-bearing server addresses are never saved")
    try NativeSmoke.capture(window, at: output.appendingPathComponent("daily-light.png"))
    NSApp.appearance = NSAppearance(named: .darkAqua)
    window.contentView?.needsDisplay = true
    try NativeSmoke.capture(window, at: output.appendingPathComponent("daily-dark.png"))
    NSApp.appearance = NSAppearance(named: .aqua)
    defaults.set(false, forKey: ExplorerDailyProfile.key)
    try await NativeSmoke.until { sidebarHas(NL("网络")) }
    try expect(browser.contextItems().contains { $0.title == NL("在终端中打开") }, "Full mode restores advanced actions without restarting")
    defaults.set(true, forKey: ExplorerDailyProfile.key)
    try await NativeSmoke.until { !sidebarHas(NL("网络")) }
    try expect(browser.dailyMode, "Returning to daily mode updates the current window")
    browser.executeAction("settings")
    try await Task.sleep(nanoseconds: 200_000_000)
    try NativeSmoke.capture(window, at: output.appendingPathComponent("daily-settings.png"))
    func childWindows(_ parent: NSWindow) -> [NSWindow] { (parent.childWindows ?? []).flatMap { [$0] + childWindows($0) } }
    let dialogViews = childWindows(window).compactMap(\.contentView).flatMap(descendants)
    try expect(dialogViews.contains { ($0 as? NSButton)?.title == NL("日常精简") }, "Settings exposes the daily/full mode choice")
    try expect(dialogViews.contains { ($0 as? NSButton)?.title == NL("启动时自动重连已连接过的 SMB 服务器") }, "Settings offers launch reconnect")
    try expect(dialogViews.contains { ($0 as? NSTextField)?.stringValue == NL("界面文字") }, "Settings offers interface font size")
    try expect(!dialogViews.contains { ($0 as? NSButton)?.title == NL("启用 Git / SVN 状态角标和右键菜单") }, "Daily settings hide repository integration")
    ExplorerDialogs.close(in: window)
    return checks
  }
}
