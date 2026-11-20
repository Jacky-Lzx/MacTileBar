import Foundation
import XCTest
@testable import MacTileBar

final class WindowListingTests: XCTestCase {
  private func window(
    id: UInt32 = 90, space: Int = 1, hasAX: Bool = false, visible: Bool? = false,
    minimized: Bool = false, hidden: Bool = false, root: Bool = true, fullscreen: Bool = false
  ) -> TileWindow {
    TileWindow(
      id: id, pid: 896, app: "Example", title: "", space: space,
      root: root, minimized: minimized, hidden: hidden, floating: false,
      fullscreen: fullscreen, hasAX: hasAX, focused: false, visible: visible)
  }

  func testFiltersUnreachableInvisibleWindowOnVisibleSpace() {
    XCTAssertFalse(window().isListed(onVisibleSpace: true))
  }

  func testKeepsOtherSpaceAndMinimizedWindowsWithoutAXReferences() {
    XCTAssertTrue(window().isListed(onVisibleSpace: false, isOrderedIn: { _ in true }))
    XCTAssertTrue(window().isListed(onVisibleSpace: false, isOrderedIn: { _ in nil }))
    XCTAssertTrue(window(minimized: true).isListed(onVisibleSpace: true, isOrderedIn: { _ in false }))
  }

  func testKeepsWindowsWithEvidenceOfAvailability() {
    XCTAssertTrue(window(hasAX: true).isListed(onVisibleSpace: true))
    XCTAssertTrue(window(visible: true).isListed(onVisibleSpace: true))
    XCTAssertTrue(window(visible: nil).isListed(onVisibleSpace: true))
  }

  func testExistingHiddenFullscreenAndChildExclusionsStillApply() {
    XCTAssertFalse(window(hasAX: true, hidden: true).isListed(onVisibleSpace: false))
    XCTAssertFalse(window(hasAX: true, root: false).isListed(onVisibleSpace: false))
    XCTAssertFalse(window(hasAX: true, fullscreen: true).isListed(onVisibleSpace: true))
  }

  func testSnapshotExcludesOrderedOutWindowAfterSwitchingSpaces() {
    let spaces = (1...2).map { index in
      Space(
        id: UInt64(index), uuid: "space-\(index)", index: index, label: "", display: 1,
        focused: index == 2, visible: index == 2, fullscreen: false)
    }
    let snapshot = Snapshot(
      displays: [], spaces: spaces,
      windows: [window(), window(id: 91), window(id: 92, minimized: true),
                window(id: 93, space: 2), window(id: 94, hasAX: true)],
      reservationIssue: nil,
      isOrderedIn: { $0 == 91 })
    XCTAssertEqual(snapshot.listedWindows.map(\.id), [91, 92, 94])
  }

  func testDecodesVisibilityAndAllowsOlderQueryDataWithoutIt() throws {
    let data = Data("""
      {"id":90,"pid":896,"app":"Bitwarden","title":"","space":1,
       "root-window":true,"is-minimized":false,"is-hidden":false,"is-floating":false,
       "is-native-fullscreen":false,"has-ax-reference":false,"is-visible":false}
      """.utf8)
    let decoder = JSONDecoder()
    XCTAssertFalse(try decoder.decode(TileWindow.self, from: data).isListed(onVisibleSpace: true))
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    object.removeValue(forKey: "is-visible")
    let legacy = try decoder.decode(TileWindow.self, from: JSONSerialization.data(withJSONObject: object))
    XCTAssertNil(legacy.visible)
    XCTAssertTrue(legacy.isListed(onVisibleSpace: true))
  }
}
