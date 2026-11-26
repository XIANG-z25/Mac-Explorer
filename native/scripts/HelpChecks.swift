import AppKit

@main
enum HelpChecks {
  static func main() {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 400, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
    let help = NativeHelpButton(text: "Help fixture: existing settings remain unchanged.", accessibilityLabel: "Help fixture")
    help.frame = NSRect(x: 340, y: 90, width: 24, height: 28)
    window.contentView!.addSubview(help); window.makeKeyAndOrderFront(nil)
    func shown() -> Bool { app.windows.contains { $0 !== window && $0.isVisible } }
    func settle() { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
    help.mouseEntered(with: NSEvent()); settle()
    precondition(shown(), "Hover must show help")
    help.mouseExited(with: NSEvent()); settle()
    precondition(!shown(), "Leaving hover must dismiss help")
    help.performClick(nil); settle()
    precondition(shown(), "Click must show help")
    help.mouseExited(with: NSEvent()); settle()
    precondition(shown(), "Clicked help must stay open after pointer leaves")
    help.removeFromSuperview(); settle()
    precondition(!shown(), "Removing the help control must close its popup")
    window.contentView!.addSubview(help)
    window.makeFirstResponder(help); settle()
    precondition(shown(), "Keyboard focus must show help")
    print("Help checks passed: hover, exit, click, pinned reading, removal, keyboard focus")
    window.close()
  }
}
