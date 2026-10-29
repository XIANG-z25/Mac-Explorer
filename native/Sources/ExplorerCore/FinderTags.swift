import Foundation
import Darwin

/// Finder stores tags as URL resource values. Keep the API small and opt-in so
/// ordinary directory reads never pay for tag metadata.
public enum FinderTags {
  public static func names(at url: URL) throws -> [String] {
    let values = try url.resourceValues(forKeys: [.tagNamesKey])
    return normalize(values.tagNames ?? [])
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
      let result = path.withCString { Darwin.removexattr($0, "com.apple.metadata:_kMDItemUserTags", 0) }
      guard result == 0 || errno == ENOATTR else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
      return
    }
    let storedNames = names.map { $0 + "\n0" }
    let data = try PropertyListSerialization.data(fromPropertyList: storedNames, format: .binary, options: 0)
    let result = data.withUnsafeBytes { buffer in
      path.withCString { Darwin.setxattr($0, "com.apple.metadata:_kMDItemUserTags", buffer.baseAddress, data.count, 0, 0) }
    }
    guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
  }
}
