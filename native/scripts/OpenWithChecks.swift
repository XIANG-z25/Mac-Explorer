import AppKit

@main
struct OpenWithChecks {
  static func main() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("open-with-check-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    func app(_ folder: String, _ id: String) throws -> URL {
      let url = root.appendingPathComponent(folder).appendingPathComponent("Same Name.app")
      try FileManager.default.createDirectory(at: url.appendingPathComponent("Contents"), withIntermediateDirectories: true)
      let plist = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": id, "CFBundleName": "Same Name", "CFBundlePackageType": "APPL"], format: .xml, options: 0)
      try plist.write(to: url.appendingPathComponent("Contents/Info.plist")); return url
    }
    let old = try app("old", "local.macexplorer.desktop")
    let native = try app("native", "local.macexplorer.native-prototype")
    let validation = try app("validation", "local.macexplorer.native-validation")
    let other = try app("other", "example.other")
    let alias = root.appendingPathComponent("alias.app")
    try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: native)
    let result = NativeOpenWith.uniqueApplications([old, validation, native, other, alias, root.appendingPathComponent("missing.app")], defaultApplication: native)
    precondition(result.count == 2 && result.first?.url == native.resolvingSymlinksInPath() && result.first?.isDefault == true)
    precondition(result.contains { $0.url == other.resolvingSymlinksInPath() }, "Different apps with the same name must remain available")
    let downloads = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    let actual = NativeOpenWith.applications([downloads])
    let own = actual.filter { ["local.macexplorer.desktop", "local.macexplorer.native-prototype", "local.macexplorer.native-validation"].contains(Bundle(url: $0.url)?.bundleIdentifier ?? "") }
    precondition(own.count <= 1)
    if NSWorkspace.shared.urlsForApplications(toOpen: downloads).contains(where: { $0.path == "/Applications/Mac Explorer.app" }) {
      precondition(own.first?.url.path == "/Applications/Mac Explorer.app", "Prefer the installed copy over build artifacts")
    }
    print("PASS: duplicate bundles, aliases, native/legacy identity, validation exclusion, missing apps, default retention, distinct same-name apps.")
    print("System candidates:")
    for url in NSWorkspace.shared.urlsForApplications(toOpen: downloads) where url.lastPathComponent.contains("Mac Explorer") { print(url.path) }
    print("Visible Mac Explorer entries: \(own.count)")
  }
}
