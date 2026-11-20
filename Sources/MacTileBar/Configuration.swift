import AppKit
import TOMLDecoder

struct ConfigurationError: LocalizedError {
  let message: String
  var errorDescription: String? { message }
}

private struct ConfigurationKey: CodingKey, ExpressibleByStringLiteral {
  let stringValue: String
  var intValue: Int? { nil }
  init(stringValue: String) { self.stringValue = stringValue }
  init?(intValue: Int) { return nil }
  init(stringLiteral value: String) { stringValue = value }
}

private func configurationTable(
  _ decoder: Decoder, keys: Set<String>
) throws -> KeyedDecodingContainer<ConfigurationKey> {
  let table = try decoder.container(keyedBy: ConfigurationKey.self)
  for key in table.allKeys where !keys.contains(key.stringValue) {
    let path = (decoder.codingPath.map(\.stringValue) + [key.stringValue]).joined(separator: ".")
    throw ConfigurationError(message: "Unknown configuration key '\(path)'.")
  }
  return table
}

struct BarAppearance: Decodable, Equatable {
  var barHeight: CGFloat = 27
  var capsuleSpacing: CGFloat = 4
  var barEdgePadding: CGFloat = 8
  var barSectionSpacing: CGFloat = 12
  var capsuleHeight: CGFloat = 25
  var capsuleBorderWidth: CGFloat = 2
  var spaceFontSize: CGFloat = 10
  var spaceLabelMaxWidth: CGFloat = 100
  var spaceLeadingPadding: CGFloat = 6
  var spaceTrailingPadding: CGFloat = 6
  var spaceLabelIconGap: CGFloat = 2
  var windowButtonSize: CGFloat = 20
  var windowIconSize: CGFloat = 18
  var windowButtonGap: CGFloat = 2
  var statusFontSize: CGFloat = 11
  var statusHorizontalPadding: CGFloat = 10
  var focusedAppMaxTextWidth: CGFloat = 180
  var focusedAppIconSize: CGFloat = 16
  var focusedAppIconSpacing: CGFloat = 4
  var floatingIndicatorWidth: CGFloat = 8
  var floatingIndicatorHeight: CGFloat = 2
  var floatingIndicatorBottomPadding: CGFloat = 0.5

  private static let fields: [String: WritableKeyPath<Self, CGFloat>] = [
    "bar_height": \.barHeight,
    "capsule_spacing": \.capsuleSpacing,
    "bar_edge_padding": \.barEdgePadding,
    "bar_section_spacing": \.barSectionSpacing,
    "capsule_height": \.capsuleHeight,
    "capsule_border_width": \.capsuleBorderWidth,
    "space_font_size": \.spaceFontSize,
    "space_label_max_width": \.spaceLabelMaxWidth,
    "space_leading_padding": \.spaceLeadingPadding,
    "space_trailing_padding": \.spaceTrailingPadding,
    "space_label_icon_gap": \.spaceLabelIconGap,
    "window_button_size": \.windowButtonSize,
    "window_icon_size": \.windowIconSize,
    "window_button_gap": \.windowButtonGap,
    "status_font_size": \.statusFontSize,
    "status_horizontal_padding": \.statusHorizontalPadding,
    "focused_app_max_text_width": \.focusedAppMaxTextWidth,
    "focused_app_icon_size": \.focusedAppIconSize,
    "focused_app_icon_spacing": \.focusedAppIconSpacing,
    "floating_indicator_width": \.floatingIndicatorWidth,
    "floating_indicator_height": \.floatingIndicatorHeight,
    "floating_indicator_bottom_padding": \.floatingIndicatorBottomPadding,
  ]

  init() {}

  init(from decoder: Decoder) throws {
    self.init()
    let table = try configurationTable(decoder, keys: Set(Self.fields.keys))
    for (name, field) in Self.fields {
      let key = ConfigurationKey(stringValue: name)
      if let value = try table.decodeIfPresent(Double.self, forKey: key) {
        guard value.isFinite, value >= 0 else {
          throw ConfigurationError(message: "appearance.\(name) must be a finite, nonnegative number.")
        }
        self[keyPath: field] = CGFloat(value)
      }
    }
    let positiveFields = [
      "bar_height", "capsule_height", "space_font_size", "space_label_max_width",
      "window_button_size", "window_icon_size", "status_font_size", "focused_app_max_text_width",
    ]
    for name in positiveFields {
      guard let field = Self.fields[name], self[keyPath: field] > 0 else {
        throw ConfigurationError(message: "appearance.\(name) must be greater than zero.")
      }
    }
    guard capsuleHeight <= barHeight, barHeight < CGFloat(Int.max) else {
      throw ConfigurationError(message: "capsule_height must not exceed bar_height, and bar_height must fit in an integer.")
    }
  }
}

struct DateConfiguration: Decodable, Equatable {
  var format = "yyyy/MM/dd EEEE"
  var textColor = "#FFFFFF"

