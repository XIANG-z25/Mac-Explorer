import Foundation

public struct AndroidDevice: Decodable, Sendable {
  public let id: String
  public let name: String
}
public struct AndroidStorage: Decodable, Sendable {
  public let id: UInt32
  public let name: String
}
public struct AndroidItem: Decodable, Sendable {
  public let id: UInt32
  public let name: String
  public let directory: Bool
  public let size: UInt64
}

/// All USB work lives in a cancellable helper process, not the main application.
public struct AndroidMTP: Sendable {
  public let helper: URL
  public init(helper: URL) { self.helper = helper }

  public static func validName(_ name: String) -> Bool {
    !name.isEmpty && name != "." && name != ".." && !name.contains("/") &&
      !name.contains("\0") && name.utf8.count <= 255
  }

  private func request<T: Decodable>(_ arguments: [String], timeout: TimeInterval = 25) throws -> T {
    guard FileManager.default.isExecutableFile(atPath: helper.path) else {
      throw Self.failure(NL("安卓 USB 组件未包含在此构建中。"))
    }
    let result: NativeCommandResult
    do {
      result = try NativeCommand.run(executable: helper.path, arguments: arguments,
        timeout: timeout, limit: 16 * 1024 * 1024)
    } catch let error as NativeCommandError {
      let response = try? JSONSerialization.jsonObject(with: error.result.output) as? [String: String]
      let code = response?["error"] ?? ""
      if code == "destinationUnavailable" { throw Self.failure(NL("目标文件已存在或无法写入。")) }
      throw Self.failure(NL("无法读取手机。请解锁手机，选择 USB 文件传输，并关闭其他手机传输软件后重试。"))
    } catch {
      let failure = error as NSError
      if failure.domain == "NativeCommand" && failure.code == 1 {
        throw Self.failure(NL("连接手机超时。请重新连接 USB 后刷新设备。"))
      }
      throw error
    }
    return try JSONDecoder().decode(T.self, from: result.output)
  }

  public func devices() throws -> [AndroidDevice] { try request(["devices"]) }
  public func storages(_ device: AndroidDevice) throws -> [AndroidStorage] {
    try request(["storages", device.id])
  }
  public func list(_ device: AndroidDevice, storage: UInt32, parent: UInt32) throws -> [AndroidItem] {
    let items: [AndroidItem] = try request(["list", device.id, String(storage), String(parent)])
    guard items.count <= 100000, items.allSatisfy({ Self.validName($0.name) }),
          Set(items.map(\.id)).count == items.count else { throw Self.failure(NL("手机返回了无效的文件清单。")) }
    return items.sorted {
      if $0.directory != $1.directory { return $0.directory }
      return $0.name.localizedStandardCompare($1.name) == .orderedAscending
    }
  }

  public func save(_ item: AndroidItem, device: AndroidDevice, storage: UInt32, to destination: URL,
    progress: @Sendable (String) -> Void = { _ in }) throws -> URL {
    guard destination.isFileURL, Self.validName(item.name) else { throw CocoaError(.fileWriteInvalidFileName) }
    try Task.checkCancellation()
    let manager = FileManager.default
    let stage = try FileActions.create(in: destination, name: ".mac-explorer-android-" + UUID().uuidString, directory: true).destination
    defer { try? manager.removeItem(at: stage) }
    var visited = Set<UInt32>()
    func read(_ current: AndroidItem, into parent: URL, depth: Int) throws {
      try Task.checkCancellation()
      guard depth < 128, visited.count < 100000, visited.insert(current.id).inserted,
            Self.validName(current.name) else { throw Self.failure(NL("手机文件夹层级或清单无效。")) }
      progress(current.name)
      if current.directory {
        let folder = try FileActions.create(in: parent, name: current.name, directory: true).destination
        for child in try list(device, storage: storage, parent: current.id) { try read(child, into: folder, depth: depth + 1) }
      } else {
        let _: [String: UInt64] = try request(["get", device.id, String(storage),
          String(current.id), parent.appendingPathComponent(current.name).path], timeout: 3600)
      }
    }
    try read(item, into: stage, depth: 0)
    try Task.checkCancellation()
    let result = FileActions.transfer([stage.appendingPathComponent(item.name)], to: destination, move: true)
    guard result.errors.isEmpty, let saved = result.succeeded.first else {
      throw Self.failure(result.errors.joined(separator: "\n"))
    }
    return saved
  }

  private static func failure(_ message: String) -> NSError {
    NSError(domain: "AndroidMTP", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
  }
}
