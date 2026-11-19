#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

source_bundle="$PWD/dist/MacTileBar.app"
destination="/Applications/MacTileBar.app"
if [[ ! -d "$source_bundle" ]]; then
  printf '%s\n' 'Run bash scripts/build-app.sh first.' >&2
  exit 1
fi
/usr/bin/codesign --verify --strict "$source_bundle"

# Prepare and verify the replacement before asking the running app to quit.
staging="$(mktemp -d /Applications/.MacTileBar-install.XXXXXX)"
cleanup() {
  if [[ -d "$staging/previous.app" && ! -e "$destination" ]]; then
    mv "$staging/previous.app" "$destination" || return
  fi
  rm -rf "$staging"
}
trap cleanup EXIT
/usr/bin/ditto "$source_bundle" "$staging/MacTileBar.app"
/usr/bin/codesign --verify --strict "$staging/MacTileBar.app"

# Normal termination lets MacTileBar restore yabai's reserved bar height.
/usr/bin/osascript -l JavaScript <<'JXA'
ObjC.import('AppKit');
const apps = $.NSRunningApplication.runningApplicationsWithBundleIdentifier('local.mactilebar.app');
for (let i = 0; i < apps.count; i++) {
  if (!apps.objectAtIndex(i).terminate) {
    throw new Error('MacTileBar could not be asked to quit. Quit it from the menu bar and try again.');
  }
}
const deadline = Date.now() + 30000;
for (let i = 0; i < apps.count; i++) {
  while (!apps.objectAtIndex(i).isTerminated) {
    if (Date.now() >= deadline) {
      throw new Error('Timed out waiting for MacTileBar to quit. Quit it from the menu bar and try again.');
    }
    // NSRunningApplication refreshes its state when the main run loop runs.
    $.NSRunLoop.currentRunLoop.runUntilDate($.NSDate.dateWithTimeIntervalSinceNow(0.1));
  }
}
JXA

if [[ -e "$destination" ]]; then
  mv "$destination" "$staging/previous.app"
fi
mv "$staging/MacTileBar.app" "$destination"
/usr/bin/open "$destination"
/usr/bin/osascript -l JavaScript <<'JXA'
ObjC.import('AppKit');
const deadline = Date.now() + 30000;
let launched = false;
while (!launched) {
  $.NSRunLoop.currentRunLoop.runUntilDate($.NSDate.dateWithTimeIntervalSinceNow(0.1));
  const apps = $.NSRunningApplication.runningApplicationsWithBundleIdentifier('local.mactilebar.app');
  for (let i = 0; i < apps.count; i++) {
    const app = apps.objectAtIndex(i);
    if (ObjC.unwrap(app.bundleURL.path) === '/Applications/MacTileBar.app'
        && app.isFinishedLaunching && !app.isTerminated) {
      launched = true;
      break;
    }
  }
  if (!launched && Date.now() >= deadline) {
    throw new Error('MacTileBar is installed, but its launch could not be confirmed.');
  }
}
JXA
printf 'Installed and launched %s\n' "$destination"
