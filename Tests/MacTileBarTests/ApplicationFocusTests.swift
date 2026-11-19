import XCTest
@testable import MacTileBar

final class ApplicationFocusTests: XCTestCase {
  private func snapshot(focusedSpace: Int, windowSpace: Int?, windowPID: Int32 = 42) -> Snapshot {
    let spaces = (1...2).map { index in
      Space(
        id: UInt64(index), uuid: "space-\(index)", index: index, label: "", display: index,
        focused: index == focusedSpace, visible: true, fullscreen: false)
    }
    let windows = windowSpace.map { space in
      [TileWindow(
        id: 1, pid: windowPID, app: "Example", title: "Window", space: space,
        root: true, minimized: false, hidden: false, floating: false, fullscreen: false,
        hasAX: true, focused: true)]
    } ?? []
    return Snapshot(displays: [], spaces: spaces, windows: windows, reservationIssue: nil)
  }

  func testApplicationAndDisplayChangeTogether() {
    let before = snapshot(focusedSpace: 1, windowSpace: 1, windowPID: 41)
    let after = snapshot(focusedSpace: 2, windowSpace: 2)

    XCTAssertEqual(
      before.applicationFocus(pid: 41, name: "Previous"),
      ApplicationFocus(pid: 41, name: "Previous", display: 1))
    XCTAssertEqual(
      after.applicationFocus(pid: 42, name: "Example"),
      ApplicationFocus(pid: 42, name: "Example", display: 2))
  }

  func testRejectsNewApplicationWithOldFocusedWindow() {
    let value = snapshot(focusedSpace: 1, windowSpace: 1, windowPID: 41)
    XCTAssertNil(value.applicationFocus(pid: 42, name: "Example"))
  }

  func testRejectsWindowAndSpaceFromDifferentFocusStates() {
    let value = snapshot(focusedSpace: 1, windowSpace: 2)
    XCTAssertNil(value.applicationFocus(pid: 42, name: "Example"))
  }

  func testWindowlessApplicationUsesFocusedSpace() {
    let value = snapshot(focusedSpace: 2, windowSpace: nil)
    XCTAssertEqual(
      value.applicationFocus(pid: 42, name: "Finder"),
      ApplicationFocus(pid: 42, name: "Finder", display: 2))
  }
}
