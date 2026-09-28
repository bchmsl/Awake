# Awake

A small native macOS menu bar app that keeps your Mac awake.

Turn Keep Awake on, and your Mac and its display stay awake. Turn it off, and macOS sleeps as usual.

## Features

- Menu bar only. No window and no Dock icon.
- Native sleep prevention through IOKit power assertions. No `caffeinate`, no fake mouse or keyboard activity.
- Keeps both the system and the display awake while on.
- Outline cup icon when off, filled cup icon when on.
- Start on Login, using the macOS login items API (`SMAppService`).
- Choose what happens at launch: keep awake, allow sleep, or restore the last state.
- Releases everything when you turn it off or quit.
- No third-party dependencies.

## Usage

| Action | Result |
|---|---|
| Left click | Opens the menu |
| Right click, or Control-click | Toggles Keep Awake |

The menu:

```text
Keep Awake            ✓ when on
──────────────────
Start on Login        ✓ when enabled
On Launch           ▸ Keep Awake
                      Allow Sleep         (default)
                      Restore Last State
──────────────────
Quit Awake           ⌘Q
```

- **Keep Awake** turns it on or off, the same as a right click.
- **Start on Login** shows the real macOS state. If you turn Awake off in System Settings > General > Login Items, the item shows a dash. Clicking it then opens that settings page.
- **On Launch** sets what Keep Awake does when the app starts. Changing it does not change the current state.
- **Quit Awake** releases the power assertions and quits.

Awake prevents idle sleep only. Closing a MacBook lid or choosing Apple menu > Sleep can still put the Mac to sleep.

## Requirements

- macOS 13 Ventura or later.
- To build: Xcode or the Command Line Tools, with Swift 6 or later.

## Build and install

```bash
git clone https://github.com/bchmsl/Awake.git
cd Awake
scripts/build-app.sh --install
```

This builds a release version, signs it ad-hoc, copies it to `~/Applications/Awake.app`, and launches it. Without `--install`, the script only builds `Awake.app` into the build folder.

| Variable | Default | Purpose |
|---|---|---|
| `AWAKE_BUILD_DIR` | `~/Library/Caches/Awake-build` | Build output folder |
| `AWAKE_SIGN_IDENTITY` | `-` (ad-hoc) | Code signing identity |

Use the scripts instead of a bare `swift build` or `swift test`. They keep build output out of the project folder, which matters if it lives in iCloud Drive. They also work around a few Command Line Tools issues, described in `scripts/common.sh` and `scripts/test.sh`.

## Tests

```bash
scripts/test.sh
```

Extra arguments are passed to `swift test`:

```bash
scripts/test.sh --filter PowerAssertion
```

The power assertion tests use the real macOS power management. Each test creates short-lived assertions with a unique name and releases them.

## Check that it works

While Keep Awake is on, run:

```bash
pmset -g assertions | grep 'Awake: Keep Awake is on'
```

It should list two assertions from Awake: `PreventUserIdleSystemSleep` and `PreventUserIdleDisplaySleep`. When Keep Awake is off, it lists nothing.

## Settings

Awake stores its settings in the `com.bachana.Awake` user defaults domain.

| Key | Type | Meaning |
|---|---|---|
| `startupBehavior` | String | `keepAwake`, `allowSleep`, or `restoreLastState`. A missing or invalid value means `allowSleep`. |
| `lastKeepAwakeState` | Bool | The last state you set. Used by Restore Last State. Quitting does not change it. |

Awake does not store Start on Login. macOS owns that state.

## Uninstall

1. Turn off **Start on Login** in the menu.
2. Quit Awake.
3. Delete the app and its settings:

```bash
rm -rf ~/Applications/Awake.app
defaults delete com.bachana.Awake
```

## Notes

- The app is ad-hoc signed, so it is meant to run on the Mac that built it. To share a build with other people, sign it with a Developer ID and notarize it.
- After a rebuild, macOS may treat the new build as a different app for login items. If Start on Login stops working, turn it off and on again.

## How it works

```text
AppDelegate
 └─ StatusItemController       menu bar icon, clicks, menu
     ├─ KeepAwakeController    single source of truth for on/off
     │   ├─ PowerAssertion     IOKit system and display sleep assertions
     │   └─ Preferences        UserDefaults
     ├─ Preferences
     └─ LoginItemController    Start on Login through SMAppService
```

- `KeepAwakeController` never stores the on/off state separately. It reads it from whether the power assertions are held, so the icon cannot disagree with the system.
- `PowerAssertion` holds both assertions or none. If creating the second one fails, it releases the first.
- `LoginItemController` always reads the status from macOS and never caches it.

Project layout:

```text
Sources/Awake/          App entry point
Sources/AwakeKit/       App logic and UI
Tests/AwakeKitTests/    Unit and integration tests (Swift Testing)
Support/Info.plist      App bundle settings (menu bar only, macOS 13+)
scripts/                Build, install, and test scripts
.plan/                  Design notes
```
