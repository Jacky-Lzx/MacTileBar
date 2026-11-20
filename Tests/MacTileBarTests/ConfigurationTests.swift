import AppKit
import XCTest
@testable import MacTileBar

final class ConfigurationTests: XCTestCase {
  private func temporaryURL() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    addTeardownBlock { try FileManager.default.removeItem(at: directory) }
    return directory.appendingPathComponent("config.toml")
  }

  private func file(at url: URL) throws -> ConfigurationFile {
    ConfigurationFile(location: ConfigurationLocation(
      options: try LaunchOptions(arguments: ["--config", url.path]), environment: [:]))
  }

  func testEmptyFileAndDocumentedExampleMatchDefaults() throws {
    XCTAssertEqual(try BarConfiguration.parse("# Defaults\n"), BarConfiguration())
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let example = try String(contentsOf: root.appendingPathComponent("config.example.toml"), encoding: .utf8)
    XCTAssertEqual(try BarConfiguration.parse(example), BarConfiguration())
  }

  func testPartialTablesAndStandardTOMLSyntax() throws {
    let configuration = try BarConfiguration.parse("""
      appearance.bar_height = 34
      appearance.capsule_height = 30
      [date]
      "format" = 'yyyy-MM-dd' # Quoted key and literal string.
      """)
    XCTAssertEqual(configuration.appearance.barHeight, 34)
  }

  func testPartialOverridesKeepOtherDefaults() throws {
    let configuration = try BarConfiguration.parse("""
      [appearance]
      bar_height = 34
      capsule_height = 30
      space_font_size = 12.5
      [date]
      format = 'yyyy-MM-dd'
      text_color = "#12345680" # Includes alpha.
      [behavior]
      refresh_interval = 1
      reserves_bar_height = false
      """)
    XCTAssertEqual(configuration.appearance.barHeight, 34)
    XCTAssertEqual(configuration.appearance.spaceFontSize, 12.5)
    XCTAssertEqual(configuration.appearance.windowIconSize, 18)
    XCTAssertEqual(configuration.date.format, "yyyy-MM-dd")
    XCTAssertEqual(configuration.date.color.alphaComponent, 128.0 / 255, accuracy: 0.001)
    XCTAssertEqual(configuration.behavior.refreshInterval, 1)
    XCTAssertEqual(configuration.behavior.reservesBarHeight, false)
  }

  func testRejectsUnknownKeysMalformedTOMLAndWrongTypes() {
    for text in [
      "unknown = 1", "[appearance]\nbar_heigth = 30", "[date]\ncolour = '#FFFFFF'",
      "[appearance", "[appearance]\nbar_height = 30\nbar_height = 32",
      "[appearance]\nbar_height = '30'", "[appearance]\nbar_height = true",
      "[behavior]\nreserves_bar_height = 1",
    ] {
      XCTAssertThrowsError(try BarConfiguration.parse(text), text)
    }
  }

  func testRejectsInvalidGeometryIntervalsAndColors() {
    for text in [
      "[appearance]\nbar_height = 0", "[appearance]\nbar_height = 20",
      "[appearance]\nbar_height = inf", "[appearance]\nbar_height = nan",
      "[appearance]\nbar_height = 1e30", "[appearance]\nspace_font_size = 0",
      "[appearance]\ncapsule_spacing = -1", "[behavior]\nrefresh_interval = 0",
      "[behavior]\nrefresh_interval = nan", "[date]\ntext_color = 'white'",
      "[date]\ntext_color = '#GGGGGG'", "[date]\nformat = ''",
    ] {
      XCTAssertThrowsError(try BarConfiguration.parse(text), text)
    }
  }

  func testReloadFailurePreservesLastValidConfigurationAndRecovers() throws {
    let url = try temporaryURL()
    let configuration = try file(at: url)
    try "[appearance]\nbar_height = 35".write(to: url, atomically: true, encoding: .utf8)
    XCTAssertTrue(configuration.reload())
    XCTAssertEqual(configuration.current.appearance.barHeight, 35)
    try "[appearance]\nbar_height = -1".write(to: url, atomically: true, encoding: .utf8)
    XCTAssertFalse(configuration.reload())
    XCTAssertEqual(configuration.current.appearance.barHeight, 35)
    XCTAssertTrue(configuration.issue?.contains("bar_height") == true)
    try "[appearance]\nbar_height = 40".write(to: url, atomically: true, encoding: .utf8)
    XCTAssertTrue(configuration.reload())
    XCTAssertEqual(configuration.current.appearance.barHeight, 40)
    XCTAssertNil(configuration.issue)
  }

  func testMissingDefaultFileUsesDefaultsButExplicitFileReportsError() throws {
    let url = try temporaryURL()
    let options = try LaunchOptions(arguments: [])
    let defaultFile = ConfigurationFile(location: ConfigurationLocation(
      options: options, environment: [:], home: url.deletingLastPathComponent()))
    XCTAssertTrue(defaultFile.reload())
    XCTAssertEqual(defaultFile.current, BarConfiguration())
    let explicitFile = try file(at: url)
    XCTAssertFalse(explicitFile.reload())
    XCTAssertNotNil(explicitFile.issue)
  }

  func testInvalidUTF8ReportsError() throws {
    let url = try temporaryURL()
    try Data([0xFF, 0xFE]).write(to: url)
    let configuration = try file(at: url)
    XCTAssertFalse(configuration.reload())
    XCTAssertTrue(configuration.issue?.contains("UTF-8") == true)
  }

  func testConfigurationPathPrecedenceAndExpansion() throws {
    let home = URL(fileURLWithPath: "/tmp/config-home", isDirectory: true)
    let directory = URL(fileURLWithPath: "/tmp/config-work", isDirectory: true)
    let environment = ["MACTILEBAR_CONFIG": "/tmp/environment.toml", "XDG_CONFIG_HOME": "/tmp/xdg"]
    let explicit = ConfigurationLocation(
      options: try LaunchOptions(arguments: ["--config=~/custom.toml"]),
      environment: environment, home: home, directory: directory)
    XCTAssertEqual(explicit.url.path, "/tmp/config-home/custom.toml")
    let relative = ConfigurationLocation(
      options: try LaunchOptions(arguments: ["--config", "relative.toml"]),
      environment: environment, home: home, directory: directory)
    XCTAssertEqual(relative.url.path, "/tmp/config-work/relative.toml")
    let options = try LaunchOptions(arguments: [])
    XCTAssertEqual(ConfigurationLocation(options: options, environment: environment).url.path, "/tmp/environment.toml")
    XCTAssertEqual(ConfigurationLocation(options: options, environment: ["XDG_CONFIG_HOME": "/tmp/xdg"]).url.path, "/tmp/xdg/mactilebar/config.toml")
    XCTAssertEqual(ConfigurationLocation(options: options, environment: ["XDG_CONFIG_HOME": "relative"], home: home).url.path, "/tmp/config-home/.config/mactilebar/config.toml")
  }

  func testLaunchOptionsValidateArguments() throws {
    XCTAssertTrue(try LaunchOptions(arguments: ["--check-config"]).checkConfig)
    XCTAssertTrue(try LaunchOptions(arguments: ["--help"]).help)
    for arguments in [["--config"], ["--config="], ["--config", "--help"], ["--unknown"]] {
      XCTAssertThrowsError(try LaunchOptions(arguments: arguments))
    }
  }
}
