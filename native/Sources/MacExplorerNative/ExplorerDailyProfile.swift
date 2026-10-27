import AppKit
import ExplorerCore

/// Presentation preferences only; file operations retain the upstream safety checks.
enum ExplorerDailyProfile {
  static let key = "dailyMode"
  static let tools = ["cut", "copy", "paste", "rename", "batchRename", "trash", "undo"]
  static var isCustomBuild: Bool { Bundle.main.object(forInfoDictionaryKey: "ExplorerDailyBuild") as? Bool == true }
  static func enabled(_ defaults: UserDefaults) -> Bool { defaults.object(forKey: key) as? Bool ?? false }
  static func configure(_ defaults: UserDefaults, validation: Bool) {
    // UserDefaults registration is shared across suites. Seed only this domain so
    // fixture profiles and independently configured windows cannot inherit it.
    let initial: [String: Any] = [key: !validation, "versionControl": false,
      "defaultFolderView": ["view": "details", "iconSize": 64, "sort": "name", "ascending": true],
      "toolbar": tools, "compact": !validation]
    for (key, value) in initial where defaults.object(forKey: key) == nil {
      defaults.set(value, forKey: key)
    }
    // Existing Daily installations predate compact spacing. Apply this requested
    // presentation migration once, while leaving future user choices untouched.
    let compactMigrationKey = "dailyCompactSpacingMigrated"
    if !validation, enabled(defaults), defaults.object(forKey: compactMigrationKey) == nil {
      defaults.set(true, forKey: "compact")
      defaults.set(true, forKey: compactMigrationKey)
    }
  }
}

/// Let AppKit choose Latin and CJK fallback fonts and preserve normal antialiasing.
enum ExplorerTypography {
  static let preferenceKey = "interfaceFontSize"
  static var baseSize: CGFloat = 13
  static func configure(_ defaults: UserDefaults) {
    let saved = defaults.integer(forKey: preferenceKey)
    baseSize = CGFloat((12...16).contains(saved) ? saved : 13)
  }
  static func font(ofSize size: CGFloat = 13, weight: NSFont.Weight = .medium) -> NSFont {
    .systemFont(ofSize: max(12, size + baseSize - 13), weight: weight == .regular ? .medium : weight)
  }
}
