import AppKit

final class BarController: NSObject, NSApplicationDelegate {
  private static let reservationPreference = "reservesBarHeight"

  private struct Group: Equatable {
    let space: Space
    let windows: [TileWindow]
  }

  private struct Strip: Equatable {
    let groups: [Group]
    let status: String?
  }

  private let backend = Yabai()
  private let worker = DispatchQueue(label: "local.mactilebar.yabai", qos: .userInitiated)
  private var timer: Timer?
  private var statusItem: NSStatusItem?
  private var observers: [NSObjectProtocol] = []
  private var panels: [UInt32: BarPanel] = [:]
  private var strips: [UInt32: Strip] = [:]
  private var snapshot: Snapshot?
  private var connectionError: String?
  private var actionError: String?
  private var querying = false
  private var acting = false
  private var pointerTracking = false
  private var statusTitle: String?
  private var statusIssue: String?
  private var statusReservationEnabled: Bool?
  private var reservesBarHeight: Bool = {
    let defaults = UserDefaults.standard
    defaults.register(defaults: [reservationPreference: true])
    return defaults.bool(forKey: reservationPreference)
  }()
  private var reservationRevision: UInt = 0
  private var terminating = false

  private var reservationRequest: ReservationRequest {
    ReservationRequest(
      height: reservesBarHeight ? Int(ceil(barHeight)) : nil, revision: reservationRevision)
  }

  var canInteract: Bool { snapshot != nil && connectionError == nil && !acting && !terminating }

