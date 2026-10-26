import AppKit
import Security
import Darwin
import ExplorerCore
import SMBTransport

struct NativeSMBCredential: Codable, Equatable, Sendable {
  var user: String
  var domain: String
  var password: String
  var encrypted: Bool
  var remember: Bool
  var isValid: Bool {
    !user.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && user.utf8.count <= 256 && domain.utf8.count <= 256 && password.utf8.count <= 16_384
      && ![user, domain, password].contains { $0.contains("\0") }
  }
}

/// Only this dedicated service is ever queried/deleted. Validation uses its own Bundle ID;
/// smoke/automated checks inject an in-memory store and never touch the user's keychain.
final class NativeSMBAccounts: @unchecked Sendable {
  static let shared = NativeSMBAccounts(service: (Bundle.main.bundleIdentifier ?? "local.macexplorer") + ".server-side-transfer")
  private let service: String?
  private var memory: [String: NativeSMBCredential] = [:]
  private let lock = NSLock()
  init(service: String?) { self.service = service }
  func load(_ key: String) -> NativeSMBCredential? {
    lock.lock(); defer { lock.unlock() }
    if let value = memory[key] { return value }
    guard let service else { return nil }
    var item: CFTypeRef?
    let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
      kSecAttrAccount as String: key, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
    guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data,
      let value = try? JSONDecoder().decode(NativeSMBCredential.self, from: data) else { return nil }
    memory[key] = value; return value
  }
  /// Persist only after successful authentication. No password reaches UserDefaults or diagnostics.
  func store(_ value: NativeSMBCredential, key: String) -> OSStatus {
    lock.lock(); defer { lock.unlock() }; memory[key] = value
    guard let service else { return errSecSuccess }
    let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key]
    if !value.remember { let status = SecItemDelete(query as CFDictionary); return status == errSecItemNotFound ? errSecSuccess : status }
    guard let data = try? JSONEncoder().encode(value) else { return errSecParam }
    let attributes: [String: Any] = [kSecValueData as String: data]
    let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    if status != errSecItemNotFound { return status }
    return SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
  }
  func forgetAll() -> OSStatus {
    lock.lock(); defer { lock.unlock() }; memory.removeAll()
    guard let service else { return errSecSuccess }
    let status = SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary)
    return status == errSecItemNotFound ? errSecSuccess : status
  }
}

private final class NativeSMBCallbacks {
  let control: FileTransferControl
  let source: URL
  init(_ control: FileTransferControl, _ source: URL) { self.control = control; self.source = source }
}

