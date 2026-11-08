import AppKit
import ExplorerCore

@MainActor
final class NativeTransferWindow: NSObject, NSWindowDelegate {
  static let shared = NativeTransferWindow()
  let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 108), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
  private let scroll = NSScrollView()
  private let document = TransferRows()
  private var rows: [NativeTransferPanel] = []
  private var waiting: [NativeTransferPanel] = []
  private weak var showingAlert: NativeTransferPanel?

  private override init() {
    super.init()
    window.title = NL("传输文件")
    window.isReleasedWhenClosed = false
    window.hidesOnDeactivate = false
    window.delegate = self
    scroll.documentView = document
    scroll.autohidesScrollers = true
    window.contentView = scroll
    window.center()
  }

  func add(_ row: NativeTransferPanel) {
    rows.append(row)
    document.addSubview(row.content)
    layout()
  }

  func remove(_ row: NativeTransferPanel) {
    rows.removeAll { $0 === row }
    row.content.removeFromSuperview()
    if rows.isEmpty { window.orderOut(nil) }
    layout()
  }

  private func layout() {
    let rowHeight: CGFloat = 108
    let height = rowHeight * CGFloat(max(1, rows.count))
    let origin = window.frame.origin
    let top = window.frame.maxY
    window.setContentSize(NSSize(width: 460, height: min(height, 432)))
    window.setFrameOrigin(NSPoint(x: origin.x, y: top - window.frame.height))
    scroll.hasVerticalScroller = height > 432
    document.frame.size = NSSize(width: 440, height: height)
    for (index, row) in rows.enumerated() {
      row.content.frame = NSRect(x: 0, y: CGFloat(index) * rowHeight, width: 440, height: rowHeight)
    }
  }

  func show() {
    if !rows.isEmpty { window.makeKeyAndOrderFront(nil) }
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    window.orderOut(nil)
    return false
  }

  func enqueueAlert(for row: NativeTransferPanel) {
    waiting.append(row)
    showNextAlert()
  }

  func dismissAlert(for row: NativeTransferPanel, alert: NSAlert, response: NSApplication.ModalResponse) {
    waiting.removeAll { $0 === row }
    guard showingAlert === row else { return }
    if alert.window.sheetParent != nil { window.endSheet(alert.window, returnCode: response) }
    showingAlert = nil
    DispatchQueue.main.async { [weak self] in self?.showNextAlert() }
  }

  private func showNextAlert() {
    guard showingAlert == nil, window.attachedSheet == nil, !waiting.isEmpty else { return }
    let row = waiting.removeFirst()
    guard let (alert, _) = row.pendingAlert else { return }
    showingAlert = row
    show()
    alert.beginSheetModal(for: window) { [weak row, weak alert] response in
      guard let alert else { return }
      row?.resolve(alert, response: response)
    }
  }
}

private final class TransferRows: NSView {
  override var isFlipped: Bool { true }
}

