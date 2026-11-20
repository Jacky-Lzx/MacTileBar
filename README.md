# MacTileBar

MacTileBar is a Swift/AppKit window control bar. Each display has three sections below the system menu bar. The left section shows the frontmost application's icon and name only on the focused display, the center shows the display's Spaces and windows, including empty Spaces, and the right shows today's date and weekday in English. The focused display is determined by yabai's focused Space. The date follows the system time zone and updates automatically. A bright border marks the Space with keyboard focus, while a lighter border marks a Space visible on another display. The bar hides when its display shows a native fullscreen Space.

## Build and run

Requires macOS 26 or later. Building requires Xcode with the macOS 26 SDK or later. The bar uses the system Liquid Glass material.

```sh
bash scripts/build-app.sh
open dist/MacTileBar.app
```

Install in Applications and launch the app. Use the same command to update an existing installation.

```sh
bash scripts/install-app.sh
```

The install script uses `dist/MacTileBar.app`, asks any running MacTileBar instance to quit normally, replaces `/Applications/MacTileBar.app`, and launches the new version. After changing the code, run the build script before running the install script.

## Configuration

MacTileBar reads `~/.config/mactilebar/config.toml` by default. An absolute `XDG_CONFIG_HOME` changes the default to `$XDG_CONFIG_HOME/mactilebar/config.toml`. Start with [config.example.toml](config.example.toml), which lists all supported settings and their defaults. Missing settings use the built-in defaults.

```sh
mkdir -p "${XDG_CONFIG_HOME:-$HOME/.config}/mactilebar"
cp -n config.example.toml "${XDG_CONFIG_HOME:-$HOME/.config}/mactilebar/config.toml"
```

To select a different file, quit MacTileBar and launch it with an absolute path.

```sh
open /Applications/MacTileBar.app --args --config /absolute/path/config.toml
```

The `MACTILEBAR_CONFIG` environment variable also selects a file when launching the executable directly. `--config` takes precedence over the environment variable, followed by the default path. Relative custom paths resolve against the launch working directory, and `~/` expands to the home directory. A custom path applies to that launch. Use the default location for settings that should also load after installation or a normal Finder launch.

A minimal configuration can override just a few settings.

```toml
[appearance]
bar_height = 32
capsule_height = 28
space_font_size = 12
window_icon_size = 18

[date]
format = "yyyy-MM-dd EEEE"
text_color = "#FFFFFF"

[behavior]
refresh_interval = 0.75
```

Appearance dimensions use points. Heights, font sizes, button and icon sizes, and maximum text widths must be positive. Spacing and border dimensions can be zero. `capsule_height` must fit within `bar_height`. Window icons are constrained to their button bounds. The date uses Foundation `DateFormatter` patterns, English names, and the system time zone. Colors accept `#RRGGBB` or `#RRGGBBAA`. `refresh_interval` is a positive number of seconds.

After editing, choose **Reload Configuration** from the MacTileBar menu. Reloading applies the layout, date, polling interval, and reserved bar height together. A malformed file, unknown key, or invalid value appears as an error in the menu, with details in the tooltip. Failed reloads retain the last valid configuration. Startup errors use the built-in defaults and display the error. A missing default file uses defaults. A missing explicitly selected file reports an error.

`behavior.reserves_bar_height` is optional. When omitted, the saved menu preference is used. When supplied, the file's value is applied on startup and reload. The menu toggle can still change it while the app runs.

Validate a file without launching the bar or modifying yabai settings.

```sh
/Applications/MacTileBar.app/Contents/MacOS/MacTileBar --config /absolute/path/config.toml --check-config
```

TOML parsing uses [TOMLDecoder](https://github.com/dduan/TOMLDecoder).

## yabai integration

The app queries a running yabai instance and looks for the executable in Homebrew locations and `PATH`. To debug with a custom executable, set `MACTILEBAR_YABAI` to its absolute path and run the executable inside the app bundle directly. The MacTileBar menu bar item shows connection status, command errors, and bar reservation issues. Its menu also lets you refresh or quit.

“Automatically Reserve Bar Height” is enabled by default and can be disabled in the MacTileBar menu. The app syncs its bar height (currently 27 pt) to yabai's `external_bar` setting, reserving space above tiled windows on all displays. Existing larger top reservations and enabled bottom reservations are preserved. yabai uses the same values for all displays.

When you disable the option or quit normally, the app restores the previous settings if yabai still uses the values written by MacTileBar. If another program changes the setting while MacTileBar is running, automatic synchronization pauses. Turn the option off and on again to resume. Force-quitting may temporarily leave the reserved space in place. The next launch resumes or cleans up the previous reservation.

## Mouse controls

- Click a Space number, name, or empty area of its capsule to switch to that Space.
- Right-click a capsule to close its Space. Windows in that Space move to other Spaces. At least one desktop Space must remain on each display.
- Click a window icon to switch to its Space and focus the window. Hover to see its title. Minimized windows appear translucent.
- Scroll horizontally when the contents exceed the display width. A regular vertical mouse wheel also scrolls the bar horizontally.

When you click a window on another Space, MacTileBar first switches to that Space, then waits for yabai to obtain the window's accessibility reference before focusing it. If the connection is lost, the bar keeps showing the last known state and disables interactions. Interactions resume automatically when the connection is restored.
