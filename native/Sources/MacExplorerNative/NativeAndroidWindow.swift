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
  private let scroll = ExplorerScrollView()
  private var phoneList: [AndroidDevice] = []
  private var storageList: [AndroidStorage] = []
  private var items: [AndroidItem] = []
  private var path: [(UInt32, String)] = []
  private var task: Task<Void, Never>?
  private var worker: Task<Void, Never>?
  private var busy = false

  static func present() {
    if let shared { shared.showWindow(nil); return }
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
    devices.isEnabled = !busy; storage.isEnabled = !busy
    refresh.isEnabled = !busy; up.isEnabled = !busy && !path.isEmpty
    save.isEnabled = !busy && !table.selectedRowIndexes.isEmpty && !storageList.isEmpty
    cancel.isEnabled = busy
  }

  private func run(_ operation: @escaping @Sendable () throws -> Void, completed: @escaping (Error?) -> Void) {
    guard !busy else { return }
    busy = true; updateControls()
    let work = Task.detached(priority: .utility) { try operation() }
    let wait = Task { @MainActor [weak self] in
      let result = await work.result
      guard let self else { return }
      self.worker = nil; self.task = nil; self.busy = false
      switch result {
      case .success: completed(nil)
      case .failure(let error): completed(error)
      }
      self.updateControls()
    }
    // The adapter gives cancellation ownership to the command's detached task.
    worker = Task { await withTaskCancellationHandler { _ = await work.result } onCancel: { work.cancel() } }
    task = wait
  }

  @objc private func refreshDevices() {
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
    guard phoneList.indices.contains(devices.indexOfSelectedItem) else { return }
    let device = phoneList[devices.indexOfSelectedItem], client = client
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
  @objc private func changeStorage() { path = []; loadFolder() }
  private func loadFolder() {
    guard phoneList.indices.contains(devices.indexOfSelectedItem),
      storageList.indices.contains(storage.indexOfSelectedItem) else { return }
    let device = phoneList[devices.indexOfSelectedItem], storageID = storageList[storage.indexOfSelectedItem].id
    let parent = path.last?.0 ?? UInt32.max, client = client
    let result = AndroidResultBox<[AndroidItem]>()
    items = []; table.reloadData(); status.stringValue = NL("正在读取…")
    run({ result.value = try client.list(device, storage: storageID, parent: parent) }) { [weak self] error in
      guard let self else { return }
      self.items = result.value ?? []; self.table.reloadData()
      self.location.stringValue = "/" + self.path.map { $0.1 }.joined(separator: "/")
      self.status.stringValue = error?.localizedDescription ?? NL("{0} 个项目", self.items.count)
      self.status.toolTip = self.status.stringValue
    }
  }
  @objc private func openItem() {
    let row = table.clickedRow
    guard !busy, items.indices.contains(row), items[row].directory else { return }
    path.append((items[row].id, items[row].name)); loadFolder()
  }
  @objc private func goUp() { guard !busy, !path.isEmpty else { return }; path.removeLast(); loadFolder() }
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
      self.run({
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
    let text = label(tableColumn?.identifier.rawValue == "size" ? (item.directory ? "" : ByteCountFormatter.string(fromByteCount: Int64(clamping: item.size), countStyle: .file)) : (item.directory ? "📁 " : "") + item.name)
    text.toolTip = item.name
    return text
  }
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    worker?.cancel(); sender.orderOut(nil); return false
  }
}

/// The worker writes before task completion; the main actor reads after awaiting it.
private final class AndroidResultBox<Value: Sendable>: @unchecked Sendable {
  var value: Value?
}
