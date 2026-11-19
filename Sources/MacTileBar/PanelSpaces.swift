import Darwin
import Foundation

enum PanelSpaces {
  private typealias GetConnection = @convention(c) () -> Int32
  private typealias GetWindowOwner =
    @convention(c) (Int32, UInt32, UnsafeMutablePointer<Int32>) -> Int32
  private typealias CopyWindowSpaces = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
  private typealias AddWindowsToSpaces = @convention(c) (Int32, CFArray, CFArray) -> Int32

  private struct API {
    let connection: GetConnection
    let windowOwner: GetWindowOwner
    let windowSpaces: CopyWindowSpaces
    let addWindows: AddWindowsToSpaces
  }

  private static let api: API? = {
    let handle = dlopen(nil, RTLD_LAZY)
    guard let connection = dlsym(handle, "SLSMainConnectionID"),
      let owner = dlsym(handle, "SLSGetWindowOwner"),
      let spaces = dlsym(handle, "SLSCopySpacesForWindows"),
      let add = dlsym(handle, "SLSAddWindowsToSpaces")
    else { return nil }
    return API(
      connection: unsafeBitCast(connection, to: GetConnection.self),
      windowOwner: unsafeBitCast(owner, to: GetWindowOwner.self),
      windowSpaces: unsafeBitCast(spaces, to: CopyWindowSpaces.self),
      addWindows: unsafeBitCast(add, to: AddWindowsToSpaces.self))
  }()

  static func reconcile(windowNumber: Int, desktops: [Space]) {
    guard !desktops.isEmpty, let api, let windowID = UInt32(exactly: windowNumber), windowID != 0
    else { return }
    let connection = api.connection()
    var owner: Int32 = 0
    guard api.windowOwner(connection, windowID, &owner) == 0, owner == connection else { return }

    let windows = [NSNumber(value: windowID)] as CFArray
    guard
      let memberships = api.windowSpaces(connection, 0x7, windows)?.takeRetainedValue()
        as? [NSNumber]
    else {
      return
    }
    let current = Set(memberships.map(\.uint64Value))
    let missing = desktops.map(\.id).filter { !current.contains($0) }
    guard !missing.isEmpty else { return }

    // After Space transitions AppKit can keep isVisible and canJoinAllSpaces
    // set even though WindowServer has dropped individual memberships.
    _ = api.addWindows(connection, windows, missing.map { NSNumber(value: $0) } as CFArray)
  }
}
