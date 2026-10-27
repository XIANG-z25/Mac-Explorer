import AppKit
import ExplorerCore

final class NativeSystemSettingsView: SurfaceView {
  var preferredHeight: CGFloat { status.stringValue.isEmpty ? 28 : 58 }
  var onHeightChange: (() -> Void)?
  private let integration: NativeSystemIntegration
  private let viewer = EDButton(title: "", style: .checkbox)
  private let help: NativeHelpButton
  private let status = label("", size: 12)
  init(integration: NativeSystemIntegration) {
    self.integration = integration
    let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Mac Explorer"
    help = NativeHelpButton(text: NL("让支持系统文件查看器的软件将“在 Finder 中显示”等请求交给 {0}。关闭后恢复启用前的设置。", appName), accessibilityLabel: NL("系统文件查看器说明"))
    super.init(frame: .zero); color = .clear
    viewer.title = NL("使用 {0} 显示文件", appName)
    [viewer, help, status].forEach(addSubview)
    viewer.onPress = { [weak self] in self?.toggleViewer() }
    refreshViewer()
  }
  required init?(coder: NSCoder) { fatalError() }
  private func refreshViewer() {
    do { let value = try integration.fileViewer.perform("status"); viewer.checked = value.enabled; viewer.isEnabled = !value.enabled || value.canRestore; if !value.error.isEmpty { status.stringValue = NL(value.error) } }
    catch { viewer.isEnabled = false; status.stringValue = NL(error.localizedDescription) }
  }
  @objc private func toggleViewer() {
    let enabling = !viewer.checked
    let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Mac Explorer"
    let alert = NSAlert(); alert.messageText = enabling ? NL("使用 {0} 显示文件？", appName) : NL("恢复原文件查看器设置？")
    alert.addButton(withTitle: NL("确定")); alert.addButton(withTitle: NL("取消"))
    guard alert.runModal() == .alertFirstButtonReturn else { refreshViewer(); return }
    do { _ = try integration.fileViewer.perform(enabling ? "enable" : "restore"); status.stringValue = NL("已保存") }
    catch { status.stringValue = NL(error.localizedDescription) }
    refreshViewer(); onHeightChange?()
  }
  override func layout() {
    super.layout(); let width = bounds.width
    viewer.frame = NSRect(x: 0, y: 0, width: width - 32, height: 28); help.frame = NSRect(x: width - 24, y: 0, width: 24, height: 28)
    status.frame = NSRect(x: 0, y: 30, width: width, height: 28); status.maximumNumberOfLines = 2
  }
}

final class NativeWakeSettingsView: SurfaceView {
  let preferredHeight: CGFloat = 112
  private let integration: NativeSystemIntegration
  private let wake = EDShortcutRecorder(value: "")
  private let save = NSButton(title: NL("保存快捷键"), target: nil, action: nil)
  private let clear = NSButton(title: NL("清除"), target: nil, action: nil)
  private let status = label("", size: 12)
  init(integration: NativeSystemIntegration) {
    self.integration = integration; super.init(frame: .zero); color = .clear
    [wake, save, clear, status].forEach(addSubview)
    wake.value = integration.wakeShortcut
    wake.captureChanged = { [weak integration] in integration?.captureShortcut($0) }
    wake.onRecord = { [weak self] value in self?.wake.value = value; self?.refresh(); return true }
    wake.onError = { [weak self] in self?.status.stringValue = $0 }
    wake.setAccessibilityLabel(NL("唤醒快捷键")); save.target = self; save.action = #selector(saveWake); clear.target = self; clear.action = #selector(clearWake)
    refresh()
  }
  required init?(coder: NSCoder) { fatalError() }
  private func refresh() {
    status.stringValue = integration.wakeError
    save.isEnabled = wake.value != integration.wakeShortcut || !integration.wakeError.isEmpty
    clear.isEnabled = !wake.value.isEmpty
  }
  @objc private func saveWake() {
    do { try integration.setWakeShortcut(wake.value); wake.value = integration.wakeShortcut; refresh() }
    catch { status.stringValue = NL(error.localizedDescription) }
  }
  @objc private func clearWake() { wake.value = ""; refresh() }
  override func layout() {
    super.layout(); let width = bounds.width
    wake.frame = NSRect(x: 0, y: 0, width: max(100, width - 78), height: 30)
    clear.frame = NSRect(x: max(110, width - 66), y: 0, width: 66, height: 30)
    status.frame = NSRect(x: 0, y: 36, width: width, height: 24)
    save.frame = NSRect(x: 0, y: 70, width: 112, height: 30)
  }
}
