import AppKit
import CryptoKit
import ExplorerCore

@MainActor
final class NativeUpdateCoordinator {
  static var isPersonalBuild: Bool { Bundle.main.object(forInfoDictionaryKey: "ExplorerPersonalBuild") as? Bool == true }
  private static var instances: [String: NativeUpdateCoordinator] = [:]
  static func current() -> NativeUpdateCoordinator {
    let app = Bundle.main.bundleURL.resolvingSymlinksInPath(), key = app.path
    if let value = instances[key] { return value }
    let value = NativeUpdateCoordinator(app: app); instances[key] = value; return value
  }
  let updates: NativeUpdates
  private var task: Task<Void, Never>?
  private var automaticTimer: Timer?
  private(set) var installationError = ""
  var isBusy: Bool { task != nil }
  private init(app: URL) {
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    let identity = Bundle.main.bundleIdentifier ?? "native-development"
    let digest = SHA256.hash(data: Data(app.path.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Mac Explorer Native/updates/\(identity)-\(digest)")
    updates = NativeUpdates(version: version, app: app, cache: cache)
  }
  func startAutomaticChecks() {
    guard !Self.isPersonalBuild, automaticTimer == nil else { return }
    checkAutomatically(launching: true)
    automaticTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
      Task { @MainActor [weak self] in self?.checkAutomatically(launching: false) }
    }
    automaticTimer?.tolerance = 10
  }
  private func checkAutomatically(launching: Bool) {
    let defaults = UserDefaults.standard
    guard !isBusy, NativeUpdateFrequency.saved(in: defaults).isDue(
      lastCheck: defaults.object(forKey: NativeUpdateFrequency.lastCheckKey) as? Date,
      now: Date(), launching: launching
    ) else { return }
    perform("checking")
  }
  func perform(_ status: String) {
    guard !Self.isPersonalBuild, task == nil else { return }; installationError = ""
    // The update belongs to the application, so closing Settings does not cancel it.
    task = Task {
      defer { task = nil }
      if status == "ready" {
        do {
          let installer = try await updates.installer()
          guard let delegate = NSApp.delegate as? ApplicationDelegate else { throw NativeUpdateValidation.failure("无法准备更新安装。") }
          try delegate.installUpdateAndTerminate { try installer.launch(pid: ProcessInfo.processInfo.processIdentifier) }
        }
        catch { installationError = NL(error.localizedDescription) }
      } else if status == "available" { await updates.download() }
      else {
        let state = await updates.state
        guard state.status != "ready", state.status != "installing" else { return }
        // Count attempts too, so an offline app does not retry every minute.
        UserDefaults.standard.set(Date(), forKey: NativeUpdateFrequency.lastCheckKey)
        await updates.check()
      }
    }
  }
}

@MainActor
final class NativeUpdateView: SurfaceView {
  let preferredHeight: CGFloat = 110
  private let coordinator = NativeUpdateCoordinator.current()
  private let status = label("", size: 12)
  private let progress = NSProgressIndicator()
  private let download = EDButton(title: NL("下载更新"), style: .primary)
  private let transferred = label("", size: 11)
  private let action = EDButton(title: NL("检查更新"), style: .secondary)
  private var current = NativeUpdateState(currentVersion: "0.1.0")
  private var poll: Timer?
  init() {
    super.init(frame: .zero)
    [status, progress, action, download, transferred].forEach(addSubview)
    action.target = self; action.action = #selector(performAction)
    download.target = self; download.action = #selector(downloadUpdate); transferred.alignment = .center
    status.alignment = .center
    progress.style = .bar; progress.isIndeterminate = true; progress.isHidden = true
    status.maximumNumberOfLines = 2
    if NativeUpdateCoordinator.isPersonalBuild { render(current); return }
    poll = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
      Task { @MainActor [weak self] in guard let self else { return }; self.render(await self.coordinator.updates.state) }
    }
    Task { @MainActor [weak self] in guard let self else { return }; self.render(await self.coordinator.updates.state) }
    render(current)
  }
  required init?(coder: NSCoder) { fatalError() }
  deinit { poll?.invalidate() }
  @objc private func performAction() {
    if current.status == "ready" {
      let alert = NSAlert(); alert.messageText = NL("退出并安装更新？"); alert.addButton(withTitle: NL("安装")); alert.addButton(withTitle: NL("取消"))
      guard alert.runModal() == .alertFirstButtonReturn else { return }
    }
    coordinator.perform(current.status == "ready" ? "ready" : "checking"); render(current)
  }
  @objc private func downloadUpdate() { coordinator.perform("available"); render(current) }
  func render(_ state: NativeUpdateState) {
    if NativeUpdateCoordinator.isPersonalBuild {
      status.stringValue = NL("本地自用版本，通过本地构建更新。")
      action.isHidden = true; download.isHidden = true; progress.isHidden = true; transferred.isHidden = true; needsLayout = true
      return
    }
    current = state
    let busy = coordinator.isBusy || ["checking", "downloading", "verifying", "installing"].contains(current.status)
    action.isEnabled = !busy
    action.style = current.status == "ready" ? .primary : .secondary
    action.title = current.status == "ready" ? NL("重启并安装") : NL("检查更新")
    download.isHidden = current.latestVersion == nil || !["available", "error"].contains(current.status)
    download.isEnabled = !busy
    transferred.isHidden = !["downloading", "verifying"].contains(current.status)
    transferred.stringValue = NL("{0} / {1} MiB", String(format: "%.1f", Double(current.downloaded) / 1_048_576), String(format: "%.1f", Double(current.total) / 1_048_576))
    needsLayout = true
    let labels = ["idle": NL("尚未检查更新"), "checking": NL("正在检查更新…"), "current": NL("已是最新版本"), "available": NL("发现新版本：{0}", current.latestVersion ?? ""), "downloading": NL("正在下载更新…"), "verifying": NL("正在校验更新…"), "ready": NL("更新已就绪"), "installing": NL("正在安装更新…")]
    status.stringValue = !coordinator.installationError.isEmpty ? coordinator.installationError : current.error.isEmpty ? labels[current.status] ?? "" : current.error
    progress.isHidden = !busy; progress.isIndeterminate = current.status != "downloading"; progress.maxValue = Double(max(1, current.total)); progress.doubleValue = Double(current.downloaded)
    if busy, progress.isIndeterminate { progress.startAnimation(nil) } else { progress.stopAnimation(nil) }
  }
  override func layout() {
    super.layout()
    status.frame = NSRect(x: 0, y: 0, width: bounds.width, height: 34)
    progress.frame = NSRect(x: 0, y: 34, width: bounds.width, height: 10)
    transferred.frame = NSRect(x: 0, y: 46, width: bounds.width, height: 18)
    let buttonsWidth: CGFloat = download.isHidden ? 146 : 274
    let left = max(0, (bounds.width - buttonsWidth) / 2)
    download.frame = NSRect(x: left + 154, y: 68, width: 120, height: 30)
    action.frame = NSRect(x: left, y: 68, width: 146, height: 30)
  }
}