  func applicationDidFinishLaunching(_ notification: Notification) {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didWakeNotification] {
      let observer = NSWorkspace.shared.notificationCenter.addObserver(
        forName: name, object: nil, queue: .main
      ) { [weak self] _ in
        self?.refresh()
      }
      observers.append(observer)
    }
    NotificationCenter.default.addObserver(
      self, selector: #selector(screenChanged),
      name: NSApplication.didChangeScreenParametersNotification, object: nil)
    let timer = Timer(timeInterval: 0.75, repeats: true) { [weak self] _ in self?.refresh() }
    self.timer = timer
    RunLoop.main.add(timer, forMode: .common)
    render()
    refresh()
  }

  func applicationWillTerminate(_ notification: Notification) {
    timer?.invalidate()
    observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
    NotificationCenter.default.removeObserver(self)
  }

  func applicationShouldTerminate(_ application: NSApplication) -> NSApplication.TerminateReply {
    guard !terminating else { return .terminateLater }
    terminating = true
    worker.async { [backend] in
      do {
        try backend.releaseReservation()
      } catch {
        NSLog("MacTileBar: Could not restore yabai external_bar: %@", error.localizedDescription)
      }
      DispatchQueue.main.async { application.reply(toApplicationShouldTerminate: true) }
    }
    return .terminateLater
  }

  @objc private func screenChanged() {
    render()
    refresh()
  }

  @objc private func refresh() {
    guard !querying, !acting, !terminating else { return }
    querying = true
    let reservation = reservationRequest
    worker.async { [weak self, backend] in
      let result = Result { try backend.snapshot(reserving: reservation) }
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.querying = false
        guard !self.acting, !self.terminating else { return }
        self.apply(result)
        if reservation != self.reservationRequest { self.refresh() }
      }
    }
  }

  @discardableResult
  func perform(_ action: BarAction) -> Bool {
    guard canInteract else { return false }
    acting = true
    actionError = nil
    let reservation = reservationRequest
    worker.async { [weak self, backend] in
      let operation = Result { try backend.perform(action) }
      let snapshot = Result { try backend.snapshot(reserving: reservation) }
      DispatchQueue.main.async { [weak self] in
        guard let self, !self.terminating else { return }
        self.acting = false
        if case .failure(let error) = operation { self.actionError = error.localizedDescription }
        self.apply(snapshot)
        if reservation != self.reservationRequest { self.refresh() }
      }
    }
    return true
  }

  private func apply(_ result: Result<Snapshot, Error>) {
    switch result {
    case .success(let value):
      snapshot = value
      connectionError = nil
    case .failure(let error):
      connectionError = error.localizedDescription
    }
    render()
  }

  func beginPointerTracking() { pointerTracking = true }

  func endPointerTracking() {
    pointerTracking = false
    DispatchQueue.main.async { [weak self] in self?.render() }
  }

  private func render() {
    updateStatus()
    guard !pointerTracking else { return }
    let screens = NSScreen.screens
    let screenIDs = Set(screens.compactMap { displayID($0) })
    for id in Set(panels.keys).subtracting(screenIDs) {
      panels.removeValue(forKey: id)?.close()
      strips.removeValue(forKey: id)
    }

    let windowsBySpace = Dictionary(grouping: snapshot?.windows.filter(\.listed) ?? [], by: \.space)
    for screen in screens {
      guard let id = displayID(screen) else { continue }
      let display = snapshot?.displays.first { $0.id == id }
      let spaces = snapshot?.desktops.filter { $0.display == display?.index } ?? []
      let onFullscreen =
        snapshot?.spaces.contains { $0.display == display?.index && $0.visible && $0.fullscreen }
        == true

      if onFullscreen || (spaces.isEmpty && id != CGMainDisplayID()) {
        panels[id]?.orderOut(nil)
        continue
      }

      let groups = spaces.map { space in
        Group(space: space, windows: (windowsBySpace[space.index] ?? []).sorted { $0.id < $1.id })
      }
      let status: String?
      if connectionError != nil {
        status = "yabai offline"
      } else if snapshot == nil {
        status = "Connecting to yabai…"
      } else if groups.isEmpty {
        status = "No Spaces available"
      } else {
        status = nil
      }

      let strip = Strip(groups: groups, status: status)
      let panel = panels[id] ?? BarPanel()
      panels[id] = panel
      if strips[id] != strip {
        updateStrip(strip, in: panel)
        strips[id] = strip
      }

      guard let scroll = panel.contentView as? StripScrollView, let document = scroll.documentView
      else { continue }
      let usable = screen.visibleFrame
      let width = min(document.frame.width, usable.width)
      let frame = NSRect(
        x: floor(usable.midX - width / 2), y: usable.maxY - barHeight,
        width: width, height: barHeight)
      if panel.frame != frame { panel.setFrame(frame, display: true) }
      if !panel.isVisible { panel.orderFrontRegardless() }
      PanelSpaces.reconcile(windowNumber: panel.windowNumber, desktops: spaces)
    }
  }

  private func updateStrip(_ strip: Strip, in panel: BarPanel) {
    let scroll: StripScrollView
    if let existing = panel.contentView as? StripScrollView {
      scroll = existing
    } else {
      scroll = StripScrollView(frame: .zero)
      scroll.drawsBackground = false
      scroll.horizontalScrollElasticity = .none
      scroll.verticalScrollElasticity = .none
      panel.contentView = scroll
    }

    let offset = scroll.contentView.bounds.minX
    let document = NSView(frame: .zero)
    var x: CGFloat = 0
    var views: [NSView] = []
    if let status = strip.status { views.append(statusCapsule(status)) }
    for group in strip.groups {
      let view = SpaceCapsule(space: group.space, windows: group.windows, controller: self)
      view.alphaValue = connectionError == nil ? 1 : 0.58
      views.append(view)
    }
    for view in views {
      view.frame.origin = NSPoint(x: x, y: (barHeight - view.frame.height) / 2)
      document.addSubview(view)
      x = view.frame.maxX + capsuleSpacing
    }
    document.setFrameSize(NSSize(width: max(1, x - capsuleSpacing), height: barHeight))
    scroll.documentView = document
    let point = NSPoint(x: offset, y: 0)
    scroll.contentView.scroll(
      to: scroll.contentView.constrainBoundsRect(NSRect(origin: point, size: scroll.contentSize))
        .origin)
    scroll.reflectScrolledClipView(scroll.contentView)
  }

  @objc private func toggleReservation() {
    reservesBarHeight.toggle()
    UserDefaults.standard.set(reservesBarHeight, forKey: Self.reservationPreference)
    reservationRevision &+= 1
    updateStatus()
    refresh()
  }

  private func updateStatus() {
    let status = connectionError != nil ? "yabai offline" : snapshot != nil ? "yabai connected" : "Connecting to yabai…"
    let issue = connectionError ?? actionError ?? snapshot?.reservationIssue
    guard
      status != statusTitle || issue != statusIssue || reservesBarHeight != statusReservationEnabled
    else { return }
    statusTitle = status
    statusIssue = issue
    statusReservationEnabled = reservesBarHeight
    let icon = issue == nil ? "rectangle.split.3x1" : "exclamationmark.circle"
    statusItem?.button?.image = NSImage(
      systemSymbolName: icon, accessibilityDescription: "MacTileBar")
    statusItem?.button?.toolTip = issue ?? "MacTileBar"

    let menu = NSMenu()
    menu.addItem(NSMenuItem(title: status, action: nil, keyEquivalent: ""))
    if let issue {
      let firstLine = issue.split(separator: "\n").first.map(String.init) ?? issue
      let item = NSMenuItem(title: String(firstLine.prefix(100)), action: nil, keyEquivalent: "")
      item.toolTip = issue
      menu.addItem(item)
    }
    menu.addItem(.separator())
    let reservationItem = NSMenuItem(
      title: "Automatically Reserve Bar Height", action: #selector(toggleReservation), keyEquivalent: "")
    reservationItem.target = self
    reservationItem.state = reservesBarHeight ? .on : .off
    menu.addItem(reservationItem)
    let refreshItem = NSMenuItem(title: "Refresh Now", action: #selector(refresh), keyEquivalent: "r")
    refreshItem.target = self
    menu.addItem(refreshItem)
    menu.addItem(
      NSMenuItem(
        title: "Quit MacTileBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    statusItem?.menu = menu
  }

  private func displayID(_ screen: NSScreen) -> UInt32? {
    (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
  }
}
