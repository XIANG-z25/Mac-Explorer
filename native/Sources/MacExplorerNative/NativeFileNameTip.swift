import AppKit

/// A delayed, click-through filename tip. It reads the already-loaded name and
/// never asks a cloud provider or NAS for additional metadata.
final class NativeFileNameTip {
  private(set) var panel: NSPanel?
  private var pending: DispatchWorkItem?
  private weak var owner: NSWindow?
  private var observers: [NSObjectProtocol] = []
  /// Last reason a tip was not shown; read by the pointer checks for diagnostics.
  private(set) var lastSkip = ""

  func schedule(name: String, in host: ItemSurface) {
    hide()
    guard !name.isEmpty, let window = host.window, window.isVisible else { lastSkip = "schedule: name=\(name.isEmpty ? "empty" : "ok") window=\(host.window == nil ? "nil" : "visible=\(host.window?.isVisible == true)")"; return }
    lastSkip = "scheduled"
    owner = window
    for notification in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification, NSWindow.didResizeNotification, NSWindow.didMoveNotification] {
      observers.append(NotificationCenter.default.addObserver(forName: notification, object: window, queue: .main) { [weak self] _ in self?.hide() })
    }
    if let clip = host.enclosingScrollView?.contentView {
      clip.postsBoundsChangedNotifications = true
      let origin = clip.bounds.origin
      observers.append(NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) { [weak self, weak clip] _ in
        // Only real scrolling dismisses the tip; layout passes that merely resize the clip view keep it pending.
        if let clip, clip.bounds.origin != origin { self?.hide() }
      })
    }
    let work = DispatchWorkItem { [weak self, weak host] in
      guard let self else { return }
      guard let host, host.hovered, host.fullFileName == name, NSEvent.pressedMouseButtons == 0 else { self.lastSkip = "fired: host=\(host == nil ? "nil" : "hovered=\(host!.hovered) sameName=\(host!.fullFileName == name)") buttons=\(NSEvent.pressedMouseButtons)"; return }
      self.show(name: name, in: host)
    }
    pending = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
  }

  private func show(name: String, in host: ItemSurface) {
    pending = nil
    guard let window = owner, host.window === window, window.isVisible,
          !host.isHiddenOrHasHiddenAncestor, !host.visibleRect.isEmpty,
          NSApp.modalWindow == nil, window.attachedSheet == nil,
          !ExplorerDialogs.isPresenting(in: window), !(window.firstResponder is NSTextView) else {
      lastSkip = "show: owner=\(owner == nil ? "nil" : "ok") sameWindow=\(host.window === owner) visible=\(owner?.isVisible == true) hidden=\(host.isHiddenOrHasHiddenAncestor) emptyRect=\(host.visibleRect.isEmpty) modal=\(NSApp.modalWindow != nil) sheet=\(owner?.attachedSheet != nil) dialog=\(owner.map { ExplorerDialogs.isPresenting(in: $0) } ?? false) textResponder=\(owner?.firstResponder is NSTextView)"
      hide(); return
    }
    lastSkip = "shown"
    let pointer = NSEvent.mouseLocation
    let screen = (NSScreen.screens.first { $0.frame.contains(pointer) } ?? window.screen ?? NSScreen.main)?.visibleFrame ?? window.frame
    let font = ExplorerTypography.font()
    let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byCharWrapping
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: paragraph]
    let width = min(max(80, screen.width - 24), min(460, max(100, ceil((name as NSString).size(withAttributes: attributes).width) + 18)))
    let measured = (name as NSString).boundingRect(with: NSSize(width: width - 18, height: 10_000), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes)
    let height = ceil(measured.height) + 14
    let frame = Self.frame(near: pointer, size: NSSize(width: width, height: height), on: screen)
    let tip = FileNameTipPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    tip.isReleasedWhenClosed = false; tip.isOpaque = false; tip.backgroundColor = .clear
    tip.hasShadow = true; tip.ignoresMouseEvents = true; tip.hidesOnDeactivate = true
    let body = FileNameTipSurface(frame: NSRect(x: 0, y: 0, width: width, height: height))
    let text = label(name); text.font = font; text.maximumNumberOfLines = 0; text.lineBreakMode = .byCharWrapping
    text.frame = body.bounds.insetBy(dx: 9, dy: 7); body.addSubview(text); tip.contentView = body
    tip.setAccessibilityLabel(name)
    panel = tip; window.addChildWindow(tip, ordered: .above); tip.orderFront(nil)
  }

  static func frame(near pointer: NSPoint, size: NSSize, on screen: NSRect) -> NSRect {
    let usable = screen.insetBy(dx: 6, dy: 6)
    let right = pointer.x + 14
    let left = pointer.x - size.width - 14
    let x = right + size.width <= usable.maxX ? right : left
    // Align the top of the tip with the pointer. Lift it near the bottom edge.
    let y = pointer.y - size.height
    return NSRect(
      x: max(usable.minX, min(x, usable.maxX - size.width)),
      y: max(usable.minY, min(y, usable.maxY - size.height)),
      width: size.width, height: size.height
    )
  }

  func hide() {
    pending?.cancel(); pending = nil
    for observer in observers { NotificationCenter.default.removeObserver(observer) }; observers = []
    if let panel { owner?.removeChildWindow(panel); panel.orderOut(nil) }; panel = nil; owner = nil
  }

  deinit {
    pending?.cancel()
    for observer in observers { NotificationCenter.default.removeObserver(observer) }
    if let panel { owner?.removeChildWindow(panel); panel.orderOut(nil) }
  }
}

private final class FileNameTipPanel: NSPanel {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}

private final class FileNameTipSurface: SurfaceView {
  override func draw(_ dirtyRect: NSRect) {
    let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
    ExplorerPalette.surface.setFill(); path.fill()
    ExplorerPalette.border.setStroke(); path.lineWidth = 1; path.stroke()
  }
}
