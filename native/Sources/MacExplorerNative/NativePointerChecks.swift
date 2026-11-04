import AppKit
import ExplorerCore

@MainActor
enum NativePointerChecks {
  static func run(output: URL) async throws -> [String] {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("native-pointer-" + UUID().uuidString)
    try fm.createDirectory(at: root.appendingPathComponent("Folder"), withIntermediateDirectories: true)
    let longName = "这是无需单击就能完整查看的文件名-" + String(repeating: "long-file-name-", count: 8) + ".mp4"
    for name in ["short.txt", "another.txt", longName] { try Data("pointer fixture".utf8).write(to: root.appendingPathComponent(name)) }
    let domain = "native-pointer." + UUID().uuidString, defaults = UserDefaults(suiteName: domain)!
    defaults.set(false, forKey: "versionControl")
    let originalKey = NSApp.keyWindow
    let browser = BrowserController(initial: root, defaults: defaults); browser.home = root
    let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 1100, height: 680), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentViewController = browser
    window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); browser.reload()
    defer { browser.table.cancelMarqueeSelection(); browser.stopObserving(); window.close(); originalKey?.makeKeyAndOrderFront(nil); defaults.removePersistentDomain(forName: domain); try? fm.removeItem(at: root) }
    var checks: [String] = []
    func check(_ value: Bool, _ message: String) throws { guard value else { throw NativeSmoke.Failure(description: message) }; checks.append(message) }
    let screen = NSRect(x: -1200, y: 100, width: 1200, height: 800)
    let tipSize = NSSize(width: 300, height: 64)
    let center = NSPoint(x: screen.midX, y: screen.midY)
    let centeredTip = NativeFileNameTip.frame(near: center, size: tipSize, on: screen)
    try check(centeredTip.minX == center.x + 14 && centeredTip.maxY == center.y, "Filename tip opens beside the pointer at its height")
    let corner = NSPoint(x: screen.maxX - 2, y: screen.minY + 2)
    let edgeTip = NativeFileNameTip.frame(near: corner, size: tipSize, on: screen)
    try check(screen.contains(edgeTip) && edgeTip.maxX < corner.x, "Filename tip flips left and stays on screen near the lower right edge")
    try await until("initial listing") { !browser.loading && browser.entries.count == 4 }
    browser.setView(.details); browser.setGrouping(.none); browser.view.layoutSubtreeIfNeeded()
    let table = browser.table
    guard let nameColumn = table.tableColumns.firstIndex(where: { $0.identifier.rawValue == "name" }),
          let cell = table.view(atColumn: nameColumn, row: 0, makeIfNecessary: true) as? NameCell else { throw NativeSmoke.Failure(description: "No name cell for pointer checks") }
    cell.layoutSubtreeIfNeeded()
    let blank = cell.convert(NSPoint(x: cell.bounds.maxX - 6, y: cell.bounds.midY), to: table)
    let icon = cell.convert(NSPoint(x: cell.icon.frame.midX, y: cell.icon.frame.midY), to: table)
    try check(table.row(at: blank) == 0 && table.canStartMarquee(at: blank), "Whitespace beside a filename starts marquee even when it is inside a file row")
    try check(!table.canStartMarquee(at: icon), "The file icon remains available for native file dragging")
    func mouse(_ type: NSEvent.EventType, at point: NSPoint) -> NSEvent {
      NSEvent.mouseEvent(with: type, location: table.convert(point, to: nil), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
    }
    table.mouseDown(with: mouse(.leftMouseDown, at: blank))
    let end = NSPoint(x: blank.x - 28, y: table.rect(ofRow: 3).midY)
    NSApp.sendEvent(mouse(.leftMouseDragged, at: end)); NSApp.sendEvent(mouse(.leftMouseUp, at: end))
    try check(table.selectedRowIndexes == IndexSet(0..<4) && browser.selectedPaths.count == 4, "Dragging from row whitespace selects multiple files through the actual table mouse entry point")

    browser.setGrouping(.kind)
    for (mode, size) in [(ExplorerLayoutMode.icons, CGFloat(48)), (.details, 48), (.icons, 64), (.icons, 48), (.icons, 32), (.list, 32), (.icons, 48)] {
      browser.setView(mode, size: size)
      if mode == .details { continue }
      let headers = Set(browser.displayRows.indices.filter { browser.groupIndex(at: $0) != nil })
      try check(!headers.isEmpty && browser.collectionLayout.groupHeaderRows == headers, "\(mode)/\(size): grouping survives a view switch without clicking")
      for row in headers {
        guard let header = browser.collectionLayout.layoutAttributesForItem(at: IndexPath(item: row, section: 0)) else { throw NativeSmoke.Failure(description: "Missing group frame after layout switch") }
        try check(header.frame.width >= browser.collectionScroll.contentSize.width - 17, "Group headings span the viewport immediately after a layout switch")
        if browser.entryIndex(at: row + 1) != nil, let next = browser.collectionLayout.layoutAttributesForItem(at: IndexPath(item: row + 1, section: 0)) {
          try check(next.frame.minY >= header.frame.maxY, "Files start below their group heading rather than piling into it")
        }
      }
    }

    browser.selectedPaths = []; browser.updateMode(persist: false)
    try await until("visible icon cells") { !browser.collection.visibleItems().isEmpty }
    // Allow real tracking events generated by the layout switches to drain before injecting hover.
    try await Task.sleep(nanoseconds: 250_000_000)
    guard let item = browser.collection.visibleItems().compactMap({ $0 as? IconItem }).first(where: { $0.nameLabel.stringValue == longName }),
          let surface = item.view as? ItemSurface else { throw NativeSmoke.Failure(description: "Long-name icon is not visible") }
    let before = browser.selectedPaths
    let enter = NSEvent.enterExitEvent(with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 2, trackingNumber: 0, userData: nil)!
    surface.mouseEntered(with: enter)
    do { try await until("hover filename tip") { surface.fileNameTip.panel?.isVisible == true } } catch { throw NativeSmoke.Failure(description: "Pointer checks timed out: hover filename tip [\(surface.fileNameTip.lastSkip)]") }
    guard let tip = surface.fileNameTip.panel else { throw NativeSmoke.Failure(description: "Missing filename tip") }
    try check(tip.contentView?.subviews.compactMap { ($0 as? NSTextField)?.stringValue }.contains(longName) == true, "Hover displays the complete filename including its extension")
    try check(browser.selectedPaths == before && !item.isSelected && tip.ignoresMouseEvents && !tip.canBecomeKey, "Hover tips require no click and leave selection and keyboard focus untouched")
    try NativeSmoke.capture(window, at: output.appendingPathComponent("grouped-medium-icons.png"))
    try NativeSmoke.capture(tip, at: output.appendingPathComponent("hover-full-name.png"))
    surface.mouseExited(with: enter)
    try check(surface.fileNameTip.panel == nil, "Moving off an icon dismisses its filename tip")
    surface.mouseEntered(with: enter)
    try await until("second hover") { surface.fileNameTip.panel?.isVisible == true }
    let clip = browser.collectionScroll.contentView
    var scrolled = clip.bounds.origin
    scrolled.y += 12
    clip.setBoundsOrigin(scrolled)
    try check(surface.fileNameTip.panel == nil, "Scrolling dismisses filename tips so they cannot cover unrelated files")
    try check(try String(contentsOf: root.appendingPathComponent(longName), encoding: .utf8) == "pointer fixture", "Pointer interaction checks preserve all fixture contents")
    return checks
  }

  private static func until(_ stage: String, _ ready: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(10)
    while !ready() { guard Date() < deadline else { throw NativeSmoke.Failure(description: "Pointer checks timed out: " + stage) }; try await Task.sleep(nanoseconds: 20_000_000) }
  }
}
