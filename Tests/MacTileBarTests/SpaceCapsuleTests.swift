import AppKit
import XCTest
@testable import MacTileBar

final class SpaceCapsuleTests: XCTestCase {
  @MainActor
  func testEmptySpaceMatchesSingleWindowWidth() throws {
    let configuration = ConfigurationFile(location: ConfigurationLocation(
      options: try LaunchOptions(arguments: []), environment: [:]))
    let controller = BarController(configurationFile: configuration)
    let space = Space(
      id: 1, uuid: "space-1", index: 1, label: "", display: 1,
      focused: false, visible: false, fullscreen: false)
    let window = TileWindow(
      id: 1, pid: 0, app: "Example", title: "", space: 1,
      root: true, minimized: false, hidden: false, floating: false,
      fullscreen: false, hasAX: true, focused: false, visible: false)

    let empty = SpaceCapsule(space: space, windows: [], controller: controller)
    let single = SpaceCapsule(space: space, windows: [window], controller: controller)

    XCTAssertEqual(empty.frame.width, single.frame.width)
  }
}