/// The progress and decision state of one operation in the shared window.
@MainActor
final class NativeTransferPanel: NSObject {
  var window: NSPanel { NativeTransferWindow.shared.window }
  let content = NSView()
  let label = NSTextField(labelWithString: NL("正在准备…"))
  let progress = NSProgressIndicator()
  let statistics = NSTextField(labelWithString: "")
  let cancel = NSButton(title: NL("取消"), target: nil, action: nil)
  private var finished = false
  private var lastUpdate = Date.distantPast
  private var lastMode: FileTransferMode?
  private var phase: FileTransferPhase = .preparing
  private var latest: FileTransferProgress?
  private var speedTimer: Timer?
  let showsWindows: Bool
  private(set) var pendingAlert: (NSAlert, (NSApplication.ModalResponse) -> Void)?
  var control: FileTransferControl?
  init(showsWindows: Bool = true) {
    self.showsWindows = showsWindows
    super.init()
    label.frame = NSRect(x: 20, y: 76, width: 400, height: 22); label.lineBreakMode = .byTruncatingMiddle
    progress.frame = NSRect(x: 20, y: 54, width: 400, height: 16); progress.style = .bar; progress.isIndeterminate = true; progress.startAnimation(nil)
    cancel.frame = NSRect(x: 330, y: 13, width: 90, height: 30); cancel.bezelStyle = .rounded; cancel.target = self; cancel.action = #selector(cancelTransfer)
    statistics.frame = NSRect(x: 20, y: 17, width: 300, height: 22)
    statistics.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular); statistics.textColor = .secondaryLabelColor
    statistics.setAccessibilityLabel(NL("传输速度"))
    speedTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.renderStatistics() }
    }
    for view in [label, progress, statistics, cancel] { content.addSubview(view) }
    guard showsWindows else { return }
    NativeTransferWindow.shared.add(self)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
      guard let self, self.showsWindows, !self.finished else { return }; self.window.orderFront(nil)
    }
  }
  @objc private func cancelTransfer() {
    control?.cancel(); cancel.isEnabled = false; label.stringValue = NL("正在取消…")
    if let (alert, _) = pendingAlert { resolve(alert, response: .abort) }
  }
  func update(_ value: FileTransferProgress) {
    guard !finished, control?.isCancelled != true else { return }
    let now = Date()
    guard value.mode != lastMode || now.timeIntervalSince(lastUpdate) > 0.1 || value.completedBytes >= value.totalBytes else { return }; lastUpdate = now; lastMode = value.mode
    latest = value
    if phase == .preparing { setPhase(.copying) }
    if phase != .copying { renderStatistics(); return }
    label.stringValue = value.mode == .serverSide ? NL("服务端复制：{0}", value.source.lastPathComponent) : value.source.lastPathComponent; label.toolTip = value.source.path
    progress.stopAnimation(nil); progress.isIndeterminate = false; progress.maxValue = Double(max(1, value.totalBytes)); progress.doubleValue = Double(value.completedBytes)
    renderStatistics()
  }
  func setPhase(_ value: FileTransferPhase) {
    guard !finished, control?.isCancelled != true else { return }
    phase = value
    switch value {
    case .preparing: label.stringValue = NL("正在读取文件清单…")
    case .connecting: label.stringValue = NL("正在连接共享…")
    case .copying: break
    case .properties: label.stringValue = NL("正在保留属性…")
    case .verifying: label.stringValue = NL("正在验证文件…")
    case .publishing: label.stringValue = NL("正在提交…")
    case .removingSource: label.stringValue = NL("正在清理来源…")
    case .finishing: label.stringValue = NL("正在收尾…")
    }
    if value != .copying { progress.isIndeterminate = true; progress.startAnimation(nil) }
    renderStatistics()
  }
  private func renderStatistics() {
    guard phase == .copying, let value = latest else { statistics.stringValue = ""; return }
    var speed = "—"
    if ProcessInfo.processInfo.systemUptime - value.observedAt <= 2, let rate = value.bytesPerSecond, rate.isFinite, rate > 0 {
      speed = ExplorerFormat.size(Int64(min(rate, Double(Int64.max / 2)))) + "/s"
    }
    statistics.stringValue = ExplorerFormat.size(value.completedBytes) + " / " + ExplorerFormat.size(value.totalBytes) + " · " + NL("速度：{0}", speed)
  }
  func close() {
    finished = true; speedTimer?.invalidate(); speedTimer = nil
    if let (alert, _) = pendingAlert { resolve(alert, response: .abort) }
    if showsWindows { NativeTransferWindow.shared.remove(self) }
    control = nil
  }
  func present(_ alert: NSAlert, completion: @escaping (NSApplication.ModalResponse) -> Void) {
    guard !finished, control?.isCancelled != true, pendingAlert == nil else { completion(.abort); return }
    // Keep the sheet and its reply together so closing/cancelling cannot strand the worker.
    pendingAlert = (alert, completion)
    guard showsWindows else { return }
    NativeTransferWindow.shared.enqueueAlert(for: self)
  }
  func resolve(_ alert: NSAlert, response: NSApplication.ModalResponse) {
    guard let (active, completion) = pendingAlert, active === alert else { return }
    pendingAlert = nil
    if showsWindows { NativeTransferWindow.shared.dismissAlert(for: self, alert: alert, response: response) }
    alert.window.orderOut(nil)
    completion(response)
  }
  func problem(_ value: FileTransferProblem, completion: @escaping (FileTransferDecision) -> Void) {
    guard !finished, control?.isCancelled != true else { completion(.cancel); return }
    let alert = NSAlert(); alert.messageText = value.propertyLoss ? NL("无法保留全部文件属性") : NL("操作中断")
    alert.informativeText = value.source.lastPathComponent + "\n" + value.message
    var decisions: [FileTransferDecision] = [.retry]
    alert.addButton(withTitle: NL("重试"))
    if value.propertyLoss {
      alert.informativeText += "\n" + (value.moving ? NL("继续移动将移除来源，部分属性可能丢失。") : NL("继续复制可能丢失部分属性。"))
      alert.addButton(withTitle: value.moving ? NL("仍然移动") : NL("仍然复制")); decisions.append(.continueWithoutProperties)
    } else if value.collision {
      alert.addButton(withTitle: NL("保留两者")); decisions.append(.keepBoth)
    }
    alert.addButton(withTitle: NL("跳过")); decisions.append(.skip)
    alert.addButton(withTitle: NL("取消")); decisions.append(.cancel)
    alert.buttons.last?.keyEquivalent = "\u{1b}"
    present(alert) { response in
      let index = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
      completion(decisions.indices.contains(index) ? decisions[index] : .cancel)
    }
  }
}

