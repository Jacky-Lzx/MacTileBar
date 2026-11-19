import Darwin
import Foundation

struct Display: Decodable {
  let id: UInt32
  let index: Int
}

struct Space: Decodable, Equatable {
  struct ID: Equatable {
    let id: UInt64
    let uuid: String
  }

  let id: UInt64
  let uuid: String
  let index: Int
  let label: String
  let display: Int
  let focused: Bool
  let visible: Bool
  let fullscreen: Bool

  var identity: ID { ID(id: id, uuid: uuid) }
  var title: String { label.isEmpty ? String(index) : label }

  enum CodingKeys: String, CodingKey {
    case id, uuid, index, label, display
    case focused = "has-focus"
    case visible = "is-visible"
    case fullscreen = "is-native-fullscreen"
  }
}

struct TileWindow: Decodable, Equatable {
  struct ID: Equatable {
    let id: UInt32
    let pid: Int32
  }

  let id: UInt32
  let pid: Int32
  let app: String
  let title: String
  let space: Int
  let root: Bool
  let minimized: Bool
  let hidden: Bool
  let floating: Bool
  let fullscreen: Bool
  let hasAX: Bool
  let focused: Bool?
  let visible: Bool?

  var identity: ID { ID(id: id, pid: pid) }
  var name: String { title.isEmpty ? app : "\(app) — \(title)" }
  var listed: Bool { root && !hidden && !fullscreen }

  func isListed(onVisibleSpace: Bool) -> Bool {
    // Off-Space windows may acquire their AX reference only after switching Spaces.
    listed && (hasAX || minimized || visible != false || !onVisibleSpace)
  }

  enum CodingKeys: String, CodingKey {
    case id, pid, app, title, space
    case root = "root-window"
    case minimized = "is-minimized"
    case hidden = "is-hidden"
    case floating = "is-floating"
    case fullscreen = "is-native-fullscreen"
    case hasAX = "has-ax-reference"
    case focused = "has-focus"
    case visible = "is-visible"
  }
}

struct ApplicationFocus: Equatable {
  let pid: Int32?
  let name: String
  let display: Int
}

struct Snapshot {
  let displays: [Display]
  let spaces: [Space]
  let windows: [TileWindow]
  let reservationIssue: String?

  var desktops: [Space] { spaces.filter { !$0.fullscreen }.sorted { $0.index < $1.index } }

  var listedWindows: [TileWindow] {
    let visibleSpaces = Set(spaces.filter(\.visible).map(\.index))
    return windows.filter { $0.isListed(onVisibleSpace: visibleSpaces.contains($0.space)) }
  }

  func applicationFocus(pid: Int32?, name: String) -> ApplicationFocus? {
    guard let space = spaces.first(where: \.focused) else { return nil }
    if let window = windows.first(where: { $0.focused == true }) {
      // Separate yabai queries can straddle a focus change. Wait for a consistent pair.
      guard window.pid == pid, window.space == space.index else { return nil }
    }
    return ApplicationFocus(pid: pid, name: name, display: space.display)
  }
}

enum BarAction {
  case selectSpace(Space.ID)
  case closeSpace(Space.ID)
  case focusWindow(TileWindow.ID)
}

struct YabaiError: LocalizedError {
  let message: String
  var errorDescription: String? { message }
}

final class Yabai {
  // All methods are called on the controller's serial background queue.
  private let env = ProcessInfo.processInfo.environment
  private let decoder = JSONDecoder()
  private let reservation = BarReservation(
    journal: URL.applicationSupportDirectory
      .appendingPathComponent("MacTileBar", isDirectory: true)
      .appendingPathComponent("external-bar.json")
  )
  private var reservationIssue: String?
  private var reservationRequest: ReservationRequest?
  private var reservationSocket: String?
  private var reapplyReservation = true
  private var nextConfigRead: TimeInterval = 0

  func snapshot(reserving request: ReservationRequest) throws -> Snapshot {
    do {
      let displays: [Display] = try query("displays")
      let spaces: [Space] = try query("spaces")
      let windows: [TileWindow] = try query("windows")
      syncReservation(request)
      return Snapshot(
        displays: displays, spaces: spaces, windows: windows, reservationIssue: reservationIssue)
    } catch {
      nextConfigRead = 0
      if reservationSocket == nil { reapplyReservation = true }
      throw error
    }
  }

  private func syncReservation(_ request: ReservationRequest) {
    let socket = socketIdentity()
    let now = ProcessInfo.processInfo.systemUptime
    if request != reservationRequest || socket != reservationSocket {
      reservationRequest = request
      reservationSocket = socket
      reapplyReservation = true
      nextConfigRead = 0
    }
    guard now >= nextConfigRead else { return }
    nextConfigRead = now + 5

    do {
      if let height = request.height {
        let current = try readExternalBar()
        let applied = try reservation.update(
          current: current, socket: socket, height: height,
          reapply: reapplyReservation, write: writeExternalBar)
        reservationIssue = applied ? nil : "External changes detected. Automatic bar reservation is paused. Turn the option off and on again to resume."
      } else {
        try releaseReservation()
        reservationIssue = nil
      }
      reapplyReservation = false
    } catch {
      reservationIssue = "Could not sync the bar height. \(error.localizedDescription)"
    }
  }

