import AppKit
import ExplorerCore

@MainActor
enum NativeWorkflowChecks {
  static func run(output: URL) async throws -> [String] {
    let fm = FileManager.default, root = fm.temporaryDirectory.appendingPathComponent("explorer-workflow-" + UUID().uuidString)
    let folder = root.appendingPathComponent("Folder")
    try fm.createDirectory(at: folder, withIntermediateDirectories: true)
    for index in 0..<90 { try Data("original-\(index)".utf8).write(to: root.appendingPathComponent(String(format: "File %03d", index) + (index % 2 == 0 ? ".txt" : ".md"))) }
    let suite = "local.macexplorer.workflow." + UUID().uuidString, defaults = UserDefaults(suiteName: suite)!
    defaults.set(false, forKey: "versionControl")
    ExplorerTypography.configure(defaults)
    let browser = BrowserController(initial: root, defaults: defaults); browser.home = root
    browser.filePasteboard = NSPasteboard(name: .init(suite))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 740), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentViewController = browser; browser.reload()
    defer { browser.stopObserving(); browser.filePasteboard.releaseGlobally(); window.close(); defaults.removePersistentDomain(forName: suite); ExplorerTypography.baseSize = 13; try? fm.removeItem(at: root) }
    var checks: [String] = []
    func check(_ value: Bool, _ text: String) throws { guard value else { throw NativeSmoke.Failure(description: text) }; checks.append(text); print("PASS workflow: " + text) }
    func until(_ condition: () -> Bool) async throws {
      let deadline = Date().addingTimeInterval(12)
      while !condition() { guard Date() < deadline else { throw NativeSmoke.Failure(description: "Workflow timed out") }; try await Task.sleep(nanoseconds: 20_000_000) }
      window.contentView?.layoutSubtreeIfNeeded(); browser.collection.layoutSubtreeIfNeeded()
    }
    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    try await until { !browser.loading && browser.entries.count == 91 }
    try check(browser.groupMode == .none && browser.displayRows.count == browser.entries.count, "Grouping starts disabled")
    try check(browser.viewMenu().contains { $0.title == NL("分组依据") } && !browser.sortMenu().contains { $0.title == NL("分组依据") }, "Grouping is offered in View")
    for layout in [ExplorerLayoutMode.details, .icons, .list, .tiles, .content] {
      browser.setView(layout, size: 64); browser.setGrouping(.kind); window.contentView?.layoutSubtreeIfNeeded()
      try check(browser.displayRows.compactMap(\.entry).count == 91, "\(layout): grouping retains every file")
      for row in browser.displayRows.indices {
        if let index = browser.entryIndex(at: row) {
          let writer = layout == .details ? browser.tableView(browser.table, pasteboardWriterForRow: row) : browser.collectionView(browser.collection, pasteboardWriterForItemAt: IndexPath(item: row, section: 0))
          guard (writer as? NSURL)?.path == browser.entries[index].url.path else { throw NativeSmoke.Failure(description: "Grouped drag maps to wrong file") }
          if layout != .details, let attrs = browser.collectionLayout.layoutAttributesForItem(at: IndexPath(item: row, section: 0)) {
            let hit = browser.collectionLayout.layoutAttributesForDropTarget(at: NSPoint(x: attrs.frame.midX, y: attrs.frame.midY))
            guard hit?.indexPath?.item == row else { throw NativeSmoke.Failure(description: "Grouped drop maps to wrong file") }
          }
        } else { try check(browser.tableView(browser.table, pasteboardWriterForRow: row) == nil, "\(layout): headers cannot be dragged as files") }
      }
      let row = browser.displayRows.firstIndex { $0.group != nil }!
      let group = browser.groups[browser.groupIndex(at: row)!]
      browser.selectedPaths = Set(group.entries.map(\.id)); browser.toggleGroup(at: row)
      try check(browser.selectedPaths.isEmpty && browser.displayRows.compactMap(\.entry).count == 91 - group.entries.count, "\(layout): collapse clears hidden selection")
      browser.selectAllFiles()
      try check(browser.selectedEntries().count == 91 - group.entries.count, "\(layout): Select All excludes collapsed items")
      browser.toggleGroup(at: row)
    }
    browser.setView(.details); browser.setGrouping(.modified)
    let selected = browser.entries.last!.id
    browser.selectedPaths = [selected]; browser.updateMode(persist: false)
    browser.tableScroll.contentView.scroll(to: NSPoint(x: 0, y: 1200)); browser.tableScroll.reflectScrolledClipView(browser.tableScroll.contentView)
    let originalOffset = browser.tableScroll.contentView.bounds.origin
    browser.openTab(at: folder); try await until { !browser.loading && browser.directory.path == folder.path }
    try check(browser.groupMode == .none, "A different folder retains its independent grouping preference")
    browser.closeTab(); try await until { !browser.loading && browser.directory.path == root.path }
    try check(browser.groupMode == .modified && browser.selectedPaths == [selected] && abs(browser.tableScroll.contentView.bounds.origin.y - originalOffset.y) < 2, "Returning to a grouped tab restores its scroll and selection; mode=\(browser.groupMode), selection=\(browser.selectedPaths), before=\(originalOffset), after=\(browser.tableScroll.contentView.bounds.origin)")
    for fileView in [browser.table as NSView, browser.collection as NSView] {
      var renamed = false, opened = false
      let key = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
      if let table = fileView as? FileTableView { let rename = table.renameSelection, open = table.openSelection; table.renameSelection = { renamed = true }; table.openSelection = { opened = true }; table.keyDown(with: key); table.renameSelection = rename; table.openSelection = open }
      if let collection = fileView as? FileCollectionView { let rename = collection.renameSelection, open = collection.openSelection; collection.renameSelection = { renamed = true }; collection.openSelection = { opened = true }; collection.keyDown(with: key); collection.renameSelection = rename; collection.openSelection = open }
      try check(renamed && !opened, "Return retains the existing rename action")
    }
    let sources = Array(browser.entries.filter { !$0.isDirectory }.prefix(2)).map(\.url)
    let form = EDBatchRenameForm(sources: sources)
    form.frame = NSRect(x: 0, y: 0, width: 720, height: 700)
    try check(!form.isValid, "Batch editor disables empty rules")
    form.prefix.stringValue = "New-"; form.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: form.prefix)); form.layoutSubtreeIfNeeded()
    try check(form.isValid && descendants(form).compactMap { ($0 as? NSTextField)?.stringValue }.contains { $0.contains(" → New-") }, "Batch editor previews source and destination names")
    form.prefix.stringValue = "bad/"; form.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: form.prefix))
    try check(!form.isValid, "Invalid names are rejected before submission")
    form.prefix.stringValue = "New-"; form.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: form.prefix))
    browser.runAsyncOperation { FileActions.batchRename(sources, options: BatchRenameOptions(prefix: "New-")) }
    try await until { !browser.busy && !browser.loading }
    browser.undoFiles(); try await until { !browser.busy && !browser.loading }
    try check(sources.allSatisfy { fm.fileExists(atPath: $0.path) }, "One UI undo restores the batch")
    browser.redoFiles(); try await until { !browser.busy && !browser.loading }
    try check(sources.allSatisfy { fm.fileExists(atPath: $0.deletingLastPathComponent().appendingPathComponent("New-" + $0.lastPathComponent).path) }, "One UI redo reapplies the batch")
    defaults.set("custom", forKey: NativeStartLocation.preferenceKey); defaults.set(folder.path, forKey: NativeStartLocation.customPathKey)
    browser.newTab(); try await until { !browser.loading }
    try check(browser.directory.path == folder.path, "New tabs use the custom startup folder")
    try NativeSessions.save([NativeSavedWindow(locations: [root.absoluteString, "explorer://computer"], frame: "")], to: defaults)
    browser.restoreLocations(NativeSessions.load(defaults)[0].locations)
    try check(browser.tabs.contains { $0.directory.absoluteString == "explorer://computer" }, "Custom startup does not suppress saved-session locations")
    var attempted: [String] = []
    browser.reconnectServer = { attempted.append($0); return nil }
    browser.rememberServer("smb://server/share"); browser.rememberServer("smb://user:password@server/private")
    browser.reconnectSavedServers(); await Task.yield()
    try check(attempted.isEmpty && defaults.stringArray(forKey: "recentSMBServers") == ["smb://server/share"], "Reconnect defaults off and never stores credentials")
    defaults.set(true, forKey: "autoReconnectSMB"); browser.reconnectSavedServers(); try await until { attempted.count == 1 }
    try check(attempted == ["smb://server/share"], "Opt-in reconnect uses the validated successful endpoint")
    for size in [24, 10, 24, 13] {
      defaults.set(size, forKey: ExplorerTypography.preferenceKey)
      NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: defaults)
      try await until { ExplorerTypography.baseSize == CGFloat(size) && !browser.loading }
      browser.setView(.details); window.contentView?.layoutSubtreeIfNeeded()
      let cell = NameCell(frame: NSRect(x: 0, y: 0, width: 400, height: browser.table.rowHeight)); cell.configure(browser.entries.first ?? FileEntry(url: root, name: "Fixture", isDirectory: true, isSymbolicLink: false, isPackage: false, size: 0, modified: nil, isHidden: false)); cell.layoutSubtreeIfNeeded()
      try check(cell.nameLabel.font?.pointSize == CGFloat(size) && cell.bounds.contains(cell.nameLabel.frame), "\(size) pt: repeated changes preserve font size and fit the file row")
      browser.setView(.icons, size: 64); browser.collection.layoutSubtreeIfNeeded()
      let settings = EDSettingsBody(theme: "light", toolbar: [], shortcutRows: [], onTheme: { _ in }, onToolbar: nil, onShortcut: nil, shortcutDefaults: [:], folderDefaults: [:], onFolderDefaults: nil, onResetFolders: nil)
      settings.browser = browser; settings.openTab(0); settings.frame = NSRect(x: 0, y: 0, width: 850, height: 600); settings.layoutSubtreeIfNeeded()
      let controls = descendants(settings).compactMap { $0 as? NSButton }
      try check(controls.contains { $0.accessibilityLabel() == NL("默认打开") } && controls.contains { $0.accessibilityLabel() == NL("界面文字") } && !controls.contains { $0.title == NL("日常精简") }, "\(size) pt: settings retain startup and font controls without a profile mode")
      if size == 24, let bitmap = settings.bitmapImageRepForCachingDisplay(in: settings.bounds) { settings.cacheDisplay(in: settings.bounds, to: bitmap); try bitmap.representation(using: .png, properties: [:])?.write(to: output.appendingPathComponent("workflow-settings-24pt.png")) }
    }
    var reconnectCancelled = false
    var reconnectStarted = false
    browser.reconnectServer = { _ in
      reconnectStarted = true
      do { try await Task.sleep(nanoseconds: 5_000_000_000) }
      catch { reconnectCancelled = Task.isCancelled }
      return nil
    }
    await Task.yield(); browser.reconnectSavedServers(); try await until { reconnectStarted }; browser.stopObserving()
    try await until { reconnectCancelled }
    try check(reconnectCancelled, "Closing the owner cancels pending reconnect")
    try check(!window.isVisible, "All workflow checks leave the desktop foreground unchanged")
    return checks
  }
}
