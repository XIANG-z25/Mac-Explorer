import Foundation
import Darwin

@main
enum AndroidMTPChecks {
  static func main() async throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("android-mtp-check-" + UUID().uuidString)
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }
    let helper = root.appendingPathComponent("fixture-helper")
    let script = """
    #!/usr/bin/python3
    import sys,json
    args=sys.argv[1:]
    if args[0]=='devices': print(json.dumps([dict(id='test-phone',name='Android')]))
    elif args[0]=='storages': print(json.dumps([dict(id=7,name='Internal')]))
    elif args[0]=='list':
      if args[3]=='4294967295':
        print(json.dumps([dict(id=2,name='中文 文件.txt',directory=False,size=7),dict(id=1,name='Folder',directory=True,size=0)]))
      elif args[3]=='1': print(json.dumps([dict(id=3,name='data.bin',directory=False,size=7)]))
      elif args[3]=='99': print(json.dumps([dict(id=4,name='../escape',directory=False,size=7)]))
      elif args[3]=='98': print(json.dumps([dict(id=3,name='a',directory=False,size=7),dict(id=3,name='b',directory=False,size=7)]))
      else: print(json.dumps([dict(id=5,name='broken.bin',directory=False,size=7)]))
    elif args[0]=='get':
      with open(args[4],'xb') as f: f.write(b'fixture')
      if args[3]=='5': print(json.dumps(dict(error='readUnavailable')));sys.exit(1)
      print(json.dumps(dict(bytes=7)))
    else: sys.exit(1)
    """
    try script.write(to: helper, atomically: true, encoding: .utf8)
    try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
    let client = AndroidMTP(helper: helper)
    var count = 0
    func check(_ value: Bool, _ title: String) throws {
      guard value else { throw NSError(domain: "AndroidMTPChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: title]) }
      count += 1; print("PASS Android: " + title)
    }
    let phone = try client.devices()[0]
    try check(try client.storages(phone)[0].id == 7, "Device and storage JSON are decoded")
    let items = try client.list(phone, storage: 7, parent: UInt32.max)
    try check(items[0].directory && items[1].name == "中文 文件.txt", "Folders-first Unicode listing")
    let out = root.appendingPathComponent("saved")
    try fm.createDirectory(at: out, withIntermediateDirectories: false)
    let file = try client.save(items[1], device: phone, storage: 7, to: out)
    try check(try Data(contentsOf: file) == Data("fixture".utf8), "File import preserves bytes")
    let folder = try client.save(items[0], device: phone, storage: 7, to: out)
    try check(try Data(contentsOf: folder.appendingPathComponent("data.bin")) == Data("fixture".utf8), "Recursive directory import")
    do {
      _ = try client.save(items[1], device: phone, storage: 7, to: out)
      throw NSError(domain: "UnexpectedSuccess", code: 1)
    } catch {
      try check((error as NSError).domain != "UnexpectedSuccess" && (try Data(contentsOf: file)) == Data("fixture".utf8), "Existing destination is never overwritten")
    }
    for parent: UInt32 in [98,99] {
      do {
        _ = try client.list(phone, storage: 7, parent: parent)
        throw NSError(domain: "UnexpectedSuccess", code: 1)
      } catch { try check((error as NSError).domain != "UnexpectedSuccess", "Duplicate identifiers and unsafe names are rejected") }
    }
    let broken = try client.list(phone, storage: 7, parent: 97)[0]
    do {
      _ = try client.save(broken, device: phone, storage: 7, to: out)
      throw NSError(domain: "UnexpectedSuccess", code: 1)
    } catch {
      try check((error as NSError).domain != "UnexpectedSuccess" && !fm.fileExists(atPath: out.appendingPathComponent(broken.name).path), "Partial download never publishes a broken destination")
    }
    try check(try fm.contentsOfDirectory(atPath: out.path).allSatisfy { !$0.hasPrefix(".mac-explorer-android-") }, "Staging directories are cleaned after success and failure")
    let cancelled = Task.detached { try Task.checkCancellation(); return try client.save(broken, device: phone, storage: 7, to: out) }
    cancelled.cancel()
    do { _ = try await cancelled.value; throw NSError(domain:"UnexpectedSuccess",code:1) }
    catch { try check(error is CancellationError, "Cancellation propagates to the transfer") }
    try check(!AndroidMTP.validName("..") && !AndroidMTP.validName("a/b") && !AndroidMTP.validName("x\0y"), "Device filenames cannot traverse local paths")
    print("AndroidMTPChecks: \(count) checks passed; synthetic transport only.")
  }
}
