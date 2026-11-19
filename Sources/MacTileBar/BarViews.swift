import AppKit

let barHeight: CGFloat = 27
let capsuleSpacing: CGFloat = 4
private let capsuleHeight: CGFloat = 25
private let capsuleBorderWidth: CGFloat = 2

private let spaceFontSize: CGFloat = 10
private let spaceLabelMaxWidth: CGFloat = 100
private let spaceLeadingPadding: CGFloat = 6
private let spaceTrailingPadding: CGFloat = 6
private let spaceLabelIconGap: CGFloat = 2

private let windowButtonSize: CGFloat = 20
private let windowIconSize: CGFloat = 18
private let windowButtonGap: CGFloat = 2

private let statusFontSize: CGFloat = 11
private let statusHorizontalPadding: CGFloat = 10

private let floatingIndicatorWidth: CGFloat = 8
private let floatingIndicatorHeight: CGFloat = 2
private let floatingIndicatorBottomPadding: CGFloat = 0.5

final class BarPanel: NSPanel {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }

  init() {
    super.init(
      contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered, defer: false)
    title = "MacTileBar"
    isReleasedWhenClosed = false
    isOpaque = false
    backgroundColor = .clear
    hasShadow = false
    hidesOnDeactivate = false
    level = .floating
    collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
  }
}

func material(behind content: NSView, tint: NSColor? = nil) -> NSGlassEffectView {
  content.autoresizingMask = [.width, .height]
  let glass = NSGlassEffectView(frame: content.frame)
  glass.cornerRadius = capsuleHeight / 2
  glass.tintColor = tint
  glass.contentView = content
  return glass
}

func statusCapsule(_ title: String) -> NSView {
  let label = NSTextField(labelWithString: title)
  label.font = .systemFont(ofSize: statusFontSize, weight: .medium)
  label.textColor = .secondaryLabelColor
  label.sizeToFit()
  label.frame.origin = NSPoint(
    x: statusHorizontalPadding, y: (capsuleHeight - label.frame.height) / 2)
  let content = NSView(
    frame: NSRect(
      x: 0, y: 0, width: label.frame.maxX + statusHorizontalPadding, height: capsuleHeight))
  content.addSubview(label)
  return material(behind: content)
}

final class StripScrollView: NSScrollView {
  override func scrollWheel(with event: NSEvent) {
    guard event.scrollingDeltaX == 0, event.scrollingDeltaY != 0,
      let documentView, documentView.frame.width > contentSize.width
    else {
      super.scrollWheel(with: event)
      return
    }
    let amount =
      event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 18
    let point = NSPoint(x: contentView.bounds.minX - amount, y: 0)
    contentView.scroll(
      to: contentView.constrainBoundsRect(NSRect(origin: point, size: contentSize)).origin)
    reflectScrolledClipView(contentView)
  }
}

final class SpaceCapsule: NSView {
  private let spaceID: Space.ID
  private weak var controller: BarController?

