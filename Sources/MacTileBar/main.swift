import AppKit

let configurationFile: ConfigurationFile
do {
  let options = try LaunchOptions(arguments: Array(CommandLine.arguments.dropFirst()))
  if options.help {
    print("""
      Usage: MacTileBar [--config PATH] [--check-config]
      Default file: $XDG_CONFIG_HOME/mactilebar/config.toml or ~/.config/mactilebar/config.toml
      MACTILEBAR_CONFIG can also specify a file. --config takes precedence.
      Use Reload Configuration in the menu bar to apply edits.
      """)
    exit(0)
  }
  configurationFile = ConfigurationFile(location: ConfigurationLocation(options: options))
  let loaded = configurationFile.reload()
  if let issue = configurationFile.issue {
    FileHandle.standardError.write(Data((issue + "\n").utf8))
  }
  if options.checkConfig {
    if loaded { print("Configuration valid. \(configurationFile.location.url.path)") }
    exit(loaded ? 0 : 1)
  }
} catch {
  FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
  exit(1)
}

let app = NSApplication.shared
let controller = BarController(configurationFile: configurationFile)
app.setActivationPolicy(.accessory)
app.delegate = controller
app.run()
