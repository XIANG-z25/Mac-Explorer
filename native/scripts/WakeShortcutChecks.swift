import Foundation

@main
struct WakeShortcutChecks {
  static func main() throws {
    var checks = 0
    for value in ["", "Control+Alt+E", "Command+Alt+F19", "F18", "⌃⌥E"] {
      let binding = try NativeSystemIntegration.keyBinding(value)
      assert(value.isEmpty ? binding == nil : binding != nil); checks += 1
    }
    for value in ["A", "Shift+A", "Bogus+F1", "Command+Command+E", "Command+Space", "Control+Up", "Command+Q", "Command+F99", "Command+Bogus+F1", "Alt++A", "Control+A+F1"] {
      do { _ = try NativeSystemIntegration.keyBinding(value); fatalError("Accepted invalid shortcut " + value) }
      catch { checks += 1 }
    }
    print("Wake shortcut validation checks passed: \(checks); no global hotkeys registered.")
  }
}