  func releaseReservation() throws {
    try reservation.release(
      socket: socketIdentity(), read: readExternalBar, write: writeExternalBar)
  }

  private func readExternalBar() throws -> ExternalBar {
    try ExternalBar(String(decoding: run(["config", "external_bar"]), as: UTF8.self))
  }

  private func writeExternalBar(_ value: ExternalBar) throws {
    try command(["config", "external_bar", value.description])
  }

  private func socketIdentity() -> String? {
    // A quick yabai restart can fall between polls without a failed CLI call.
    guard let user = env["USER"] else { return nil }
    var info = stat()
    guard lstat("/tmp/yabai_\(user).socket", &info) == 0 else { return nil }
    return
      "\(info.st_dev):\(info.st_ino):\(info.st_birthtimespec.tv_sec):\(info.st_birthtimespec.tv_nsec)"
  }

  func perform(_ action: BarAction) throws {
    switch action {
    case .selectSpace(let id):
      let space = try resolve(id, in: query("spaces"))
      if space.visible && !space.focused {
        // space --focus treats an already visible desktop specially.
        try command(["display", "--focus", String(space.display)])
      } else if !space.focused {
        try command(["space", "--focus", String(space.index)])
      }
    case .closeSpace(let id):
      let spaces: [Space] = try query("spaces")
      let space = try resolve(id, in: spaces)
      guard
        spaces.contains(where: {
          $0.display == space.display && !$0.fullscreen && $0.id != space.id
        })
      else {
        throw YabaiError(message: "Cannot close the last desktop Space on this display.")
      }
      try command(["space", String(space.index), "--destroy"])
    case .focusWindow(let id):
      let window = try resolve(id, in: query("windows"))
      try focus(window)
    }
  }

  private func focus(_ window: TileWindow) throws {
    let spaces: [Space] = try query("spaces")
    guard let space = spaces.first(where: { $0.index == window.space && !$0.fullscreen }) else {
      throw YabaiError(message: "The window has moved to a different Space.")
    }
    guard window.isListed(onVisibleSpace: space.visible) else {
      throw YabaiError(message: "The target window is no longer available.")
    }
    if !space.visible {
      try command(["space", "--focus", String(space.index)])
    }
    if !window.hasAX {
      let deadline = ProcessInfo.processInfo.systemUptime + 1
      while ProcessInfo.processInfo.systemUptime < deadline {
        let current = try resolve(window.identity, in: query("windows"))
        if current.hasAX {
          try command(["window", String(current.id), "--focus"])
          return
        }
        Thread.sleep(forTimeInterval: 0.05)
      }
      throw YabaiError(message: "yabai cannot access this window yet.")
    }
    try command(["window", String(window.id), "--focus"])
  }

  private func resolve(_ id: Space.ID, in spaces: [Space]) throws -> Space {
    guard let space = spaces.first(where: { $0.identity == id && !$0.fullscreen }) else {
      throw YabaiError(message: "The target Space has changed.")
    }
    return space
  }

  private func resolve(_ id: TileWindow.ID, in windows: [TileWindow]) throws -> TileWindow {
    guard let window = windows.first(where: { $0.identity == id && $0.listed }) else {
      throw YabaiError(message: "The target window has changed.")
    }
    return window
  }

  private func query<T: Decodable>(_ domain: String) throws -> [T] {
    let data = try run(["query", "--\(domain)"])
    do {
      return try decoder.decode([T].self, from: data)
    } catch {
      throw YabaiError(message: "Could not parse the yabai \(domain) query result.\n\(error)")
    }
  }

  private func command(_ arguments: [String]) throws {
    _ = try run(arguments)
  }

  private func run(_ arguments: [String]) throws -> Data {
    let candidates =
      env["MACTILEBAR_YABAI"].map { [$0] }
      ?? (["/opt/homebrew/bin/yabai", "/usr/local/bin/yabai"]
        + (env["PATH"] ?? "").split(separator: ":").map { String($0) + "/yabai" })
    guard
      let executable = candidates.first(where: {
        $0.hasPrefix("/") && FileManager.default.isExecutableFile(atPath: $0)
      })
    else {
      throw YabaiError(message: "Could not find the yabai executable.")
    }

    let output = Pipe()
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = ["-m"] + arguments
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = output
    process.standardError = output
    try process.run()

    // Drain the pipe before waiting so a long window listing cannot fill it.
    let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
    timer.schedule(deadline: .now() + 2)
    timer.setEventHandler {
      if process.isRunning { kill(process.processIdentifier, SIGKILL) }
    }
    timer.resume()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    timer.cancel()

    guard process.terminationStatus == 0 else {
      if process.terminationReason == .uncaughtSignal && process.terminationStatus == SIGKILL {
        throw YabaiError(message: "The yabai command timed out.")
      }
      let detail = String(decoding: data, as: UTF8.self).trimmingCharacters(
        in: .whitespacesAndNewlines)
      throw YabaiError(
        message: detail.isEmpty ? "The yabai command failed (exit code \(process.terminationStatus))." : detail)
    }
    return data
  }
}