/// Semaphore only bridges the background file worker to AppKit's asynchronous sheet.
/// The main thread never waits for the worker.
private final class TransferDecisionReply: @unchecked Sendable {
  let semaphore = DispatchSemaphore(value: 0)
  var decision: FileTransferDecision = .cancel
  var credential: NativeSMBCredential?
}

extension BrowserController {
  func runTransferOperation(recordUndo: Bool = true, panel: NativeTransferPanel? = nil, completion: ((FileActionResult) -> Void)? = nil, _ operation: @escaping @Sendable (FileTransferControl) -> FileActionResult) {
    guard !busy else { return }
    let panel = panel ?? NativeTransferPanel()
    let smoke = ProcessInfo.processInfo.arguments.contains("--smoke-test")
    let diagnostics = smoke || !panel.showsWindows ? nil : TransferDiagnostics()
    let logDirectory = Bundle.main.bundleIdentifier == "local.macexplorer.native-validation"
      ? Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("transfer-logs")
      : FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent(Bundle.main.bundleIdentifier ?? "local.macexplorer").appendingPathComponent("transfer-logs")
    let provider: NativeSMBDataCopier? = smoke || defaults.object(forKey: "serverSideTransfer") as? Bool == false ? nil : NativeSMBDataCopier(login: { [weak panel] server, account, previous, error in
      let reply = TransferDecisionReply()
      DispatchQueue.main.async {
        guard let panel else { reply.semaphore.signal(); return }
        panel.login(server: server, account: account, previous: previous, error: error) { value in reply.credential = value; reply.semaphore.signal() }
      }
      reply.semaphore.wait(); return reply.credential
    }, saveFailure: { [weak panel] code in
      let reply = TransferDecisionReply()
      DispatchQueue.main.async {
        guard let panel else { reply.semaphore.signal(); return }
        let alert = NSAlert(); alert.messageText = NL("无法保存登录信息"); alert.informativeText = NL("钥匙串错误码：{0}", String(code))
        panel.present(alert) { _ in reply.semaphore.signal() }
      }
      reply.semaphore.wait()
    })
    let control = FileTransferControl(onProblem: { [weak panel] value in
      // Existing regression fixtures choose Skip; dialog controls have separate UI checks.
      if smoke { return .skip }
      let reply = TransferDecisionReply()
      DispatchQueue.main.async {
        guard let panel else { reply.semaphore.signal(); return }
        panel.problem(value) { choice in reply.decision = choice; reply.semaphore.signal() }
      }
      reply.semaphore.wait(); return reply.decision
    }, onProgress: { [weak panel] value in
      diagnostics?.progress(value); DispatchQueue.main.async { panel?.update(value) }
    }, serverSideCopy: provider, onPhase: { [weak panel] phase in
      DispatchQueue.main.async { panel?.setPhase(phase) }
    }, onTiming: { diagnostics?.record($0) })
    panel.control = control
    runAsyncOperation(recordUndo: recordUndo, completion: completion) {
      let result = await Task.detached {
        let result = operation(control)
        _ = try? diagnostics?.finish(result, directory: logDirectory)
        return result
      }.value
      panel.close()
      return result
    }
  }
}

