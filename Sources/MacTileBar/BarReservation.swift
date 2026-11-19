import Foundation

struct ExternalBar: Codable, Equatable, CustomStringConvertible {
  enum Mode: String, Codable {
    case off, main, all
  }

  let mode: Mode
  let top: Int
  let bottom: Int

  init(mode: Mode, top: Int, bottom: Int) {
    self.mode = mode
    self.top = top
    self.bottom = bottom
  }

  init(_ value: String) throws {
    let fields = value.trimmingCharacters(in: .whitespacesAndNewlines)
      .split(separator: ":", omittingEmptySubsequences: false)
    guard fields.count == 3, let mode = Mode(rawValue: String(fields[0])),
      let top = Int(fields[1]), let bottom = Int(fields[2])
    else {
      throw YabaiError(message: "Could not parse the yabai external_bar setting (\(value)).")
    }
    self.init(mode: mode, top: top, bottom: bottom)
  }

  var description: String { "\(mode.rawValue):\(top):\(bottom)" }

  func reserving(_ height: Int) -> Self {
    Self(mode: .all, top: max(height, mode == .off ? 0 : top), bottom: mode == .off ? 0 : bottom)
  }
}

struct ReservationRequest: Equatable {
  let height: Int?
  let revision: UInt
}

/// Used only on the yabai queue. The on-disk record survives abnormal exits.
final class BarReservation {
  private struct Lease: Codable {
    let socket: String?
    let original: ExternalBar
    let applied: ExternalBar
    // While resizing, yabai may still have the previously applied value.
    var previous: ExternalBar?

    func owns(_ value: ExternalBar, socket currentSocket: String?) -> Bool {
      if let socket, let currentSocket, socket != currentSocket { return false }
      return value == applied || value == previous
    }
  }

  private let journal: URL
  private var lastObserved: ExternalBar?
  private var yielded = false

  init(journal: URL) {
    self.journal = journal
  }

  func update(
    current: ExternalBar, socket: String?, height: Int, reapply: Bool,
    write: (ExternalBar) throws -> Void
  ) throws -> Bool {
    var lease = try load()
    if lease?.owns(current, socket: socket) != true, lease != nil {
      try clear()
      lease = nil
    }

    if reapply || lastObserved == nil {
      yielded = false
    } else if lease == nil && current != lastObserved {
      yielded = true
    }
    lastObserved = current
    guard !yielded else { return false }

    let original = lease?.original ?? current
    let desired = original.reserving(height)
    if desired == original {
      if current != original { try write(original) }
      if lease != nil { try clear() }
    } else if current != desired {
      let next = Lease(
        socket: socket, original: original, applied: desired,
        previous: lease == nil ? nil : current)
      // Record ownership before setting yabai so a force quit cannot lose the baseline.
      try save(next)
      try write(desired)
      if next.previous != nil {
        try save(Lease(socket: socket, original: original, applied: desired))
      }
    } else if var lease, lease.applied == current, lease.previous != nil {
      lease.previous = nil
      try save(lease)
    }
    lastObserved = desired
    return true
  }

  func release(socket: String?, read: () throws -> ExternalBar, write: (ExternalBar) throws -> Void)
    throws
  {
    guard let lease = try load() else { return }
    let current = try read()
    if lease.owns(current, socket: socket) && current != lease.original {
      try write(lease.original)
    }
    try clear()
  }

  private func load() throws -> Lease? {
    do {
      return try JSONDecoder().decode(Lease.self, from: Data(contentsOf: journal))
    } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
      return nil
    }
  }

  private func save(_ lease: Lease) throws {
    try FileManager.default.createDirectory(
      at: journal.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONEncoder().encode(lease).write(to: journal, options: .atomic)
  }

  private func clear() throws {
    try FileManager.default.removeItem(at: journal)
  }
}
