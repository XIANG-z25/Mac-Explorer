import Foundation

/// Short-lived metadata only. Device object IDs must never outlive a refresh/reconnection.
/// Owned by the browser's main actor; USB reads and sorting remain in its worker.
public struct AndroidDirectoryCache {
  public struct Key: Hashable, Sendable {
    public let device: String
    public let storage: UInt32
    public let parent: UInt32
    public init(device: String, storage: UInt32, parent: UInt32) {
      self.device = device; self.storage = storage; self.parent = parent
    }
  }
  public struct Snapshot: Sendable {
    public let items: [AndroidItem]
    public let needsRefresh: Bool
  }
  private struct Entry {
    let items: [AndroidItem]
    let created: TimeInterval
    let cost: Int
    var used: UInt64
  }
  private var entries: [Key: Entry] = [:]
  private var clock: UInt64 = 0
  private var cost = 0
  private let maximumBytes: Int
  private let maximumFolders: Int
  private let freshness: TimeInterval
  private let lifetime: TimeInterval

  public init(maximumBytes: Int = 4 * 1024 * 1024, maximumFolders: Int = 32,
    freshness: TimeInterval = 5, lifetime: TimeInterval = 30) {
    self.maximumBytes = max(0, maximumBytes); self.maximumFolders = max(0, maximumFolders)
    self.freshness = max(0, freshness); self.lifetime = max(freshness, lifetime)
  }
  public var folderCount: Int { entries.count }
  public var estimatedBytes: Int { cost }

  public mutating func snapshot(for key: Key, now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Snapshot? {
    guard var entry = entries[key] else { return nil }
    let age = now - entry.created
    guard age >= 0, age < lifetime else { remove(key); return nil }
    clock &+= 1; entry.used = clock; entries[key] = entry
    return Snapshot(items: entry.items, needsRefresh: age >= freshness)
  }
  public mutating func insert(_ items: [AndroidItem], for key: Key,
    now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
    remove(key)
    // Don't walk or retain extremely large listings on the UI actor.
    guard maximumFolders > 0, items.count <= 20000 else { return }
    let bytes = items.reduce(256) { $0 + 128 + $1.name.utf8.count * 2 }
    guard bytes <= maximumBytes else { return }
    while entries.count >= maximumFolders || cost + bytes > maximumBytes {
      guard let oldest = entries.min(by: { $0.value.used < $1.value.used })?.key else { break }
      remove(oldest)
    }
    clock &+= 1
    entries[key] = Entry(items: items, created: now, cost: bytes, used: clock); cost += bytes
  }
  public mutating func remove(_ key: Key) {
    if let old = entries.removeValue(forKey: key) { cost -= old.cost }
  }
  public mutating func removeAll() { entries.removeAll(); cost = 0 }
}
