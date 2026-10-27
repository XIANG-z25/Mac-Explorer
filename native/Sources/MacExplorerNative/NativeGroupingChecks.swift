import AppKit
import ExplorerCore

@MainActor enum NativeGroupingChecks {
  static func run(largeRoot: URL, output: URL) async throws -> [String] {
    var checks: [String] = []
    func expect(_ value: Bool, _ message: String) throws { guard value else { throw NativeSmoke.Failure(description: message) }; checks.append(message) }
    let fm = FileManager.default, root = fm.temporaryDirectory.appendingPathComponent("native-grouping-" + UUID().uuidString)
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    let suite = "local.zx.grouping-check.\(UUID().uuidString)", defaults = UserDefaults(suiteName: suite)!
    ExplorerDailyProfile.configure(defaults, validation: false)
    let now = Date(), calendar = Calendar.current
    for (name, age, folder) in [("工作资料", -100, true), ("下载归档", -50, true), ("项目说明.txt", 0, false), ("设计参考.txt", 0, false), ("会议记录.txt", -1, false), ("上周报告.txt", -10, false), ("历史备份.txt", -100, false)] {
      let url = root.appendingPathComponent(name)
      if folder { try fm.createDirectory(at: url, withIntermediateDirectories: false) } else { try Data(name.utf8).write(to: url) }
      try fm.setAttributes([.modificationDate: calendar.date(byAdding: .day, value: age, to: now)!], ofItemAtPath: url.path)
    }
    let browser = BrowserController(initial: root, defaults: defaults)
    let pasteboard = NSPasteboard(name: .init(suite)); browser.filePasteboard = pasteboard
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 780), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentViewController = browser; window.center(); window.makeKeyAndOrderFront(nil)
    defer { browser.stopObserving(); window.orderOut(nil); window.contentViewController = nil; pasteboard.releaseGlobally(); defaults.removePersistentDomain(forName: suite); try? fm.removeItem(at: root) }
    try await NativeSmoke.until { !browser.loading && browser.entries.count == 7 }
    browser.setGrouping(.modified); window.contentView?.layoutSubtreeIfNeeded()
    try expect(browser.groups.first?.id == "folders", "Folder section remains above date groups")
    try expect(browser.groups.flatMap(\.entries).count == 7, "Grouping preserves actual file counts")
    try expect(browser.table.numberOfRows == 7 + browser.groups.count, "Table displays real group header rows")
    try expect(browser.status.stringValue.contains("7"), "Status excludes artificial headers")
    browser.table.selectRowIndexes(IndexSet(integersIn: 0..<browser.table.numberOfRows), byExtendingSelection: false)
    try expect(browser.table.selectedRowIndexes.allSatisfy { browser.entryIndex(at: $0) != nil }, "Group headers cannot enter table selection")
    browser.table.deselectAll(nil)
    if let firstFile = browser.displayRows.firstIndex(where: { $0.entry != nil }),
       let down = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 125) {
      window.makeFirstResponder(browser.table); browser.table.keyDown(with: down)
      try expect(browser.table.selectedRow == firstFile, "Down skips the leading group header")
    }
    let firstEntryRow = browser.displayRows.firstIndex { $0.entry != nil }
    try expect(nextFileRow(key: 126, previous: -1, count: browser.displayRows.count, accepts: { browser.entryIndex(at: $0) != nil }) == firstEntryRow, "Up with no selection skips the leading header")
    if let header = browser.table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? ExplorerGroupCell {
      let before = browser.displayRows.count
      try expect(header.accessibilityPerformPress(), "Group headers expose an accessibility press action")
      try expect(browser.displayRows.count == before - 2, "Accessible group activation collapses the folder group")
      browser.toggleGroup(at: 0)
      try expect(browser.displayRows.count == before, "Reopening a group restores its exact item count")
    }
    if let header = browser.table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? ExplorerGroupCell {
      try expect(window.makeFirstResponder(header), "Group headers accept keyboard focus")
      guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .control, timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, characters: "l", charactersIgnoringModifiers: "l", isARepeat: false, keyCode: 37) else { throw NativeSmoke.Failure(description: "Cannot create address shortcut event") }
      NSApp.postEvent(event, atStart: true)
      if let queued = NSApp.nextEvent(matching: .keyDown, until: Date().addingTimeInterval(0.05), inMode: .default, dequeue: true) { NSApp.sendEvent(queued) }
      try await NativeSmoke.until { browser.addressBar.editing }
      try expect(browser.addressBar.editing, "Ctrl+L works while a group header has focus")
      window.makeFirstResponder(browser.table)
    }
    for (mode, size) in [(ExplorerLayoutMode.details, 64), (.icons, 128), (.icons, 64), (.icons, 48), (.icons, 32), (.list, 32), (.tiles, 64), (.content, 64)] {
      browser.setView(mode, size: CGFloat(size)); window.contentView?.layoutSubtreeIfNeeded()
      guard let row = browser.displayRows.firstIndex(where: { $0.entry.map { !browser.entries[$0].isDirectory } == true }), let index = browser.entryIndex(at: row) else { throw NativeSmoke.Failure(description: "Grouped file row missing") }
      let expected = browser.entries[index].url
      if mode == .details {
        browser.table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        let writer = browser.tableView(browser.table, pasteboardWriterForRow: row) as? NSURL
        try expect(writer?.path == expected.path, "Grouped details dragging maps to the real file")
      } else {
        browser.collection.selectionIndexPaths = [IndexPath(item: row, section: 0)]
        browser.collectionView(browser.collection, didSelectItemsAt: [IndexPath(item: row, section: 0)])
        let writer = browser.collectionView(browser.collection, pasteboardWriterForItemAt: IndexPath(item: row, section: 0)) as? NSURL
        try expect(writer?.path == expected.path, "Grouped \(mode.rawValue)/\(size) dragging maps to the real file")
        let attrs = browser.collectionLayout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))
        try expect((attrs?.frame.width ?? 0) > browser.collection.bounds.width * 0.8, "Grouped \(mode.rawValue)/\(size) header spans the viewport")
      }
      browser.executeAction("copy")
      let copied = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
      try expect(copied == [expected], "Grouped \(mode.rawValue)/\(size) copy preserves file identity")
    }
    browser.groupingMenu().first { $0.title == NL("折叠所有组") }?.action?()
    try expect(browser.displayRows.count == browser.groups.count && browser.selectedPaths.isEmpty, "Collapse All clears hidden selections and retains headers")
    browser.groupingMenu().first { $0.title == NL("展开所有组") }?.action?()
    try expect(browser.displayRows.count == 7 + browser.groups.count, "Expand All restores every file exactly once")
    let remembered = BrowserController(initial: root, defaults: defaults)
    try expect(remembered.groupMode == .modified, "A new controller restores per-folder grouping")
    browser.setView(.details)
    if let row = browser.displayRows.firstIndex(where: { $0.entry.map { !browser.entries[$0].isDirectory } == true }), let index = browser.entryIndex(at: row) {
      browser.table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
      browser.executeAction("rename")
      let field = (browser.table.view(atColumn: 0, row: row, makeIfNecessary: true) as? NameCell)?.nameLabel
      try expect(field?.isEditable == true && field?.identifier?.rawValue == browser.entries[index].id, "F2 edits the actual grouped file rather than its header")
      field?.stringValue = browser.entries[index].name
      if let action = field?.action { _ = field?.sendAction(action, to: field?.target) }
    }
    NSApp.appearance = NSAppearance(named: .aqua)
    browser.table.deselectAll(nil); try NativeSmoke.capture(window, at: output.appendingPathComponent("grouped-details.png"))
    browser.setView(.icons, size: 64); try NativeSmoke.capture(window, at: output.appendingPathComponent("grouped-icons.png"))
    NSApp.appearance = NSAppearance(named: .darkAqua); try NativeSmoke.capture(window, at: output.appendingPathComponent("grouped-dark.png")); NSApp.appearance = NSAppearance(named: .aqua)
    browser.setGrouping(.none); browser.setView(.details)
    try expect(browser.table.numberOfRows == 7, "None removes every artificial header")
    let restored = BrowserController(initial: root, defaults: defaults)
    try expect(restored.groupMode == .none, "Explicit None persists across reopen")
    browser.navigate(to: largeRoot)
    try await NativeSmoke.until { !browser.loading && browser.entries.count == 10003 }
    let start = Date(); browser.setGrouping(.modified); browser.setView(.icons, size: 64); window.contentView?.layoutSubtreeIfNeeded()
    let attributes = browser.collectionLayout.layoutAttributesForElements(in: browser.collection.visibleRect)
    try expect(attributes.count < 150, "10,003 grouped entries compute only viewport layout attributes")
    try expect(browser.collection.visibleItems().count < 150, "10,003 grouped entries instantiate only visible items")
    checks.append("10,003-entry grouped layout updated in \(Int(Date().timeIntervalSince(start) * 1000)) ms on this machine")
    try expect(ExplorerShortcuts.bindings("open", overrides: [:]).contains("Enter") && ExplorerShortcuts.bindings("rename", overrides: [:]) == ["F2"], "Windows Enter opens and F2 renames")
    try expect(ExplorerShortcuts.bindings("trash", overrides: [:]).contains("Delete"), "Windows Delete uses the system Trash action")
    browser.setView(.details); browser.setGrouping(.none)
    return checks
  }
}
