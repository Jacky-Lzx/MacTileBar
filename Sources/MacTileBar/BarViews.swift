import AppKit

var barAppearance = BarAppearance()
var barHeight: CGFloat { barAppearance.barHeight }
var capsuleSpacing: CGFloat { barAppearance.capsuleSpacing }
var barEdgePadding: CGFloat { barAppearance.barEdgePadding }
var barSectionSpacing: CGFloat { barAppearance.barSectionSpacing }

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
    animationBehavior = .none
    hidesOnDeactivate = false
    level = .floating
    collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
  }
}

func material(behind content: NSView, tint: NSColor? = nil) -> NSGlassEffectView {
  content.autoresizingMask = [.width, .height]
  let glass = NSGlassEffectView(frame: content.frame)
  glass.cornerRadius = barAppearance.capsuleHeight / 2
  glass.tintColor = tint
  glass.contentView = content
  return glass
}

func statusCapsule(
  _ title: String, application: NSRunningApplication? = nil, textColor: NSColor? = nil
) -> NSView {
  let label = NSTextField(labelWithString: title)
  label.font = .systemFont(ofSize: barAppearance.statusFontSize, weight: .medium)
  label.textColor = textColor ?? (application == nil ? .secondaryLabelColor : .labelColor)
  label.lineBreakMode = .byTruncatingTail
  label.sizeToFit()
  let icon = application?.icon
  if application != nil { label.frame.size.width = min(label.frame.width, barAppearance.focusedAppMaxTextWidth) }
  let iconWidth = icon == nil ? 0 : barAppearance.focusedAppIconSize + barAppearance.focusedAppIconSpacing
  label.frame.origin = NSPoint(
    x: barAppearance.statusHorizontalPadding + iconWidth, y: (barAppearance.capsuleHeight - label.frame.height) / 2)
  label.autoresizingMask = [.width]
  let content = NSView(
    frame: NSRect(
      x: 0, y: 0, width: label.frame.maxX + barAppearance.statusHorizontalPadding, height: barAppearance.capsuleHeight))
  content.addSubview(label)
  if let icon {
    let image = NSImageView(frame: NSRect(
      x: barAppearance.statusHorizontalPadding, y: (barAppearance.capsuleHeight - barAppearance.focusedAppIconSize) / 2,
      width: barAppearance.focusedAppIconSize, height: barAppearance.focusedAppIconSize))
    image.image = icon
    image.imageScaling = .scaleProportionallyDown
    content.addSubview(image)
  }
  let capsule = material(behind: content)
  capsule.toolTip = title
  capsule.setAccessibilityLabel(title)
  return capsule
}

/// Keeps the middle section centered while reserving room for both side sections.
struct BarSectionFrames {
  let left: NSRect
  let center: NSRect
  let right: NSRect

  init(usable: NSRect, leftWidth: CGFloat, centerWidth: CGFloat, rightWidth: CGFloat) {
    let margin = min(barEdgePadding, usable.width / 2)
    let available = max(0, usable.width - 2 * margin)
    let gap = min(barSectionSpacing, available / 4)
    let sideLimit = max(0, (available - 2 * gap) / 3)
    let leftWidth = min(leftWidth, sideLimit)
    let rightWidth = min(rightWidth, sideLimit)
    let centerWidth = min(centerWidth, max(0, available - 2 * (max(leftWidth, rightWidth) + gap)))
    let y = usable.maxY - barHeight
    left = NSRect(x: usable.minX + margin, y: y, width: leftWidth, height: barHeight)
    center = NSRect(x: usable.midX - centerWidth / 2, y: y, width: centerWidth, height: barHeight)
    right = NSRect(x: usable.maxX - margin - rightWidth, y: y, width: rightWidth, height: barHeight)
  }
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
      ofSize: barAppearance.spaceFontSize, weight: space.focused ? .semibold : .medium)
    label.lineBreakMode = .byTruncatingTail
    label.sizeToFit()
    label.frame.size.width = min(barAppearance.spaceLabelMaxWidth, label.frame.width)
    label.frame.origin = NSPoint(
      x: barAppearance.spaceLeadingPadding, y: (barAppearance.capsuleHeight - label.frame.height) / 2)

    var x = label.frame.maxX + barAppearance.spaceLabelIconGap
    for chip in chips {
      chip.frame.origin = NSPoint(x: x, y: (barAppearance.capsuleHeight - chip.frame.height) / 2)
      x = chip.frame.maxX + barAppearance.windowButtonGap
    }
    let contentWidth = chips.last?.frame.maxX ?? label.frame.maxX
    // Empty Spaces keep symmetric padding around their label.
    let trailingPadding = chips.isEmpty ? barAppearance.spaceLeadingPadding : barAppearance.spaceTrailingPadding
    let frame = NSRect(
      x: 0, y: 0, width: contentWidth + trailingPadding, height: barAppearance.capsuleHeight)
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
    layer?.borderWidth = borderAlpha > 0 ? barAppearance.capsuleBorderWidth : 0
    layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(borderAlpha).cgColor
    let status = space.focused ? "Focused" : space.visible ? "Visible" : "Not visible"
    let accessibilityLabel = "Space \(space.title) · \(status)"
    toolTip = "\(accessibilityLabel) · Right-click to close"
    setAccessibilityElement(true)
    setAccessibilityRole(.group)
    setAccessibilityLabel(accessibilityLabel)
    let spaceButton = SpaceButton(
      frame: NSRect(
        x: 0, y: 0, width: label.frame.maxX + barAppearance.spaceLabelIconGap, height: barAppearance.capsuleHeight))
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
      ?? NSImage(size: NSSize(width: barAppearance.windowIconSize, height: barAppearance.windowIconSize))
    super.init(
      frame: NSRect(
        x: 0, y: 0, width: barAppearance.windowButtonSize, height: min(barAppearance.windowButtonSize, barAppearance.capsuleHeight)))
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
    let iconSize = min(barAppearance.windowIconSize, bounds.width, bounds.height)
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
          x: bounds.midX - barAppearance.floatingIndicatorWidth / 2, y: barAppearance.floatingIndicatorBottomPadding,
          width: barAppearance.floatingIndicatorWidth, height: barAppearance.floatingIndicatorHeight),
        xRadius: barAppearance.floatingIndicatorHeight / 2, yRadius: barAppearance.floatingIndicatorHeight / 2
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
