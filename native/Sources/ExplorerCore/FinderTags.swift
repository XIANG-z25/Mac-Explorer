import Foundation
import Darwin

/// Finder stores tags as URL resource values. Keep the API small and opt-in so
/// ordinary directory reads never pay for tag metadata.
public enum FinderTags {
  public static func names(at url: URL) throws -> [String] {
    normalize(try storedNames(at: url))
  }

  private static let attribute = "com.apple.metadata:_kMDItemUserTags"
  private static func storedNames(at url: URL) throws -> [String] {
    // URL resource values can remain cached after an xattr edit. Read only this
    // small attribute and never follow a symlink into an unrelated file.
    let length = url.path.withCString { Darwin.getxattr($0, attribute, nil, 0, 0, XATTR_NOFOLLOW) }
    if length < 0 && errno == ENOATTR { return [] }
    guard length >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    guard length <= 64 * 1024 else { throw CocoaError(.fileReadCorruptFile) }
    if length == 0 { return [] }
    var data = Data(count: length)
    let count = data.withUnsafeMutableBytes { buffer in
      url.path.withCString { Darwin.getxattr($0, attribute, buffer.baseAddress, buffer.count, 0, XATTR_NOFOLLOW) }
    }
    guard count >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    data.count = count
    guard let names = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String] else { throw CocoaError(.fileReadCorruptFile) }
    return names
  }

  public static func commonNames(in urls: [URL]) throws -> [String] {
    guard let first = urls.first else { return [] }
    var common = Set(try names(at: first))
    for url in urls.dropFirst() { common.formIntersection(try names(at: url)) }
    return common.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
  }

  public static func set(_ names: [String], on urls: [URL]) -> FileActionResult {
    let normalized = normalize(names)
    var succeeded: [URL] = [], errors: [String] = []
    for url in urls {
      do {
        try write(normalized, to: url)
        succeeded.append(url)
      } catch { errors.append("\(url.path)：\(error.localizedDescription)") }
    }
    return FileActionResult(succeeded: succeeded, errors: errors, changes: [])
  }

  public static func matches(_ url: URL, query: String) -> Bool {
    let wanted = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !wanted.isEmpty else { return true }
    return (try? names(at: url))?.contains { $0.range(of: wanted, options: [.caseInsensitive, .diacriticInsensitive]) != nil } == true
  }

  public static func normalize(_ values: [String]) -> [String] {
    var seen = Set<String>(), result: [String] = []
    for value in values {
      // Finder's colored-tag representation can append a newline and color id.
      let name = value.split(separator: "\n", maxSplits: 1).first.map(String.init)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      guard !name.isEmpty, name.count <= 255 else { continue }
      let key = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
      if seen.insert(key).inserted { result.append(name) }
    }
    return Array(result.prefix(30))
  }

  private static func write(_ names: [String], to url: URL) throws {
    // The Swift URL overlay makes tagNames read-only. Finder itself persists
    // this metadata as a binary property-list extended attribute.
    let path = url.path
    if names.isEmpty {
      let result = path.withCString { Darwin.removexattr($0, attribute, XATTR_NOFOLLOW) }
      guard result == 0 || errno == ENOATTR else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
      return
    }
    let existing = try storedNames(at: url)
    let stored = names.map { name in existing.first { normalize([$0]).first == name } ?? name + "\n0" }
    let data = try PropertyListSerialization.data(fromPropertyList: stored, format: .binary, options: 0)
    let result = data.withUnsafeBytes { buffer in
      path.withCString { Darwin.setxattr($0, attribute, buffer.baseAddress, data.count, 0, XATTR_NOFOLLOW) }
    }
    guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
  }
}
