import AppKit
import ExplorerCore

@MainActor
enum NativeSMBTransferChecks {
  static func run(output: URL) async throws -> [String] {
    var checks: [String] = []
    func expect(_ condition: Bool, _ text: String) throws { guard condition else { throw NativeSmoke.Failure(description: text) }; checks.append(text) }
    let fields = NativeSMBLoginFields(account: "DOMAIN;fixture", previous: nil)
    try expect(fields.user.stringValue == "fixture" && fields.domain.stringValue == "DOMAIN", "SMB login pre-fills the mounted account without a password")
    try expect(fields.password.stringValue.isEmpty && fields.remember.state == .off && fields.encrypted.state == .on, "SMB password saving is opt-in and encryption starts required")
    try expect(fields.view.subviews.allSatisfy { fields.view.bounds.contains($0.frame) }, "Every SMB login field fits inside the accessory view")
    try expect(fields.password.accessibilityLabel() == NL("密码"), "Secure SMB password input has an accessible label")
    fields.user.stringValue = " "; try expect(fields.credential == nil, "Empty SMB users cannot submit credentials")
    fields.user.stringValue = "fixture"; fields.password.stringValue = "fixture-only-password"
    guard var credential = fields.credential else { throw NativeSmoke.Failure(description: "SMB login credential") }
    let store = NativeSMBAccounts(service: nil)
    try expect(store.load("fixture") == nil, "Injected SMB account store begins empty without keychain access")
    try expect(store.store(credential, key: "fixture") == 0 && store.load("fixture") == credential, "Session-only SMB credentials stay in the injected memory store")
    credential.remember = true
    try expect(store.store(credential, key: "fixture") == 0 && store.forgetAll() == 0 && store.load("fixture") == nil, "Forget clears injected SMB account state")
    let restored = NativeSMBLoginFields(account: "other", previous: credential)
    try expect(restored.user.stringValue == credential.user && restored.remember.state == .on, "SMB retry uses explicitly supplied credential fields")
    let panel = NativeTransferPanel(); defer { panel.close() }
    panel.control = FileTransferControl()
    let source = URL(fileURLWithPath: "/private/tmp/smb-ui-fixture")
    panel.update(FileTransferProgress(source: source, completedBytes: 1, totalBytes: 9, mode: .serverSide))
    try expect(panel.label.stringValue == NL("服务端复制：{0}", source.lastPathComponent) && panel.progress.doubleValue == 1, "SMB progress identifies acknowledged server-side copy")
    panel.update(FileTransferProgress(source: source, completedBytes: 1, totalBytes: 9))
    try expect(panel.label.stringValue == source.lastPathComponent, "Fallback resets the server-side label immediately")
    func wait(_ condition: () -> Bool) async throws {
      for _ in 0..<60 { if condition() { return }; try await Task.sleep(nanoseconds: 20_000_000) }
      throw NativeSmoke.Failure(description: "SMB login sheet did not complete")
    }
    func buttons(_ view: NSView) -> [NSButton] { (view as? NSButton).map { [$0] } ?? view.subviews.flatMap(buttons) }
    func press(_ title: String) throws {
      guard let sheet = panel.window.attachedSheet, let content = sheet.contentView,
        let button = buttons(content).first(where: { $0.title == title }) else { throw NativeSmoke.Failure(description: "Missing SMB login action: " + title) }
      button.performClick(nil)
    }
    func capture(_ window: NSWindow, _ name: String) throws {
      guard let view = window.contentView else { throw NativeSmoke.Failure(description: "Missing SMB fixture window") }
      window.appearance = NSAppearance(named: .aqua)
      view.layoutSubtreeIfNeeded(); view.displayIfNeeded()
      guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw NativeSmoke.Failure(description: "Missing SMB fixture bitmap") }
      window.effectiveAppearance.performAsCurrentDrawingAppearance { view.cacheDisplay(in: view.bounds, to: bitmap) }
      let image = NSImage(size: view.bounds.size), content = NSImage(size: view.bounds.size)
      content.addRepresentation(bitmap); image.lockFocus()
      NSColor(calibratedWhite: 0.95, alpha: 1).setFill(); view.bounds.fill()
      content.draw(in: view.bounds, from: .zero, operation: .sourceOver, fraction: 1)
      image.unlockFocus()
      guard let tiff = image.tiffRepresentation, let flattened = NSBitmapImageRep(data: tiff),
        let data = flattened.representation(using: .png, properties: [:]) else { throw NativeSmoke.Failure(description: "Missing SMB fixture PNG") }
      try data.write(to: output.appendingPathComponent(name))
    }
    var finished = false, submitted: NativeSMBCredential?
    panel.login(server: "fixture.invalid:445", account: "DOMAIN;fixture", previous: credential, error: nil) { value in submitted = value; finished = true }
    try await wait { panel.window.attachedSheet != nil }
    guard let sheet = panel.window.attachedSheet else { throw NativeSmoke.Failure(description: "Missing SMB sheet") }
    try capture(sheet, "native-smb-login-fixture.png")
    try press(NL("使用普通传输")); try await wait { finished && panel.window.attachedSheet == nil }
    try expect(submitted == nil && !panel.control!.isCancelled, "Standard-transfer login action dismisses the sheet without cancelling the operation")
    finished = false
    panel.login(server: "fixture.invalid:445", account: "DOMAIN;fixture", previous: credential, error: nil) { value in submitted = value; finished = true }
    try await wait { panel.window.attachedSheet != nil }
    try press(NL("登录")); try await wait { finished && panel.window.attachedSheet == nil }
    try expect(submitted == credential && !panel.control!.isCancelled, "Login sheet returns secure fixture credentials to the worker")
    panel.update(FileTransferProgress(source: source, completedBytes: 4, totalBytes: 9, mode: .serverSide))
    try capture(panel.window, "native-smb-progress-fixture.png")
    finished = false
    panel.login(server: "fixture.invalid:445", account: "DOMAIN;fixture", previous: nil, error: nil) { value in submitted = value; finished = true }
    try await wait { panel.window.attachedSheet != nil }
    try press(NL("取消")); try await wait { finished && panel.window.attachedSheet == nil }
    try expect(submitted == nil && panel.control!.isCancelled, "Cancel in the SMB login sheet cancels the existing transfer control")
    return checks
  }
}
