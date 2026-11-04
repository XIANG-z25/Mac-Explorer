import Foundation

@main
enum CloudDriveChecks {
  static func main() throws {
    let manager = FileManager.default
    let root = manager.temporaryDirectory.appendingPathComponent("native-cloud-drives-" + UUID().uuidString)
    defer { try? manager.removeItem(at: root) }
    let storage = root.appendingPathComponent("Library/CloudStorage", isDirectory: true)
    for name in ["OneDrive-Contoso", "Box", "Dropbox", "GoogleDrive-Work", "Not A Provider"] {
      try manager.createDirectory(at: storage.appendingPathComponent(name, isDirectory: true), withIntermediateDirectories: true)
    }
    let volume = storage.appendingPathComponent("Box", isDirectory: true)
    try manager.createSymbolicLink(at: root.appendingPathComponent("Dropbox"), withDestinationURL: storage.appendingPathComponent("Dropbox"))
    let drives = NativeCloudDrives.discover(home: root, mountedVolumes: [volume])
    guard drives.map(\.name) == ["OneDrive-Contoso", "Box Drive", "Dropbox", "GoogleDrive-Work"] else {
      throw NSError(domain: "CloudDriveChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cloud providers are detected, named, ordered and deduplicated"])
    }
    guard drives.map(\.url.path).allSatisfy({ $0.hasPrefix(root.path) }) else {
      throw NSError(domain: "CloudDriveChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cloud discovery does not return paths outside its candidate set"])
    }
    guard drives.allSatisfy({ $0.sourceURLs.allSatisfy(\.isFileURL) }),
          let dropbox = drives.first(where: { $0.provider == .dropbox }),
          dropbox.sourceURLs.contains(root.appendingPathComponent("Dropbox").standardizedFileURL),
          drives.filter({ $0.provider == .dropbox }).count == 1 else {
      throw NSError(domain: "CloudDriveChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: "Legacy symlinks do not duplicate a File Provider root"])
    }
    print("CloudDriveChecks: 3 checks passed.")
  }
}
