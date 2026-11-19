import AppKit
import XCTest
@testable import MacTileBar

final class BarSectionFramesTests: XCTestCase {
  func testUnequalSidesKeepSpacesAtTheScreenCenter() {
    let usable = NSRect(x: -1920, y: 40, width: 1920, height: 1040)
    let frames = BarSectionFrames(
      usable: usable, leftWidth: 220, centerWidth: 500, rightWidth: 150)

    XCTAssertEqual(frames.center.midX, usable.midX)
    XCTAssertEqual(frames.center.width, 500)
    XCTAssertEqual(frames.left.minX, usable.minX + barEdgePadding)
    XCTAssertEqual(frames.right.maxX, usable.maxX - barEdgePadding)
    for frame in [frames.left, frames.center, frames.right] {
      XCTAssertEqual(frame.maxY, usable.maxY)
      XCTAssertEqual(frame.height, barHeight)
    }
  }

  func testOverflowingSectionsRemainSeparateAndInsideScreen() {
    for width: CGFloat in [0, 20, 320, 800] {
      let usable = NSRect(x: 100, y: 0, width: width, height: 600)
      let frames = BarSectionFrames(
        usable: usable, leftWidth: 500, centerWidth: 2000, rightWidth: 300)

      XCTAssertEqual(frames.center.midX, usable.midX, accuracy: 0.001)
      XCTAssertLessThanOrEqual(frames.left.maxX, frames.center.minX + 0.001)
      XCTAssertLessThanOrEqual(frames.center.maxX, frames.right.minX + 0.001)
      for frame in [frames.left, frames.center, frames.right] {
        XCTAssertGreaterThanOrEqual(frame.width, 0)
        XCTAssertGreaterThanOrEqual(frame.minX, usable.minX - 0.001)
        XCTAssertLessThanOrEqual(frame.maxX, usable.maxX + 0.001)
      }
    }
  }
}