/// Contexts and credentials live for one UI operation; each context is used by one serial worker.
/// The macOS mounts remain the file namespace and metadata provider. Unknown bindings fall back.
final class NativeSMBDataCopier: ServerSideCopyProvider, @unchecked Sendable {
  typealias Login = @Sendable (String, String, NativeSMBCredential?, Int32?) -> NativeSMBCredential?
  private let login: Login
  private let accounts: NativeSMBAccounts
  private let saveFailure: @Sendable (OSStatus) -> Void
  private var sessions: [String: OpaquePointer] = [:]
  private var disabled = Set<String>()
  private let lock = NSLock()
  init(accounts: NativeSMBAccounts = .shared, login: @escaping Login, saveFailure: @escaping @Sendable (OSStatus) -> Void = { _ in }) {
    self.accounts = accounts; self.login = login; self.saveFailure = saveFailure
  }
  deinit { for session in sessions.values { mx_smb_destroy(session) } }
  func isCandidate(source: URL, destination: URL) -> Bool {
    guard let from = SMBMountedLocation.read(source), let to = SMBMountedLocation.read(destination.deletingLastPathComponent()) else { return false }
    return from.canTransfer(to: to)
  }
  private func address(_ fd: Int32) -> (String, UInt16)? {
    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST)); var port: UInt16 = 0
    guard mx_smb_mount_address(fd, &host, host.count, &port) == 0 else { return nil }
    return (String(cString: host), port)
  }
  func copy(sourceDescriptor: Int32, destinationDescriptor: Int32, source: URL, destination: URL, control: FileTransferControl) throws -> Bool {
    lock.lock(); defer { lock.unlock() }
    if control.isCancelled { throw CancellationError() }
    guard let from = SMBMountedLocation.read(descriptor: sourceDescriptor, file: source),
      let to = SMBMountedLocation.read(descriptor: destinationDescriptor, file: destination), from.canTransfer(to: to),
      let a = address(sourceDescriptor), let b = address(destinationDescriptor), a.0 == b.0, a.1 == b.1 else { return false }
    let accountKey = from.authority + "\n" + from.account.lowercased()
    if disabled.contains(accountKey) { return false }
    let endpoint = (a.0.contains(":") ? "[\(a.0)]" : a.0) + ":\(a.1)"
    let key = accountKey + "\n" + endpoint + "\n" + from.share + "\n" + to.share
    var session = sessions[key]
    if session == nil {
      var credential = FileTransferControl.measure(control, "smb.credentials", phase: .connecting) { accounts.load(accountKey) }
      if credential?.isValid != true { credential = nil }
      var failure: Int32?
      while session == nil {
        if control.isCancelled { throw CancellationError() }
        if credential == nil || failure != nil { credential = login(from.authority, from.account, credential, failure) }
        guard let value = credential, value.isValid else {
          if control.isCancelled { throw CancellationError() }; disabled.insert(accountKey); return false
        }
        var code: Int32 = 0
        session = FileTransferControl.measure(control, "smb.connect", phase: .connecting) {
          mx_smb_connect(endpoint, from.share, to.share, value.user, value.domain, value.password, value.encrypted ? 1 : 0, &code)
        }
        if session == nil { failure = code; continue }
        let saved = accounts.store(value, key: accountKey); if saved != errSecSuccess { saveFailure(saved) }
      }
      sessions[key] = session
    }
    guard let session else { return false }
    if control.isCancelled { throw CancellationError() }
    let callbacks = NativeSMBCallbacks(control, source)
    let context = Unmanaged.passUnretained(callbacks).toOpaque()
    var code: Int32 = 0
    let protocolStart = ProcessInfo.processInfo.systemUptime
    let result = withExtendedLifetime(callbacks) {
      mx_smb_copy(session, from.root.path, to.root.path, from.remotePath, to.remotePath, sourceDescriptor, destinationDescriptor, { pointer in
        guard let pointer else { return 1 }; return Unmanaged<NativeSMBCallbacks>.fromOpaque(pointer).takeUnretainedValue().control.isCancelled ? 1 : 0
      }, { pointer, completed, total in
        guard let pointer, completed <= UInt64(Int64.max), total <= UInt64(Int64.max) else { return }
        let state = Unmanaged<NativeSMBCallbacks>.fromOpaque(pointer).takeUnretainedValue()
        state.control.reportServerSideProgress(state.source, completed: Int64(completed), total: Int64(total))
      }, context, &code)
    }
    var metrics = mx_smb_metrics()
    mx_smb_copy_metrics(session, &metrics)
    control.recordTiming("smb.protocol", seconds: ProcessInfo.processInfo.systemUptime - protocolStart, succeeded: result == MX_SMB_COPIED, metrics: [
      "bindingSeconds": metrics.binding_seconds, "copyChunkSeconds": metrics.copychunk_seconds,
      "closeSeconds": metrics.closing_seconds, "requests": Double(metrics.request_count),
      "acknowledgedBytes": Double(metrics.acknowledged_bytes), "result": Double(result), "error": Double(code)
    ])
    switch Int(result) {
    case MX_SMB_COPIED: return true
    case MX_SMB_CANCELLED: throw CancellationError()
    case MX_SMB_UNCERTAIN:
      sessions.removeValue(forKey: key); mx_smb_destroy(session); throw ServerSideCopyError.uncertain(code)
    case MX_SMB_FAILED: throw ServerSideCopyError.failed(code)
    default:
      // Do not repeatedly probe a server that cannot safely offload this operation.
      sessions.removeValue(forKey: key); mx_smb_destroy(session); disabled.insert(accountKey); return false
    }
  }
}

