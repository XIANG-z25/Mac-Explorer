import AppKit

/// OneDrive browsing belongs to Finder, where Microsoft's File Provider UI is available.
enum NativeOneDriveFinder {
  static func handles(_ url: URL, home: URL) -> Bool {
    guard url.isFileURL else { return false }
    let path = url.standardizedFileURL.path
    let legacy = home.appendingPathComponent("OneDrive").path
    if path == legacy || path.hasPrefix(legacy + "/") { return true }
    let prefix = home.appendingPathComponent("Library/CloudStorage").path + "/"
    guard path.hasPrefix(prefix),
          let provider = path.dropFirst(prefix.count).split(separator: "/").first else { return false }
    return provider == "OneDrive" || provider.hasPrefix("OneDrive-")
  }

  static func open(_ url: URL, completion: @escaping (Error?) -> Void) {
    // Explicitly target Finder so a custom default file viewer cannot route back here.
    let finder = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
    NSWorkspace.shared.open([url], withApplicationAt: finder,
      configuration: NSWorkspace.OpenConfiguration()) { _, error in completion(error) }
  }
}
