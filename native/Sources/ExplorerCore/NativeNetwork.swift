import Foundation
import AppKit
import NetFS
import Darwin

public enum NativeVolumeKind: String, Sendable { case local, network, unknown }
public enum NativeVolumeCapacityState: String, Sendable { case known, partial, unknown, invalid, unavailable }

public struct NativeVolume: Equatable, Sendable {
  public let url: URL
  public let name: String
  public let total: Int64?
  public let free: Int64?
  public let kind: NativeVolumeKind
  public let canEject: Bool
  public let capacityState: NativeVolumeCapacityState
  public var isNetwork: Bool { kind == .network }
  public var path: String { url.path }
  /// Nil means no trustworthy proportion: missing/error, contradictory values, or a zero total.
  public var usedFraction: Double? {
    guard capacityState == .known, let total, total > 0, let free else { return nil }
    return min(1, max(0, 1 - Double(free) / Double(total)))
  }
  public init(url: URL, name: String, total: Int64?, free: Int64?, kind: NativeVolumeKind, canEject: Bool, metadataUnavailable: Bool = false) {
    self.url = url; self.name = name; self.kind = kind; self.canEject = url.path != "/" && canEject
    self.total = metadataUnavailable ? nil : total.flatMap { $0 >= 0 ? $0 : nil }
    self.free = metadataUnavailable ? nil : free.flatMap { $0 >= 0 ? $0 : nil }
    if metadataUnavailable { capacityState = .unavailable }
    else if total.map({ $0 < 0 }) == true || free.map({ $0 < 0 }) == true || (total != nil && free != nil && free! > total!) { capacityState = .invalid }
    else if total != nil && free != nil { capacityState = .known }
    else if total != nil || free != nil { capacityState = .partial }
    else { capacityState = .unknown }
  }
}

struct NativeVolumeAttributes {
  var name: String? = nil
  var total: Int64? = nil
  var free: Int64? = nil
  var local: Bool? = nil
  var ejectable = false
}

/// Per-read dependencies keep errors and missing fields testable without contacting or ejecting a server.
struct NativeVolumeReader {
  var mountedURLs: () -> [URL]?
  var mountKinds: () -> [String: NativeVolumeKind]
  var attributes: (URL) throws -> NativeVolumeAttributes
  static var live: Self {
    let keys: Set<URLResourceKey> = [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeIsLocalKey, .volumeIsEjectableKey, .volumeIsRemovableKey]
    return Self(mountedURLs: { NativeVolumes.visibleURLs() }, mountKinds: {
      NativeVolumes.mountFlags().mapValues { $0 & UInt32(MNT_LOCAL) == 0 ? .network : .local }
    }, attributes: { url in
      let values = try url.resourceValues(forKeys: keys)
      return NativeVolumeAttributes(name: values.volumeName, total: values.volumeTotalCapacity.map(Int64.init), free: values.volumeAvailableCapacity.map(Int64.init), local: values.volumeIsLocal,
        ejectable: values.volumeIsEjectable == true || values.volumeIsRemovable == true)
    })
  }
}

public enum NativeVolumes {
  static func mountFlags() -> [String: UInt32] {
    // A private buffer lets background volume refreshes run concurrently.
    var buffer: UnsafeMutablePointer<statfs>?
    let count = getmntinfo_r_np(&buffer, MNT_NOWAIT)
    guard count > 0, let buffer else { return [:] }
    defer { Darwin.free(buffer) }
    var result: [String: UInt32] = [:]
    for index in 0..<Int(count) {
      var entry = buffer[index]
      let path = withUnsafeBytes(of: &entry.f_mntonname) { bytes in
        String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
      }
      result[path] = entry.f_flags
    }
    return result
  }

