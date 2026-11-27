import AppKit
import ExplorerCore

/// A separate native browser keeps object-based MTP access out of filesystem operations.
@MainActor
final class NativeAndroidWindow: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
  private static var shared: NativeAndroidWindow?
  private let client: AndroidMTP
  private let devices = NSPopUpButton()
  private let storage = NSPopUpButton()
  private let refresh = NSButton(title: NL("刷新设备"), target: nil, action: nil)
  private let up = NSButton(title: NL("上一级"), target: nil, action: nil)
  private let save = NSButton(title: NL("保存到 Mac…"), target: nil, action: nil)
  private let cancel = NSButton(title: NL("取消"), target: nil, action: nil)
  private let location = label("", size: 12)
  private let status = label("", size: 12)
  private let table = NSTableView()
  private let byteFormatter = ByteCountFormatter()
  private let scroll = ExplorerScrollView()
  private var phoneList: [AndroidDevice] = []
  private var storageList: [AndroidStorage] = []
  private var items: [AndroidItem] = []
  private var path: [(UInt32, String)] = []
  private var task: Task<Void, Never>?
  private var worker: Task<Void, Error>?
  private var generation: UInt64 = 0
  private var cache = AndroidDirectoryCache()
  private var busy = false
  private var transferring = false

  static func present() {
    if let shared { shared.showWindow(nil); shared.refreshDevices(); return }
    let controller = NativeAndroidWindow()
    shared = controller
    controller.showWindow(nil)
    controller.refreshDevices()
  }

  private init() {
    let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/android-reader")
    client = AndroidMTP(helper: helper)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 560),
      styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
    super.init(window: window)
    window.title = NL("安卓手机（USB）"); window.minSize = NSSize(width: 660, height: 400)
    window.isReleasedWhenClosed = false; window.delegate = self
    let root = ExplorerRootView(); window.contentView = root
    for view in [devices, storage, refresh, up, save, cancel, location, status, scroll] { root.addSubview(view) }
    root.onLayout = { [weak self, weak root] in
      guard let self, let root else { return }
      let w = root.bounds.width, h = root.bounds.height
      self.devices.frame = NSRect(x: 16, y: 12, width: 230, height: 28)
      self.storage.frame = NSRect(x: 254, y: 12, width: max(100, w - 390), height: 28)
      self.refresh.frame = NSRect(x: w - 120, y: 12, width: 104, height: 28)
      self.up.frame = NSRect(x: 16, y: 48, width: 85, height: 28)
      self.location.frame = NSRect(x: 112, y: 54, width: w - 128, height: 22)
      self.scroll.frame = NSRect(x: 16, y: 88, width: w - 32, height: max(100, h - 148))
      self.status.frame = NSRect(x: 16, y: h - 42, width: max(100, w - 260), height: 24)
      self.save.frame = NSRect(x: w - 228, y: h - 46, width: 132, height: 30)
      self.cancel.frame = NSRect(x: w - 88, y: h - 46, width: 72, height: 30)
    }
    for (id, title, width) in [("name", NL("名称"), 480.0), ("size", NL("大小"), 140.0)] {
      let column = NSTableColumn(identifier: .init(id)); column.title = title; column.width = width
      table.addTableColumn(column)
    }
    table.delegate = self; table.dataSource = self; table.allowsMultipleSelection = true
    table.rowHeight = 28; table.target = self; table.doubleAction = #selector(openItem)
    byteFormatter.countStyle = .file
    scroll.documentView = table; scroll.hasVerticalScroller = true
    devices.target = self; devices.action = #selector(changeDevice)
    storage.target = self; storage.action = #selector(changeStorage)
    for (button, selector) in [(refresh, #selector(refreshDevices)), (up, #selector(goUp)),
      (save, #selector(saveSelected)), (cancel, #selector(cancelTransfer))] { button.target = self; button.action = selector }
    status.stringValue = NL("请解锁手机并选择 USB 文件传输。")
    updateControls(); window.center()
  }
  required init?(coder: NSCoder) { fatalError() }

  private func updateControls() {
    devices.isEnabled = !transferring; storage.isEnabled = !transferring
    refresh.isEnabled = !transferring; up.isEnabled = !transferring && !path.isEmpty
    save.isEnabled = !busy && !table.selectedRowIndexes.isEmpty && !storageList.isEmpty
    cancel.isEnabled = busy
  }

  private func cancelLoading() {
    generation &+= 1
    worker?.cancel(); task?.cancel(); task = nil
    busy = false
  }

  private func run(transfer: Bool = false, _ operation: @escaping @Sendable () throws -> Void,
    completed: @escaping (Error?) -> Void) {
    guard !transferring else { return }
    cancelLoading()
    let previous = worker, request = generation
    busy = true; transferring = transfer; updateControls()
    // Await cancellation/reaping before starting another USB process. Rapid navigation
    // must not race an older request for the phone's exclusive interface.
    let work = Task.detached(priority: transfer ? .utility : .userInitiated) {
      _ = await previous?.result
      try Task.checkCancellation()
      try operation()
    }
    worker = work
    let wait = Task { @MainActor [weak self] in
      let result = await work.result
      guard let self, self.generation == request else { return }
      self.worker = nil; self.task = nil; self.busy = false; self.transferring = false
      switch result {
      case .success: completed(nil)
      case .failure(let error): completed(error)
      }
      self.updateControls()
    }
    task = wait
  }

  @objc private func refreshDevices() {
    guard !transferring else { return }
    cache.removeAll()
    let client = client
    status.stringValue = NL("正在查找手机…")
    let result = AndroidResultBox<[AndroidDevice]>()
    run({ result.value = try client.devices() }) { [weak self] error in
      guard let self else { return }
      self.phoneList = result.value ?? []; self.devices.removeAllItems()
      self.devices.addItems(withTitles: self.phoneList.map(\.name))
      self.items = []; self.storageList = []; self.storage.removeAllItems(); self.path = []; self.table.reloadData()
      if let error { self.status.stringValue = error.localizedDescription }
      else if self.phoneList.isEmpty { self.status.stringValue = NL("未发现手机。请解锁并选择 USB 文件传输。") }
      else { self.changeDevice() }
    }
  }
  @objc private func changeDevice() {
    guard !transferring else { return }
    guard phoneList.indices.contains(devices.indexOfSelectedItem) else { return }
    let device = phoneList[devices.indexOfSelectedItem], client = client
    cache.removeAll()
    storageList = []; storage.removeAllItems(); location.stringValue = ""
    let result = AndroidResultBox<[AndroidStorage]>()
    path = []; items = []; table.reloadData(); status.stringValue = NL("正在读取手机存储…")
    run({ result.value = try client.storages(device) }) { [weak self] error in
      guard let self else { return }
      self.storageList = result.value ?? []; self.storage.removeAllItems()
      self.storage.addItems(withTitles: self.storageList.map(\.name))
      if let error { self.status.stringValue = error.localizedDescription }
      else if self.storageList.isEmpty { self.status.stringValue = NL("手机未提供可访问的存储。") }
      else { self.changeStorage() }
    }
  }
  @objc private func changeStorage() { guard !transferring else { return }; path = []; loadFolder() }
  private func loadFolder(revealItem: UInt32? = nil) {
    guard phoneList.indices.contains(devices.indexOfSelectedItem),
      storageList.indices.contains(storage.indexOfSelectedItem) else { return }
    let device = phoneList[devices.indexOfSelectedItem], storageID = storageList[storage.indexOfSelectedItem].id
    let parent = path.last?.0 ?? UInt32.max, client = client
    let key = AndroidDirectoryCache.Key(device: device.id, storage: storageID, parent: parent)
    let result = AndroidResultBox<[AndroidItem]>()
    cancelLoading()
    location.stringValue = "/" + path.map { $0.1 }.joined(separator: "/")
    let snapshot = cache.snapshot(for: key)
    show(snapshot?.items ?? [], revealItem: revealItem, resetScroll: true)
    if let snapshot, !snapshot.needsRefresh {
      status.stringValue = NL("{0} 个项目", items.count); updateControls(); return
    }
    status.stringValue = snapshot == nil ? NL("正在读取…") : NL("正在刷新…")
    run({ result.value = try client.list(device, storage: storageID, parent: parent) }) { [weak self] error in
      guard let self else { return }
      if let refreshed = result.value, error == nil {
        self.cache.insert(refreshed, for: key)
        let selected = Set(self.table.selectedRowIndexes.compactMap { self.items.indices.contains($0) ? self.items[$0].id : nil })
        self.show(refreshed, revealItem: revealItem, preserving: selected)
      } else if error != nil {
        // A failed read may indicate unplug/replug; never keep old object IDs.
        self.cache.removeAll(); self.show([])
      }
      self.status.stringValue = error?.localizedDescription ?? NL("{0} 个项目", self.items.count)
      self.status.toolTip = self.status.stringValue
    }
  }
  private func show(_ updated: [AndroidItem], revealItem: UInt32? = nil, preserving selected: Set<UInt32> = [], resetScroll: Bool = false) {
    // Comparing value arrays avoids a full table reload during an unchanged refresh.
    if items != updated {
      items = updated; table.reloadData(); table.deselectAll(nil)
      let indexes = IndexSet(items.indices.filter { selected.contains(items[$0].id) })
      table.selectRowIndexes(indexes, byExtendingSelection: false)
    }
    if let revealItem, let row = items.firstIndex(where: { $0.id == revealItem }) {
      table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
      table.scrollRowToVisible(row)
    } else if resetScroll { scroll.contentView.scroll(to: .zero); scroll.reflectScrolledClipView(scroll.contentView) }
  }
  @objc private func openItem() {
    let row = table.clickedRow
    guard !transferring, items.indices.contains(row), items[row].directory else { return }
    path.append((items[row].id, items[row].name)); loadFolder()
  }
  @objc private func goUp() { guard !transferring, let previous = path.popLast() else { return }; loadFolder(revealItem: previous.0) }
  @objc private func cancelTransfer() { worker?.cancel(); status.stringValue = NL("正在取消…") }
  @objc private func saveSelected() {
    guard !busy, let window, phoneList.indices.contains(devices.indexOfSelectedItem),
      storageList.indices.contains(storage.indexOfSelectedItem) else { return }
    let selected = table.selectedRowIndexes.compactMap { items.indices.contains($0) ? items[$0] : nil }
    guard !selected.isEmpty else { return }
    let device = phoneList[devices.indexOfSelectedItem], storageID = storageList[storage.indexOfSelectedItem].id
    let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
    panel.beginSheetModal(for: window) { [weak self] response in
      guard let self, response == .OK, let destination = panel.url else { return }
      let client = self.client
      self.status.stringValue = NL("正在保存到 Mac…")
      self.run(transfer: true, {
        for item in selected { _ = try client.save(item, device: device, storage: storageID, to: destination) }
      }) { [weak self] error in
        self?.status.stringValue = error is CancellationError ? NL("已取消") : error?.localizedDescription ?? NL("已保存到 Mac")
        self?.status.toolTip = self?.status.stringValue
      }
    }
  }
  func numberOfRows(in tableView: NSTableView) -> Int { items.count }
  func tableViewSelectionDidChange(_ notification: Notification) { updateControls() }
  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    guard items.indices.contains(row) else { return nil }
    let item = items[row]
    let identifier = tableColumn?.identifier ?? NSUserInterfaceItemIdentifier("name")
    let cell: NSTableCellView
    if let reusable = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView { cell = reusable }
    else {
      cell = NSTableCellView(); cell.identifier = identifier
      let text = label(""); text.lineBreakMode = .byTruncatingMiddle
      text.frame = NSRect(x: 4, y: 4, width: max(0, (tableColumn?.width ?? 200) - 8), height: 20)
      text.autoresizingMask = [.width]; cell.textField = text; cell.addSubview(text)
    }
    cell.textField?.stringValue = identifier.rawValue == "size" ? (item.directory ? "" : byteFormatter.string(fromByteCount: Int64(clamping: item.size))) : (item.directory ? "📁 " : "") + item.name
    cell.toolTip = item.name
    return cell
  }
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    if transferring { worker?.cancel() }
    else { cancelLoading(); cache.removeAll(); items = []; table.reloadData(); updateControls() }
    sender.orderOut(nil); return false
  }
}

/// The worker writes before task completion; the main actor reads after awaiting it.
private final class AndroidResultBox<Value: Sendable>: @unchecked Sendable {
  var value: Value?
}
