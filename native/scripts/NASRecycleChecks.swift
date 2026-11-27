import Foundation

@main enum NASRecycleChecks {
  static func main() throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("nas-recycle-" + UUID().uuidString)
    try fm.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? fm.removeItem(at: root) }
    let trash = root.appendingPathComponent("trashbox")
    let source = root.appendingPathComponent("video.mp4")
    let payload = Data("original-content".utf8)
    try payload.write(to: source)
    var count = 0
    func check(_ value: Bool, _ message: String) throws {
      guard value else { throw NSError(domain: "NASRecycleChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
      count += 1
    }
    do { _ = try NASRecycle.prepare(source, root: root); throw NSError(domain: "UnexpectedSuccess", code: 1) }
    catch { try check((error as NSError).domain != "UnexpectedSuccess" && fm.fileExists(atPath: source.path), "missing trash never deletes") }
    try fm.createDirectory(at: trash, withIntermediateDirectories: false)
    let existing = trash.appendingPathComponent("video.mp4")
    try Data("existing".utf8).write(to: existing)
    let folder = root.appendingPathComponent("Folder")
    try fm.createDirectory(at: folder, withIntermediateDirectories: false)
    try payload.write(to: folder.appendingPathComponent("child"))
    let plans = try [source, folder].map { try NASRecycle.prepare($0, root: root) }
    let result = NASRecycle.move(plans)
    try check(result.errors.isEmpty && result.changes.count == 2, "files and folders recycle")
    try check(try Data(contentsOf: result.succeeded[0]) == payload, "payload preserved")
    try check(try Data(contentsOf: result.succeeded[1].appendingPathComponent("child")) == payload, "directory contents preserved")
    try check(try Data(contentsOf: existing) == Data("existing".utf8), "existing trash names never overwritten")
    let undo = FileActions.undo(result.changes)
    try check(undo.errors.isEmpty && fm.fileExists(atPath: source.path), "undo restores original locations")
    let redo = FileActions.undo(undo.changes)
    try check(redo.errors.isEmpty && !fm.fileExists(atPath: source.path), "redo recycles again")
    let again = FileActions.undo(redo.changes)
    try check(again.errors.isEmpty, "second undo succeeds")
    let stale = try NASRecycle.prepare(source, root: root)
    try fm.moveItem(at: source, to: root.appendingPathComponent("changed")); try payload.write(to: source)
    try check(!NASRecycle.move([stale]).errors.isEmpty && fm.fileExists(atPath: source.path), "changed source is preserved")
    do { _ = try NASRecycle.prepare(existing, root: root); throw NSError(domain: "UnexpectedSuccess", code: 1) }
    catch { try check((error as NSError).domain != "UnexpectedSuccess", "trash contents cannot be recycled again") }
    try fm.moveItem(at: trash, to: root.appendingPathComponent("saved-trash"))
    try fm.createSymbolicLink(at: trash, withDestinationURL: root.appendingPathComponent("saved-trash"))
    do { _ = try NASRecycle.prepare(source, root: root); throw NSError(domain: "UnexpectedSuccess", code: 1) }
    catch { try check((error as NSError).domain != "UnexpectedSuccess", "symlink trash roots rejected") }
    print("NASRecycleChecks: \(count) checks passed")
  }
}