@MainActor
final class NativeSMBLoginFields: NSObject, NSTextFieldDelegate {
  var onChange: (() -> Void)?
  let view = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 188))
  let user = NSTextField(), domain = NSTextField(), password = NSSecureTextField()
  let remember = NSButton(checkboxWithTitle: NL("保存到钥匙串"), target: nil, action: nil)
  let encrypted = NSButton(checkboxWithTitle: NL("要求 SMB3 加密"), target: nil, action: nil)
  init(account: String, previous: NativeSMBCredential?) {
    super.init()
    for field in [user, domain, password] { field.delegate = self }
    let parts = account.split(maxSplits: 1, whereSeparator: { $0 == ";" || $0 == "\\" }).map(String.init)
    user.stringValue = previous?.user ?? parts.last ?? ""
    domain.stringValue = previous?.domain ?? (parts.count == 2 ? parts[0] : "")
    password.stringValue = previous?.password ?? ""
    remember.state = previous?.remember == true ? .on : .off
    encrypted.state = previous?.encrypted == false ? .off : .on
    for (index, pair) in [(NL("用户名"), user), (NL("域"), domain), (NL("密码"), password)].enumerated() {
      let label = NSTextField(labelWithString: pair.0); label.frame = NSRect(x: 0, y: 150 - index * 36, width: 80, height: 24)
      pair.1.frame = NSRect(x: 88, y: 150 - index * 36, width: 252, height: 24)
      pair.1.setAccessibilityLabel(pair.0); view.addSubview(label); view.addSubview(pair.1)
    }
    remember.frame = NSRect(x: 88, y: 40, width: 252, height: 22)
    encrypted.frame = NSRect(x: 88, y: 12, width: 252, height: 22)
    view.addSubview(remember); view.addSubview(encrypted)
  }
  func controlTextDidChange(_ notification: Notification) { onChange?() }
  var credential: NativeSMBCredential? {
    let name = user.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    let value = NativeSMBCredential(user: name, domain: domain.stringValue, password: password.stringValue, encrypted: encrypted.state == .on, remember: remember.state == .on)
    return value.isValid ? value : nil
  }
}

@MainActor
extension NativeTransferPanel {
  func login(server: String, account: String, previous: NativeSMBCredential?, error: Int32?, completion: @escaping (NativeSMBCredential?) -> Void) {
    guard control?.isCancelled != true else { completion(nil); return }
    let alert = NSAlert(); alert.messageText = NL("服务端传输登录")
    alert.informativeText = server + (error.map { "\n" + NL("无法连接共享（错误码 {0}）。", String($0)) } ?? "")
    let fields = NativeSMBLoginFields(account: account, previous: previous); alert.accessoryView = fields.view
    alert.addButton(withTitle: NL("登录")); alert.addButton(withTitle: NL("使用普通传输")); alert.addButton(withTitle: NL("取消"))
    alert.buttons.last?.keyEquivalent = "\u{1b}"
    alert.buttons.first?.isEnabled = fields.credential != nil
    fields.onChange = { [weak alert, weak fields] in alert?.buttons.first?.isEnabled = fields?.credential != nil }
    present(alert) { [weak self] result in
      if result == .alertFirstButtonReturn {
        if let credential = fields.credential { completion(credential) }
        else { self?.login(server: server, account: account, previous: nil, error: EINVAL, completion: completion) }
      } else { if result == .alertThirdButtonReturn { self?.control?.cancel() }; completion(nil) }
    }
    alert.window.makeFirstResponder(fields.user.stringValue.isEmpty ? fields.user : fields.password)
  }
}