  var color: NSColor {
    let hex = String(textColor.dropFirst())
    let value = UInt32(hex, radix: 16) ?? 0xFFFFFF
    let rgba = hex.count == 6 ? (value << 8) | 0xFF : value
    return NSColor(
      srgbRed: CGFloat((rgba >> 24) & 0xFF) / 255,
      green: CGFloat((rgba >> 16) & 0xFF) / 255,
      blue: CGFloat((rgba >> 8) & 0xFF) / 255,
      alpha: CGFloat(rgba & 0xFF) / 255)
  }

  init() {}

  init(from decoder: Decoder) throws {
    let table = try configurationTable(decoder, keys: ["format", "text_color"])
    format = try table.decodeIfPresent(String.self, forKey: "format") ?? format
    textColor = try table.decodeIfPresent(String.self, forKey: "text_color") ?? textColor
    guard !format.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw ConfigurationError(message: "date.format must not be empty.")
    }
    guard textColor.first == "#", [7, 9].contains(textColor.count),
      textColor.dropFirst().allSatisfy({ $0.isASCII && $0.isHexDigit })
    else {
      throw ConfigurationError(message: "date.text_color must use #RRGGBB or #RRGGBBAA.")
    }
  }
}

struct BehaviorConfiguration: Decodable, Equatable {
  var refreshInterval: TimeInterval = 0.75
  var reservesBarHeight: Bool?

  init() {}

  init(from decoder: Decoder) throws {
    let table = try configurationTable(decoder, keys: ["refresh_interval", "reserves_bar_height"])
    refreshInterval = try table.decodeIfPresent(Double.self, forKey: "refresh_interval") ?? refreshInterval
    reservesBarHeight = try table.decodeIfPresent(Bool.self, forKey: "reserves_bar_height")
    guard refreshInterval.isFinite, refreshInterval > 0 else {
      throw ConfigurationError(message: "behavior.refresh_interval must be a finite number greater than zero.")
    }
  }
}

struct BarConfiguration: Decodable, Equatable {
  var appearance = BarAppearance()
  var date = DateConfiguration()
  var behavior = BehaviorConfiguration()

  init() {}

  init(from decoder: Decoder) throws {
    let table = try configurationTable(decoder, keys: ["appearance", "date", "behavior"])
    appearance = try table.decodeIfPresent(BarAppearance.self, forKey: "appearance") ?? appearance
    date = try table.decodeIfPresent(DateConfiguration.self, forKey: "date") ?? date
    behavior = try table.decodeIfPresent(BehaviorConfiguration.self, forKey: "behavior") ?? behavior
  }

  static func parse(_ text: String) throws -> Self {
    try TOMLDecoder().decode(Self.self, from: text)
  }
}

struct LaunchOptions {
  var configPath: String?
  var checkConfig = false
  var help = false

  init(arguments: [String]) throws {
    var arguments = arguments.makeIterator()
    while let argument = arguments.next() {
      switch argument {
      case "--config":
        guard let path = arguments.next(), !path.isEmpty, !path.hasPrefix("--") else {
          throw ConfigurationError(message: "--config requires a file path.")
        }
        configPath = path
      case "--check-config": checkConfig = true
      case "--help", "-h": help = true
      default:
        guard argument.hasPrefix("--config="), argument.count > "--config=".count else {
          throw ConfigurationError(message: "Unknown argument '\(argument)'. Use --help for usage.")
        }
        configPath = String(argument.dropFirst("--config=".count))
      }
    }
  }
}

struct ConfigurationLocation {
  let url: URL
  let required: Bool

  init(
    options: LaunchOptions, environment: [String: String] = ProcessInfo.processInfo.environment,
    home: URL = FileManager.default.homeDirectoryForCurrentUser,
    directory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
  ) {
    if let path = options.configPath ?? environment["MACTILEBAR_CONFIG"], !path.isEmpty {
      let expanded = path.hasPrefix("~/") ? home.appendingPathComponent(String(path.dropFirst(2))).path : path
      url = URL(fileURLWithPath: expanded, relativeTo: directory).standardizedFileURL
      required = true
    } else {
      let root: URL
      if let xdg = environment["XDG_CONFIG_HOME"], xdg.hasPrefix("/") {
        root = URL(fileURLWithPath: xdg)
      } else {
        root = home.appendingPathComponent(".config", isDirectory: true)
      }
      url = root.appendingPathComponent("mactilebar/config.toml")
      required = false
    }
  }
}

final class ConfigurationFile {
  let location: ConfigurationLocation
  private(set) var current = BarConfiguration()
  private(set) var issue: String?

  init(location: ConfigurationLocation) { self.location = location }

  @discardableResult
  func reload() -> Bool {
    do {
      let data: Data
      do {
        data = try Data(contentsOf: location.url)
      } catch CocoaError.fileReadNoSuchFile where !location.required {
        current = BarConfiguration()
        issue = nil
        return true
      }
      guard let text = String(data: data, encoding: .utf8) else {
        throw ConfigurationError(message: "The configuration file must contain UTF-8 text.")
      }
      let next = try BarConfiguration.parse(text)
      current = next
      issue = nil
      return true
    } catch {
      let detail = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
      issue = "Could not load \(location.url.path).\n\(detail)"
      return false
    }
  }
}