  private static var mountyDirectory: String {
    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".mounty", isDirectory: true).path
  }
  private static func isMountyPath(_ path: String) -> Bool {
    (path as NSString).deletingLastPathComponent == mountyDirectory
  }
  public static func sidebarMounts() -> [String: UInt32] {
    mountFlags().filter { $0.key.hasPrefix("/Volumes/") || isMountyPath($0.key) }
  }

  public static func visibleURLs() -> [URL]? {
    visibleURLs(foundation: FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]), flags: mountFlags())
  }
  static func visibleURLs(foundation: [URL]?, flags: [String: UInt32]) -> [URL]? {
    let missing = flags.keys.sorted().filter { path in
      guard let value = flags[path] else { return false }
      // Mounty uses a hidden directory. Include its actual local mount points.
      if isMountyPath(path) { return value & UInt32(MNT_LOCAL) != 0 }
      guard path == "/" || path.hasPrefix("/Volumes/") else { return false }
      return value & UInt32(MNT_DONTBROWSE) == 0
    }
    guard foundation != nil || !missing.isEmpty else { return nil }
    var seen = Set<String>()
    return ((foundation ?? []) + missing.map { URL(fileURLWithPath: $0, isDirectory: true) })
      .filter { seen.insert($0.path).inserted }
  }
  public static func isReadOnly(_ url: URL) -> Bool {
    guard url.isFileURL else { return false }
    let path = url.standardizedFileURL.path
    // The APFS system root is read-only, but firmlinked paths such as /Users are writable.
    let mount = sidebarMounts().filter { root, _ in path == root || path.hasPrefix(root + "/") }
      .max { $0.key.count < $1.key.count }
    return mount.map { $0.value & UInt32(MNT_RDONLY) != 0 } ?? false
  }
  public static func list() throws -> [NativeVolume] { try list(using: .live) }
  public static func canEject(_ url: URL) -> Bool {
    guard url.isFileURL, let flags = sidebarMounts()[url.path] else { return false }
    if isMountyPath(url.path) { return flags & UInt32(MNT_LOCAL) != 0 }
    let values = try? url.resourceValues(forKeys: [.volumeIsEjectableKey, .volumeIsRemovableKey, .volumeIsLocalKey])
    return values?.volumeIsEjectable == true || values?.volumeIsRemovable == true || values?.volumeIsLocal == false
  }
  static func list(using reader: NativeVolumeReader) throws -> [NativeVolume] {
    guard let urls = reader.mountedURLs() else { throw NativeNetwork.failure("无法读取已挂载的磁盘。") }
    let kinds = reader.mountKinds()
    var seen = Set<String>()
    return urls.filter { ($0.path == "/" || $0.path.hasPrefix("/Volumes/") || isMountyPath($0.path)) && seen.insert($0.path).inserted }.map { url in
      let values = try? reader.attributes(url)
      let kind = kinds[url.path] ?? values?.local.map { $0 ? NativeVolumeKind.local : .network } ?? .unknown
      return NativeVolume(url: url, name: values?.name ?? url.lastPathComponent, total: values?.total, free: values?.free, kind: kind,
        canEject: isMountyPath(url.path) ? kind == .local : values?.ejectable == true || kind == .network, metadataUnavailable: values == nil)
    }.sorted { a, b in if a.url.path == "/" { return b.url.path != "/" }; if b.url.path == "/" { return false }; return a.name.localizedStandardCompare(b.name) == .orderedAscending }
  }
  public static func eject(_ url: URL) throws -> [NativeVolume] {
    let selected = try ejectable(url, among: list())
    if isMountyPath(selected.path) {
      // diskutil resolves the live mount point and normally unmounts its volumes before ejecting.
      let process = Process()
      let errors = Pipe()
      process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
      process.arguments = ["eject", selected.path]
      process.standardOutput = FileHandle.nullDevice
      process.standardError = errors
      try process.run()
      let diagnostic = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      process.waitUntilExit()
      guard process.terminationStatus == 0, sidebarMounts()[selected.path] == nil else {
        throw NativeNetwork.failure(NL("无法推出磁盘：{0}。请关闭正在使用它的文件或应用后重试。", diagnostic.isEmpty ? selected.name : diagnostic))
      }
    } else {
      try NSWorkspace.shared.unmountAndEjectDevice(at: selected.url)
    }
    return try list()
  }
  public static func ejectable(_ url: URL, among volumes: [NativeVolume]) throws -> NativeVolume {
    guard url.isFileURL, [nil, "", "localhost"].contains(url.host), url.query == nil, url.fragment == nil, url.path != "/", url.path.hasPrefix("/Volumes/") || isMountyPath(url.path), url.standardizedFileURL.path == url.path,
      !url.path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
      let volume = volumes.first(where: { $0.url.path == url.path && $0.canEject }), volume.url.path != "/" else {
      throw NativeNetwork.failure("此位置不是可推出的已挂载磁盘。")
    }
    return volume
  }
}

struct NativeMountAPI {
  let start: (URL, DispatchQueue, @escaping (Int32, [String]?) -> Void) -> (Int32, UnsafeMutableRawPointer?)
  let cancel: (UnsafeMutableRawPointer) -> Int32
  static let live = NativeMountAPI(start: { url, queue, completion in
    var request: AsyncRequestID?
    let status = NetFSMountURLAsync(url as CFURL, nil, nil, nil, nil, nil, &request, queue) { status, _, mounts in completion(status, mounts as? [String]) }
    return (status, request)
  }, cancel: { NetFSMountURLCancel($0) })
}

