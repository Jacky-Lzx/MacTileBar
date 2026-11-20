import Darwin

enum WindowOrder {
  private typealias GetConnection = @convention(c) () -> Int32
  private typealias IsOrderedIn =
    @convention(c) (Int32, UInt32, UnsafeMutablePointer<UInt8>) -> Int32

  private static let api: (connection: GetConnection, isOrderedIn: IsOrderedIn)? = {
    let handle = dlopen(nil, RTLD_LAZY)
    guard let connection = dlsym(handle, "SLSMainConnectionID"),
      let orderedIn = dlsym(handle, "SLSWindowIsOrderedIn")
    else { return nil }
    return (
      unsafeBitCast(connection, to: GetConnection.self),
      unsafeBitCast(orderedIn, to: IsOrderedIn.self)
    )
  }()

  static func isOrderedIn(_ windowID: UInt32) -> Bool? {
    guard let api else { return nil }
    var value: UInt8 = 0
    guard api.isOrderedIn(api.connection(), windowID, &value) == 0 else { return nil }
    return value != 0
  }
}