  init(space: Space, windows: [TileWindow], controller: BarController) {
    spaceID = space.identity
    self.controller = controller
    let chips = windows.map { WindowChip(model: $0, controller: controller) }

    let label = NSTextField(labelWithString: space.title)
    label.font = .monospacedDigitSystemFont(
      ofSize: spaceFontSize, weight: space.focused ? .semibold : .medium)
    label.lineBreakMode = .byTruncatingTail
    label.sizeToFit()
    label.frame.size.width = min(spaceLabelMaxWidth, label.frame.width)
    label.frame.origin = NSPoint(
      x: spaceLeadingPadding, y: (capsuleHeight - label.frame.height) / 2)

    var x = label.frame.maxX + spaceLabelIconGap
    for chip in chips {
      chip.frame.origin = NSPoint(x: x, y: (capsuleHeight - chip.frame.height) / 2)
      x = chip.frame.maxX + windowButtonGap
    }
    let contentWidth = chips.last?.frame.maxX ?? label.frame.maxX
    // Empty Spaces keep symmetric padding around their label.
    let trailingPadding = chips.isEmpty ? spaceLeadingPadding : spaceTrailingPadding
    let frame = NSRect(
      x: 0, y: 0, width: contentWidth + trailingPadding, height: capsuleHeight)
    super.init(frame: frame)
    let content = NSView(frame: frame)
    content.addSubview(label)
    chips.forEach(content.addSubview)
    let tint: NSColor? =
      space.visible || space.focused
      ? NSColor.controlAccentColor.withAlphaComponent(space.focused ? 0.28 : 0.12) : nil
    addSubview(material(behind: content, tint: tint))

    wantsLayer = true
    layer?.cornerRadius = frame.height / 2
    let borderAlpha: CGFloat = space.focused ? 0.8 : space.visible ? 0.4 : 0
    layer?.borderWidth = borderAlpha > 0 ? capsuleBorderWidth : 0
    layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(borderAlpha).cgColor
    let status = space.focused ? "Focused" : space.visible ? "Visible" : "Not visible"
    let accessibilityLabel = "Space \(space.title) · \(status)"
    toolTip = "\(accessibilityLabel) · Right-click to close"
    setAccessibilityElement(true)
    setAccessibilityRole(.group)
    setAccessibilityLabel(accessibilityLabel)
    let spaceButton = SpaceButton(
      frame: NSRect(
        x: 0, y: 0, width: label.frame.maxX + spaceLabelIconGap, height: capsuleHeight))
    spaceButton.capsule = self
    spaceButton.toolTip = toolTip
    spaceButton.setAccessibilityLabel("Switch to Space \(space.title)")
    addSubview(spaceButton)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func hitTest(_ point: NSPoint) -> NSView? {
    guard let hit = super.hitTest(point) else { return nil }
    if hit is WindowChip || hit is SpaceButton { return hit }
    return self
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  override func mouseDown(with event: NSEvent) { select() }
  override func rightMouseDown(with event: NSEvent) { controller?.perform(.closeSpace(spaceID)) }

  @discardableResult
  func select() -> Bool { controller?.perform(.selectSpace(spaceID)) ?? false }
}

private final class SpaceButton: NSView {
  weak var capsule: SpaceCapsule?

  override init(frame: NSRect) {
    super.init(frame: frame)
    setAccessibilityElement(true)
    setAccessibilityRole(.button)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  override func mouseDown(with event: NSEvent) { capsule?.select() }

  override func accessibilityPerformPress() -> Bool {
    capsule?.select() ?? false
  }
}

private final class WindowChip: NSView {
  private let model: TileWindow
  private weak var controller: BarController?
  private let icon: NSImage
  private var pressed = false

  init(model: TileWindow, controller: BarController) {
    self.model = model
    self.controller = controller
    icon =
      NSRunningApplication(processIdentifier: model.pid)?.icon
      ?? NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)
      ?? NSImage(size: NSSize(width: windowIconSize, height: windowIconSize))
    super.init(
      frame: NSRect(
        x: 0, y: 0, width: windowButtonSize, height: min(windowButtonSize, capsuleHeight)))
    var name = model.name
    if model.minimized { name += " · Minimized" }
    if model.floating { name += " · Floating" }
    toolTip = name
    setAccessibilityElement(true)
    setAccessibilityRole(.button)
    setAccessibilityLabel(name)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func draw(_ dirtyRect: NSRect) {
    let iconSize = min(windowIconSize, bounds.width, bounds.height)
    let iconRect = NSRect(
      x: bounds.midX - iconSize / 2, y: bounds.midY - iconSize / 2,
      width: iconSize, height: iconSize)
    icon.draw(
      in: iconRect, from: .zero, operation: .sourceOver,
      fraction: model.minimized ? 0.4 : 1)
    if model.floating {
      NSColor.secondaryLabelColor.setFill()
      NSBezierPath(
        roundedRect: NSRect(
          x: bounds.midX - floatingIndicatorWidth / 2, y: floatingIndicatorBottomPadding,
          width: floatingIndicatorWidth, height: floatingIndicatorHeight),
        xRadius: floatingIndicatorHeight / 2, yRadius: floatingIndicatorHeight / 2
      ).fill()
    }
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func accessibilityPerformPress() -> Bool {
    controller?.perform(.focusWindow(model.identity)) ?? false
  }

  override func mouseDown(with event: NSEvent) {
    guard controller?.canInteract == true else { return }
    pressed = true
    controller?.beginPointerTracking()
  }

  override func mouseUp(with event: NSEvent) {
    guard pressed else { return }
    pressed = false
    if bounds.contains(convert(event.locationInWindow, from: nil)) {
      _ = accessibilityPerformPress()
    }
    controller?.endPointerTracking()
  }
}
