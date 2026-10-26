import AppKit
import ExplorerCore

@main enum DeletionUIChecks {
  @MainActor static func main() async throws {
    NSApplication.shared.setActivationPolicy(.prohibited)
    NativeLanguage.load(from: URL(fileURLWithPath: CommandLine.arguments[1])); NativeLanguage.mode = "zh-CN"
    let output = URL(fileURLWithPath: CommandLine.arguments[2])
    let checks = try await NativeNetworkDeleteChecks.run(output: output)
    precondition(!NSApp.windows.contains { $0.isVisible }, "Headless checks displayed a window")
    try JSONSerialization.data(withJSONObject: ["passed": true, "checks": checks], options: [.prettyPrinted]).write(to: output.appendingPathComponent("report.json"))
  }
}