@MainActor
enum NativeTransferPanelChecks {
  static func run() async throws -> [String] {
    let panel = NativeTransferPanel(), control = FileTransferControl()
    panel.control = control
    let second = NativeTransferPanel(), secondControl = FileTransferControl()
    second.control = secondControl
    defer { panel.close(); second.close() }
    var checks: [String] = []
    func expect(_ condition: Bool, _ message: String) throws {
      guard condition else { throw NativeSmoke.Failure(description: message) }; checks.append(message)
    }
    func buttons(_ view: NSView) -> [NSButton] { (view as? NSButton).map { [$0] } ?? view.subviews.flatMap(buttons) }
    let source = URL(fileURLWithPath: "/private/tmp/transfer-ui-fixture")
    second.update(FileTransferProgress(source: source.appendingPathExtension("second"), completedBytes: 70, totalBytes: 100))
    panel.update(FileTransferProgress(source: source, completedBytes: 25, totalBytes: 100))
    try expect(panel.content.window === second.content.window && panel.content.frame.maxY <= second.content.frame.minY &&
      second.progress.doubleValue == 70, "Two simultaneous transfers use separate rows in one window")
    try expect(panel.label.stringValue == source.lastPathComponent && panel.progress.doubleValue == 25, "Transfer progress displays actual bytes without full-file verification reads")
    panel.update(FileTransferProgress(source: source, completedBytes: 100, totalBytes: 100, bytesPerSecond: 1024))
    try expect(panel.statistics.stringValue.contains("/s"), "Local copy displays a measured byte rate")
    panel.update(FileTransferProgress(source: source, completedBytes: 100, totalBytes: 100, mode: .serverSide, bytesPerSecond: 2048))
    try expect(panel.label.stringValue == NL("服务端复制：{0}", source.lastPathComponent) && panel.statistics.stringValue.contains("/s"), "Server-side copy displays its acknowledged logical byte rate")
    panel.setPhase(.properties)
    try expect(panel.progress.isIndeterminate && panel.statistics.stringValue.isEmpty && panel.label.stringValue == NL("正在保留属性…"), "Metadata processing never leaves a misleading 100-percent data bar or speed")
    panel.setPhase(.verifying)
    try expect(panel.label.stringValue == NL("正在验证文件…"), "Verification remains visible after copying finishes")
    panel.setPhase(.copying)
    panel.update(FileTransferProgress(source: source, completedBytes: 100, totalBytes: 100, bytesPerSecond: 1024, observedAt: ProcessInfo.processInfo.systemUptime - 3))
    try expect(!panel.statistics.stringValue.contains("/s"), "Stale progress does not display a stale transfer speed")
    var answer: FileTransferDecision?
    panel.problem(FileTransferProblem(source: source, destination: source.appendingPathExtension("copy"), message: "fixture", propertyLoss: true, moving: true)) { answer = $0 }
    try await NativeSmoke.until { panel.window.attachedSheet != nil }
    let firstSheet = panel.window.attachedSheet
    var secondResponse: NSApplication.ModalResponse?
    second.present(NSAlert()) { secondResponse = $0 }
    second.cancel.performClick(nil)
    try expect(secondControl.isCancelled && !control.isCancelled && secondResponse == .abort &&
      panel.window.attachedSheet === firstSheet, "Cancel affects only its row and does not dismiss another task's alert")
    let choices = panel.window.attachedSheet?.contentView.map(buttons) ?? []
    try expect([NL("重试"), NL("仍然移动"), NL("跳过"), NL("取消")].allSatisfy { title in choices.contains { $0.title == title } }, "Property-loss dialog exposes Retry, explicit Move anyway, Skip and Cancel")
    choices.first { $0.title == NL("跳过") }?.performClick(nil)
    try await NativeSmoke.until { answer != nil }
    try expect(answer == .skip, "Skipping a property-loss sheet returns a skip decision")
    panel.cancel.performClick(nil)
    try expect(control.isCancelled && !panel.cancel.isEnabled, "Transfer Cancel signals the background worker")
    return checks
  }
}
