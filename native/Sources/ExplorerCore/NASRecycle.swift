import Foundation
import Darwin

/// Recoverable moves to an existing server trash folder. Never unlink user items,
/// create a pretend trash root, or traverse the contents of selected folders.
public enum NASRecycle {
  private static let names = ["trashbox", "#recycle", "@Recycle"]
  private static let prefix = "Mac Explorer-"
  public struct Plan: Sendable {
    public let source: URL
    public let trash: URL
    let sourceIdentity: String
    let parentIdentity: String
    let trashIdentity: String
    let device: dev_t
  }
  private static func failure(_ text: String) -> NSError {
    NSError(domain: "NASRecycle", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
  }
  private static func info(_ url: URL) throws -> stat {
    var value = stat()
    guard lstat(url.path, &value) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSFilePathErrorKey: url.path]) }
    return value
  }
  private static func directory(_ url: URL) throws -> stat {
    let value = try info(url)
    guard value.st_mode & S_IFMT == S_IFDIR, url.resolvingSymlinksInPath().path == url.path else {
      throw failure(NL("NAS 回收站路径发生变化，已停止。"))
    }
    return value
  }
  private static func inside(_ url: URL, _ root: URL) -> Bool { url.path.hasPrefix(root.path + "/") }

  public static func prepare(_ sources: [URL]) throws -> [Plan] {
    try sources.map { source in
      let parent = source.standardizedFileURL.deletingLastPathComponent().resolvingSymlinksInPath()
      let fd = open(parent.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
      guard fd >= 0 else { throw failure(NL("无法确认 NAS 共享位置，已停止。")) }
      defer { close(fd) }
      var mount = statfs()
      guard fstatfs(fd, &mount) == 0 else { throw failure(NL("无法确认 NAS 共享位置，已停止。")) }
      func text<T>(_ value: inout T) -> String {
        withUnsafePointer(to: &value) { $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout<T>.size) { String(cString: $0) } }
      }
      // Only the mounted filesystem and its root matter for local namespace moves.
      // Parsing the server login URL would wrongly reject guest mounts with an
      // empty password, and is unnecessary because no separate SMB login occurs.
      guard text(&mount.f_fstypename) == "smbfs" else { throw failure(NL("无法确认 NAS 共享位置，已停止。")) }
      return try prepare(source, root: URL(fileURLWithPath: text(&mount.f_mntonname)))
    }
  }
  // Internal entry point permits isolated local fixtures; production always resolves
  // the actual mounted SMB share from the selected item's parent above.
  static func prepare(_ input: URL, root: URL) throws -> Plan {
    guard input.isFileURL, input.baseURL == nil, input.query == nil, input.fragment == nil,
      input.user == nil, input.password == nil, input.port == nil, !input.path.contains("\0"),
      [nil, "", "localhost"].contains(input.host) else { throw failure(NL("无效的 NAS 路径。")) }
    let parent = input.standardizedFileURL.deletingLastPathComponent().resolvingSymlinksInPath()
    let source = parent.appendingPathComponent(input.lastPathComponent)
    guard inside(source, root), !names.contains(where: { source.path == root.appendingPathComponent($0).path || inside(source, root.appendingPathComponent($0)) }) else {
      throw failure(NL("不能将共享根目录或回收站内的项目再次移入回收站。"))
    }
    try FileActions.validateModificationSource(source)
    let roots = names.map { root.appendingPathComponent($0, isDirectory: true) }.filter { url in
      var value = stat(); return lstat(url.path, &value) == 0
    }
    guard roots.count == 1, let trash = roots.first else {
      throw failure(NL("未找到唯一的 NAS 回收站，未删除任何文件。"))
    }
    let sourceInfo = try info(source), trashInfo = try directory(trash)
    _ = try directory(parent)
    guard sourceInfo.st_dev == trashInfo.st_dev else { throw failure(NL("NAS 回收站不在同一个共享中，已停止。")) }
    return Plan(source: source, trash: trash, sourceIdentity: try FileActions.identity(source),
      parentIdentity: try FileActions.identity(parent), trashIdentity: try FileActions.identity(trash), device: sourceInfo.st_dev)
  }
  public static func move(_ plans: [Plan]) -> FileActionResult {
    var succeeded: [URL] = [], changes: [FileActionChange] = []
    do {
      // Validate the complete selection before moving its first entry.
      let paths = plans.map(\.source.path)
      guard Set(paths).count == paths.count,
        !paths.contains(where: { path in paths.contains(where: { $0 != path && path.hasPrefix($0 + "/") }) }) else {
        throw failure(NL("请选择不同且互不包含的项目。"))
      }
      for plan in plans { try validate(plan) }
      for plan in plans {
        try Task.checkCancellation(); try validate(plan)
        let bucket = plan.trash.appendingPathComponent(prefix + UUID().uuidString, isDirectory: true)
        // A unique, app-owned container prevents collisions with existing server
        // trash entries without scanning or modifying any of them.
        try FileManager.default.createDirectory(at: bucket, withIntermediateDirectories: false)
        let destination = bucket.appendingPathComponent(plan.source.lastPathComponent)
        let noteName = plan.source.lastPathComponent == ".mac-explorer-origin.json" ? ".mac-explorer-origin-1.json" : ".mac-explorer-origin.json"
        let noteURL = bucket.appendingPathComponent(noteName)
        do {
          let note = try JSONEncoder().encode(["originalPath": plan.source.path, "name": plan.source.lastPathComponent])
          try note.write(to: noteURL, options: .withoutOverwriting)
          try validate(plan)
          guard try directory(bucket).st_dev == plan.device else { throw failure(NL("NAS 回收站发生变化，已停止。")) }
          try FileManager().moveItem(at: plan.source, to: destination)
        } catch {
          // Only remove our own empty bucket/metadata; never delete its payload.
          if (try? FileManager.default.contentsOfDirectory(atPath: bucket.path)) == [noteName] {
            try? FileManager.default.removeItem(at: noteURL)
          }
          if (try? FileManager.default.contentsOfDirectory(atPath: bucket.path).isEmpty) == true { try? FileManager.default.removeItem(at: bucket) }
          throw error
        }
        succeeded.append(destination)
        changes.append(FileActionChange(source: plan.source, destination: destination, kind: .nasRecycle))
      }
      return FileActionResult(succeeded: succeeded, errors: [], changes: changes)
    } catch { return FileActionResult(succeeded: succeeded, errors: [error.localizedDescription], changes: changes) }
  }
  private static func validate(_ plan: Plan) throws {
    _ = try directory(plan.trash)
    _ = try directory(plan.source.deletingLastPathComponent())
    guard try FileActions.identity(plan.trash) == plan.trashIdentity,
      try FileActions.identity(plan.source.deletingLastPathComponent()) == plan.parentIdentity,
      try FileActions.identity(plan.source) == plan.sourceIdentity,
      try info(plan.source).st_dev == plan.device else { throw failure(NL("NAS 项目已发生变化，已停止。")) }
  }
  /// Undo/redo use the same system move as recycling, with no copy/delete fallback.
  static func reverse(_ change: FileActionChange) throws -> FileActionChange {
    guard let destination = change.source else { throw failure(NL("缺少 NAS 原始位置。")) }
    let source = change.destination
    let a = source.deletingLastPathComponent(), b = destination.deletingLastPathComponent()
    _ = try directory(a); _ = try directory(b)
    guard try info(a).st_dev == info(b).st_dev else { throw failure(NL("NAS 挂载已变化，无法撤销。")) }
    try FileManager().moveItem(at: source, to: destination)
    return FileActionChange(source: source, destination: destination, kind: .nasRecycle)
  }
}