// All NetFS state and completions run on one queue, including cancellation before startup.
final class NativeMountRequest: @unchecked Sendable {
  private let queue = DispatchQueue(label: "local.macexplorer.native.smb")
  private let api: NativeMountAPI
  private var continuation: CheckedContinuation<[String]?, Error>?
  private var token: UnsafeMutableRawPointer?
  private var timer: DispatchWorkItem?
  private var cancelled = false
  private var finished = false
  init(api: NativeMountAPI = .live) { self.api = api }
  func run(_ url: URL, timeout: TimeInterval = 120) async throws -> [String]? {
    try await withTaskCancellationHandler(operation: {
      try await withCheckedThrowingContinuation { continuation in
        queue.async {
          self.continuation = continuation
          if self.cancelled || Task.isCancelled { self.complete(.success(nil)); return }
          let (status, token) = self.api.start(url, self.queue) { status, paths in
            if status == -128 { self.complete(.success(nil)) }
            else if status == 0 || (status == EEXIST && paths?.isEmpty == false) { self.complete(.success(paths ?? [])) }
            else { self.complete(.failure(NSError(domain: status > 0 ? NSPOSIXErrorDomain : NSOSStatusErrorDomain, code: Int(status)))) }
          }
          guard !self.finished else { return }
          if status == -128 { self.complete(.success(nil)); return }
          guard status == 0, let token else {
            self.complete(.failure(NSError(domain: status > 0 ? NSPOSIXErrorDomain : NSOSStatusErrorDomain, code: Int(status == 0 ? EIO : status)))); return
          }
          self.token = token
          let timer = DispatchWorkItem { [weak self] in self?.cancel(timedOut: true) }
          self.timer = timer; self.queue.asyncAfter(deadline: .now() + timeout, execute: timer)
        }
      }
    }, onCancel: { self.queue.async { self.cancel(timedOut: false) } })
  }
  private func cancel(timedOut: Bool) {
    guard !finished else { return }; cancelled = true
    guard let token else { return }
    // A failed NetFS cancellation is still pending; only its real completion may release the connection guard.
    guard api.cancel(token) == 0 else { return }
    if timedOut { complete(.failure(NativeNetwork.failure("连接超时，请重试。"))) }
    else { complete(.success(nil)) }
  }
  private func complete(_ result: Result<[String]?, Error>) {
    guard !finished else { return }; finished = true; timer?.cancel(); timer = nil; token = nil
    let continuation = self.continuation; self.continuation = nil; continuation?.resume(with: result)
  }
}

public actor NativeNetwork {
  public static let shared = NativeNetwork()
  public private(set) var isConnecting = false
  public init() {}
  public static func failure(_ message: String) -> NSError { NSError(domain: "MacExplorer.Network", code: 1, userInfo: [NSLocalizedDescriptionKey: NL(message)]) }
  public static func validate(_ input: String) throws -> URL {
    let failure = Self.failure("请输入有效的 SMB 服务器地址，例如 smb://server/share。")
    guard !input.isEmpty, input.utf16.count <= 2048, !input.contains("\\"), !input.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw failure }
    let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard value.lowercased().hasPrefix("smb://"), var parts = URLComponents(string: value), parts.scheme?.lowercased() == "smb",
      let host = parts.host, !host.isEmpty, host != ".", host != "..", !host.contains("@"), !host.contains("\\"),
      !host.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) }),
      parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
      parts.port.map({ (1...65535).contains($0) }) ?? true else { throw failure }
    let authority = String(value.dropFirst(6).split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)[0])
    guard !authority.hasSuffix(":"), let path = parts.percentEncodedPath.removingPercentEncoding, !path.contains("\\"),
      !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw failure }
    if host.hasPrefix("[") || host.hasSuffix("]") {
      guard host.hasPrefix("["), host.hasSuffix("]") else { throw failure }
      var address = in6_addr(); guard String(host.dropFirst().dropLast()).withCString({ inet_pton(AF_INET6, $0, &address) }) == 1 else { throw failure }
    }
    if !host.hasPrefix("[") { guard host.rangeOfCharacter(from: CharacterSet(charactersIn: "/:@?#[]%")) == nil else { throw failure } }
    parts.scheme = "smb"
    guard let url = parts.url else { throw failure }; return url
  }
  public func connection(_ input: String) async throws -> URL? {
    try await connect(input) { url in try await NativeMountRequest().run(url) }
  }
  // The injected mount operation keeps concurrency checks testable without contacting a real server.
  func connect(_ input: String, mount: @escaping (URL) async throws -> [String]?) async throws -> URL? {
    let url = try Self.validate(input)
    guard !isConnecting else { throw Self.failure("正在连接服务器，请稍候。") }
    isConnecting = true; defer { isConnecting = false }
    guard let paths = try await mount(url) else { return nil }
    return try Self.mountedDirectory(paths)
  }
  public static func mountedDirectory(_ paths: [String]) throws -> URL {
    guard !paths.isEmpty, paths.count <= 1024 else { throw failure("系统未返回已挂载的共享目录。") }
    for path in paths {
      guard path.hasPrefix("/"), !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw failure("系统返回的共享目录无效。") }
      let url = URL(fileURLWithPath: path)
      guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
      return url
    }
    throw failure("系统未返回已挂载的共享目录。")
  }
}
