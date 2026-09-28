# Awake: macOS Keep Awake Menu Bar App (Implementation Plan)

Status: **Plan only. Implementation has not started.**
Date: 2026-09-28
App name: **Awake** (matches the project folder).

---

## 0. Environment findings

These facts were checked on this Mac. They drive several decisions below.

| Item | Finding | Impact |
|---|---|---|
| macOS | 27.0, Apple Silicon (arm64) | Only this version can be verified locally |
| Xcode | **Not installed.** Only Command Line Tools (`/Library/Developer/CommandLineTools`). `xcodebuild` and `actool` are unavailable. | No `.xcodeproj` build. Use SwiftPM plus a small bundle script. |
| Swift | 6.4, macOS 27.0 SDK | Swift 6 language mode is fine |
| Test frameworks | Swift Testing (`Testing.framework`) is present. XCTest is **not** present in CLT. | Tests use `import Testing` |
| Signing identities | 0 valid code signing identities | Use ad-hoc signing (`codesign --sign -`) |
| Tools | `codesign`, `iconutil`, `plutil`, `pmset`, `sfltool`, `defaults` all present | Build and verification work with CLT only |
| Project location | iCloud Drive: `~/Library/Mobile Documents/com~apple~CloudDocs/Personal Projects/Awake`. Path has spaces and `~`. | Build output must live **outside** iCloud. Scripts must quote every path. |
| SF Symbols | `cup.and.saucer` and `cup.and.saucer.fill` exist. They show a clear outline vs solid difference at 16 pt. | Chosen icon pair (see section 11) |

The SF Symbol check used a throwaway render script in the session scratchpad. Nothing was written to the project except this plan.

---

## 1. Requirements summary

- Native macOS menu bar utility, Swift, no Dock icon, no main window.
- Two states. **OFF**: normal macOS sleep. **ON**: app prevents automatic idle system sleep.
- Icon: OFF = outline, ON = filled, same symbol.
- Left click opens a compact menu. Right click toggles Keep Awake at once, with no menu and no dialog.
- Menu contains: Keep Awake toggle, Start on Login (checkable), On Launch submenu (3 exclusive options), Quit.
- Start on Login uses the modern native API and always shows the real system state.
- Startup behavior options: Keep Awake, Allow Sleep, Restore Last State. Persisted.
- Persist startup behavior and last Keep Awake state with `UserDefaults`.
- One source of truth for the active state. Assertion released on OFF and on quit.
- No fake input events. No third-party dependencies.
- Output: a normal `.app` that launches directly. Local use only, no App Store.

---

## 2. Technical decisions

| Area | Decision | Reason |
|---|---|---|
| UI framework | **AppKit only** (`NSStatusItem`, `NSMenu`) | SwiftUI `MenuBarExtra` cannot tell left and right clicks apart. No windows are needed, so SwiftUI adds nothing. |
| Language | Swift 6 language mode, `swift-tools-version: 6.0` | Modern default. All UI types are `@MainActor`. |
| Build system | **SwiftPM + `scripts/build-app.sh`** that assembles and signs `Awake.app` | Xcode is not installed. Fully scriptable. No hand-written `.pbxproj`. |
| Minimum macOS | **13.0** | `SMAppService` needs 13.0. No other API needs more. |
| Dock hiding | `LSUIElement = true` in `Info.plist` | Applied before launch, so the Dock icon never flashes. Still the standard mechanism. |
| Keep Awake | IOKit `IOPMAssertionCreateWithName` with `PreventUserIdleSystemSleep` | Apple's documented power assertion API. Returns error codes. Released automatically if the process dies. |
| Start on Login | `SMAppService.mainApp` | Modern API (macOS 13+). No helper app, no plist, no entitlements. |
| Persistence | `UserDefaults.standard`, 2 keys | Simplest native option |
| Default startup behavior | **Allow Sleep** | Safe and predictable (section 7) |
| Status icon | SF Symbols `cup.and.saucer` / `cup.and.saucer.fill`, template images | Native look, correct light/dark/highlight rendering, matching fill variant |
| Signing | Ad-hoc. Optional stable self-signed identity via env var. | No Apple account or certificate needed for local use |
| Dependencies | None | Not needed |
| Bundle identifier | `com.bachana.Awake` (**placeholder, confirm before first build**) | Changing it later orphans saved preferences and the login item entry |
| Install location | `~/Applications/Awake.app` | No admin rights needed. Stable path for the login item. |

### Rejected alternatives

| Alternative | Why rejected |
|---|---|
| `ProcessInfo.beginActivity(options: .idleSystemSleepDisabled)` | Works and creates the same assertion type internally. But it has no error result and is less explicit. Acceptable fallback only. |
| Running `caffeinate -i` as a child process | Extra process to manage. Orphan risk if the app crashes. No benefit over calling the API directly. |
| Fake mouse or keyboard activity, `IOPMAssertionDeclareUserActivity` | Forbidden by requirements. Also wakes the display, which is not the goal. |
| `SMLoginItemSetEnabled` with a helper app | Deprecated since macOS 13 |
| Writing a plist into `~/Library/LaunchAgents` | Manual file hack, not the modern API |
| `LSSharedFileList` login items | Deprecated |
| `NSStatusItem.popUpMenu(_:)` | Deprecated since macOS 10.14 |
| Xcode project | Requires installing Xcode first. No benefit for an app this size. Possible later (section 17). |

---

## 3. Chosen macOS APIs

| API | Framework | Min macOS | Used for |
|---|---|---|---|
| `NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)` | AppKit | 10.x | Menu bar item |
| `NSStatusBarButton.sendAction(on:)`, `NSApp.currentEvent` | AppKit | 10.x | Left vs right click routing |
| `NSStatusItem.menu` + `button.performClick(nil)` | AppKit | 10.x | Native menu opening on left click |
| `NSMenu`, `NSMenuItem`, `NSMenuDelegate` (`menuNeedsUpdate(_:)`, `menuDidClose(_:)`) | AppKit | 10.x | Menu, state refresh, menu cleanup |
| `NSImage(systemSymbolName:accessibilityDescription:)`, `NSImage.SymbolConfiguration` | AppKit | 11.0 | Status icons |
| `NSAlert` | AppKit | 10.x | Rare error messages |
| `NSRunningApplication.runningApplications(withBundleIdentifier:)` | AppKit | 10.6 | Single-instance guard |
| `IOPMAssertionCreateWithName`, `IOPMAssertionRelease` | IOKit (`IOKit.pwr_mgt`) | 10.6 / 10.7 | Keep Awake |
| `IOPMCopyAssertionsByProcess` | IOKit | 10.x | Tests only: count this process's assertions |
| `SMAppService.mainApp`: `register()`, `unregister()`, `status`, `openSystemSettingsLoginItems()` | ServiceManagement | 13.0 | Start on Login |
| `UserDefaults` | Foundation | all | Preferences |
| `Logger` | os | 11.0 | Diagnostics (no PII) |

---

## 4. Application architecture

Pure AppKit. Main thread only. No timers, no background queues, no Combine, no notifications between objects.

```
AwakeMain (@main, executable target "Awake")
   │ creates and keeps a strong reference
   ▼
AppDelegate ─────────owns──────► Preferences ◄──────────────┐
   │                               (UserDefaults)            │
   ├──owns──► KeepAwakeController ──owns──► PowerAssertion   │
   │             ▲        │ onChange(isOn)    (IOKit)        │
   │   setOn /   │        ▼                                  │
   │   toggle    │                                           │
   ├──owns──► StatusItemController ──reads/writes───────────┘
   │             (NSStatusItem, icons, click routing, NSMenu)
   │                    │ uses
   └──owns──► LoginItemController (SMAppService.mainApp)
```

### Targets

| Target | Kind | Contents |
|---|---|---|
| `Awake` | executable | One file: `@main` entry point |
| `AwakeKit` | library | All app code |
| `AwakeKitTests` | test | Swift Testing tests, `@testable import AwakeKit` |

Why two targets: tests import a plain library. This avoids problems with testing an executable target that has `@main`. It is one extra folder, not an extra abstraction.

### Responsibilities

| Type | Isolation | Responsibility |
|---|---|---|
| `AwakeMain` | `@MainActor` | Creates `NSApplication`, sets the delegate, runs the app |
| `AppDelegate` | `@MainActor`, `public` | Lifecycle: builds objects, applies startup behavior, cleans up on quit |
| `KeepAwakeController` | `@MainActor` | Single write path for the active state. Persists last state. Notifies the UI. |
| `PowerAssertion` | not actor-isolated | Owns at most one IOKit assertion. Create and release. |
| `SleepPreventing` | protocol | Seam so `KeepAwakeController` can be tested with a fake |
| `Preferences` | not actor-isolated | Typed access to 2 `UserDefaults` keys |
| `StartupBehavior` | enum | The 3 options and the pure "initial state" rule |
| `LoginItemController` | `@MainActor` | Wraps `SMAppService.mainApp`: status and toggle, benign error handling |
| `StatusItemController` | `@MainActor`, `NSObject`, `NSMenuDelegate` | Status item, icon, tooltip, left/right click, menu build and refresh, alerts |

`PowerAssertion` is not `@MainActor`, so its `deinit` can release the assertion without Swift 6 isolation problems. It is only used from the main thread.

---

## 5. State model

Three separate concepts. They are never mixed.

| Concept | Type | Source of truth | Persisted |
|---|---|---|---|
| Active Keep Awake state | `Bool` (computed) | Whether `PowerAssertion` holds an assertion ID | Mirrored into `lastKeepAwakeState` |
| Startup behavior | `StartupBehavior` | `UserDefaults` key `startupBehavior` | Yes |
| Start on Login | `SMAppService.Status` | macOS (`SMAppService.mainApp.status`) | **No**, never cached |

### Rules

- There is **no stored `isOn` flag anywhere**. `KeepAwakeController.isOn` returns `sleepPreventer.isActive`. So the UI can never disagree with the real system resource.
- **`KeepAwakeController.setOn(_:)` is the only write path.** Menu toggle, right click, and startup all go through it.
- After every successful change: persist `lastKeepAwakeState`, then call `onChange(isOn)`. `StatusItemController` swaps the icon and tooltip in that callback.
- Menu item states are read fresh in `menuNeedsUpdate(_:)` each time the menu opens. There is no cached menu state to go stale.

### Planned API (signatures only)

```swift
protocol SleepPreventing: AnyObject {
    var isActive: Bool { get }
    func activate() throws      // no-op if already active
    func deactivate()           // no-op if not active, never throws
}

@MainActor final class KeepAwakeController {
    init(sleepPreventer: any SleepPreventing, preferences: Preferences)
    var isOn: Bool { get }                 // sleepPreventer.isActive
    var onChange: ((Bool) -> Void)?        // single observer: StatusItemController
    func applyStartupBehavior()            // called once at launch
    func setOn(_ on: Bool) throws          // the single write path
    func toggle() throws                   // setOn(!isOn)
    func releaseForTermination()           // releases, does NOT persist, does NOT notify
}
```

### `setOn(_:)` semantics

1. If `on == isOn`: return. No write, no callback.
2. If `on`: `try sleepPreventer.activate()`. On failure: log and rethrow. State stays OFF. Nothing is persisted.
3. If `!on`: `sleepPreventer.deactivate()`.
4. `preferences.lastKeepAwakeState = isOn`
5. `onChange?(isOn)`

### Transitions

```
            setOn(true) succeeds
    OFF ───────────────────────────► ON
     ▲  ◄───────────────────────────  │
     │        setOn(false)             │
     │                                 │ releaseForTermination()
     │                                 ▼ (quit only: no persist, no callback)
     └─ setOn(true) fails: stays OFF, error surfaced to the caller
```

---

## 6. Settings persistence model

`UserDefaults.standard`. Domain = bundle ID. File: `~/Library/Preferences/com.bachana.Awake.plist`.

| Key | Type | Values | If missing or invalid |
|---|---|---|---|
| `startupBehavior` | String | `keepAwake`, `allowSleep`, `restoreLastState` | `allowSleep` |
| `lastKeepAwakeState` | Bool | `true` / `false` | `false` |

Nothing else is persisted. No Start on Login key, because macOS is the source of truth. No window state, because there are no windows.

The raw string values are a storage contract. Tests pin them so a rename cannot silently reset users.

### When `lastKeepAwakeState` is written

1. **At the end of startup, always**, with the actual resulting state, even when nothing changed.
   Reason: with Allow Sleep on Launch the app starts OFF with no transition. Without this write, a stale `true` from an older session survives. A later switch to Restore Last State would then wrongly restore ON.
2. **After every successful change** while running (menu toggle, right click).

It is **never** written:

- on quit or in `applicationWillTerminate`, because releasing the assertion at quit is not a user choice;
- after a failed activation, because the state did not change.

**Invariant:** while the app runs, `lastKeepAwakeState == isOn`. Tests check this.

### Crash durability

`UserDefaults.set` hands the value to `cfprefsd` right away. It survives an app crash or `kill -9`. `synchronize()` is not needed. Only a kernel panic or power loss in the next moment could lose it, which is acceptable.

### Planned API

```swift
final class Preferences {
    init(defaults: UserDefaults = .standard)
    var startupBehavior: StartupBehavior { get set }
    var lastKeepAwakeState: Bool { get set }
}
```

Tests inject `UserDefaults(suiteName: "AwakeTests.<UUID>")` and call `removePersistentDomain(forName:)` afterwards.

Manual reset (app not running): `defaults delete com.bachana.Awake`.

---

## 7. Startup behavior model

```swift
enum StartupBehavior: String, CaseIterable {
    case keepAwake, allowSleep, restoreLastState
    static let defaultValue: StartupBehavior = .allowSleep
    func initialState(lastState: Bool) -> Bool   // pure, unit tested
}
```

| Behavior | Menu title | `lastState = false` | `lastState = true` |
|---|---|---|---|
| `keepAwake` | Keep Awake | ON | ON |
| `allowSleep` | Allow Sleep | OFF | OFF |
| `restoreLastState` | Restore Last State | OFF | ON |

### Default: Allow Sleep

- A fresh install, or a launch at login, never keeps the Mac awake unless the user asked for it.
- Avoids a laptop staying awake in a bag after login (heat, battery drain).
- Matches normal macOS behavior until the user opts in.

### Rules

- Choosing a startup behavior only writes the preference. It **never changes the current state**. It takes effect at the next launch.
- Manual launch and login launch use the **same code path**. The app does not detect how it was launched. This satisfies requirement 25 by design.

---

## 8. Menu bar mouse interaction design

### Setup

- `statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)`
- `statusItem.autosaveName = "AwakeStatusItem"` so the position is kept after Cmd-drag reordering.
- `statusItem.menu` stays **`nil`** except while the menu is open. If a menu is attached, AppKit opens it on every click and never sends the action. Right-click toggle would break.
- `button.target = self`, `button.action = #selector(handleClick(_:))`
- `button.sendAction(on: [.leftMouseDown, .rightMouseUp])`

### Routing in `handleClick(_:)`

```
event = NSApp.currentEvent
isSecondary =
      event.type == .rightMouseUp
   || event.type == .rightMouseDown
   || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))

isSecondary  -> toggle Keep Awake (no menu)
otherwise    -> showMenu()   // left click, keyboard or VoiceOver press, nil event
```

### `showMenu()`

```
statusItem.menu = menu
statusItem.button?.performClick(nil)   // AppKit opens the menu natively
// menuDidClose(_:) sets statusItem.menu = nil
```

Why this pattern:

- AppKit opens the menu itself. Position, button highlight, dark mode, keyboard navigation, and accessibility are all native.
- It avoids the deprecated `popUpMenu(_:)` and manual `NSMenu.popUp(positioning:at:in:)` placement.
- Clearing the menu in `menuDidClose(_:)` guarantees the next right click toggles instead of opening the menu.

Why these event types:

- `.leftMouseDown`: native menu bar menus open on mouse down.
- `.rightMouseUp`: the toggle fires once, on a completed click.

**Fallback:** if `.leftMouseDown` shows glitches in verification (menu flickers or closes at once), change the mask to `[.leftMouseUp, .rightMouseUp]`. Nothing else changes.

### Secondary click variants

- Control-click is treated as right click. This is the macOS convention for secondary click.
- Two-finger trackpad click produces right mouse events, so it toggles.

### Feedback

- The icon and tooltip change in the same run-loop turn. No animation, no sound, no alert.
- Tooltip: `Keep Awake is on. Right-click to turn off.` / `Keep Awake is off. Right-click to turn on.` This makes the right-click shortcut discoverable.

### Known platform limitation

A developer report says that on macOS 26+, right clicks on the very top edge of the taller menu bar may not reach status items. Clicks on the icon itself work. App code cannot fix this.

---

## 9. Start on Login implementation

| Question | Answer |
|---|---|
| API | `SMAppService.mainApp` (ServiceManagement). Registers the app bundle itself as a login item. |
| Required macOS | 13.0. This sets the deployment target. |
| Helper, plist, entitlements | None needed |
| Approval | `register()` for the main app normally enables it at once. macOS shows a notification that a login item was added. The app appears in System Settings > General > Login Items (& Extensions) > Open at Login. The user can switch it off there. Then `status` becomes `.requiresApproval`. |
| Signing | The SDK header says apps using `SMAppService` "must be code signed". Ad-hoc signing is expected to be enough for local use. This is common practice, not verified yet. Verify in step 9. |
| Detecting state | Read `SMAppService.mainApp.status` every time the menu opens. Never cached. Changes made in System Settings show up correctly. |

### Menu mapping

| `status` | Checkmark | Click action |
|---|---|---|
| `.enabled` | on (✓) | `unregister()` |
| `.notRegistered` | off | `register()` |
| `.notFound` | off | `register()` |
| `.requiresApproval` | mixed (–) | `SMAppService.openSystemSettingsLoginItems()` |

For the mixed state, set the tooltip: `Turned off in System Settings. Click to open Login Items.`

### Error handling

| Error | Handling |
|---|---|
| `kSMErrorAlreadyRegistered` on register | Treat as success |
| `kSMErrorJobNotFound` on unregister | Treat as success |
| `kSMErrorLaunchDeniedByUser` | Open System Settings Login Items |
| Anything else (for example `kSMErrorInvalidSignature`, "Operation not permitted") | Log with `Logger`. Show `NSAlert`: "Couldn't change Start on Login" plus `error.localizedDescription`. |

Compare `(error as NSError).code` against these constants. Do not depend on the error domain, because `SMAppServiceErrorDomain` only exists as a symbol on macOS 15+.

The status is re-read on the next menu open, so the checkmark always shows the real result.

Alerts: the app is never frontmost (LSUIElement). Activate first: `NSApp.activate()` on macOS 14+, `NSApp.activate(ignoringOtherApps: true)` on 13.

### Planned API

```swift
@MainActor final class LoginItemController {
    var status: SMAppService.Status { get }   // SMAppService.mainApp.status
    func toggle() throws                      // implements the table above
}
```

### Launch at login

macOS launches the bundle at login with no special arguments. The normal startup path runs. Same startup behavior as a manual launch.

### Location rule

Registration is tied to the bundle location and signature. Always register from the installed copy at `~/Applications/Awake.app`. Never from the build folder.

### Debug helpers (manual)

```bash
sfltool dumpbtm
```

```bash
sudo log stream --debug --info --predicate "sender in {'ServiceManagement', 'BackgroundTaskManagement', 'smd', 'backgroundtaskmanagementd'}"
```

`sfltool resetbtm` resets **all** login and background items for **all** apps and needs a reboot. Last resort only. The agent must never run it.

---

## 10. Keep Awake implementation details

| Question | Answer |
|---|---|
| API | `IOPMAssertionCreateWithName(type, level, name, &id)` and `IOPMAssertionRelease(id)` |
| Type | `kIOPMAssertionTypePreventUserIdleSystemSleep` |
| Level | `kIOPMAssertionLevelOn` |
| Name | `Awake: Keep Awake is on` (visible in `pmset -g assertions`) |
| Timeout | None. Held until turned off. |

### What it prevents

Idle system sleep, meaning sleep caused by a lack of user activity. SDK header: it "will prevent the system from sleeping due to a period of idle user activity".

### What it does not prevent

From the SDK header and by design:

- display dimming and display sleep ("The display may dim and idle sleep");
- screen saver and screen lock after the display turns off;
- Sleep chosen from the Apple menu, the power button, or a keyboard shortcut;
- lid close on a laptop (unless macOS clamshell rules apply);
- low battery sleep and thermal emergency sleep;
- log out, restart, shutdown.

It has no effect in Dark Wake.

OFF means **Awake holds no assertion**. Other apps (video playback, `caffeinate`, builds) can still keep the Mac awake. `pmset -g assertions` shows them.

### Start

`activate()`:

1. If an assertion ID is already held, return.
2. Call `IOPMAssertionCreateWithName`.
3. On `kIOReturnSuccess`, store the ID.
4. Otherwise throw `PowerAssertionError.createFailed(IOReturn)`. It conforms to `LocalizedError` and includes the hex code.

### Stop

`deactivate()`:

1. If no ID is held, return.
2. Call `IOPMAssertionRelease(id)`.
3. Log if the result is not `kIOReturnSuccess`.
4. Clear the ID **always**. A failed release means the ID is already invalid.

### Leak prevention

- At most one assertion, guarded by the stored ID.
- Every create is paired with exactly one release.
- No `IOPMAssertionRetain` calls.

### Cleanup

| Case | What releases the assertion |
|---|---|
| User turns OFF | `deactivate()` |
| Quit, logout, shutdown | `applicationWillTerminate` calls `releaseForTermination()` |
| Object deallocated | `PowerAssertion.deinit` (safety net) |
| Crash, `kill -9`, SIGTERM, Force Quit | `powerd` drops all assertions owned by a dead process. Established behavior. Verified by the kill test in section 16. |

### Sleep and wake

The assertion survives sleep and wake. No `NSWorkspace` sleep/wake observers are needed. After an explicit sleep (Apple menu or lid), Keep Awake is still ON after wake and the icon stays filled. This is correct, because the user turned it on.

### Swift import note

`kIOPMAssertionTypePreventUserIdleSystemSleep` is a macro alias to `CFSTR("PreventUserIdleSystemSleep")`. Pass it `as CFString`. If Swift does not import the macro, use the literal `"PreventUserIdleSystemSleep" as CFString`, which is the header's value.

---

## 11. Icon strategy

### Chosen pair

| State | Symbol |
|---|---|
| OFF | `cup.and.saucer` (outline) |
| ON | `cup.and.saucer.fill` (filled) |

- Same shape. Only the fill differs.
- Coffee means "stay awake". It is the well-known metaphor from Caffeine-style utilities.
- Both symbols exist since macOS 11, so they are safe for a 13.0 target.

### Candidates checked (rendered at 16 pt on this Mac)

| Pair | Verdict |
|---|---|
| `cup.and.saucer` / `.fill` | **Chosen.** Clear outline vs solid difference. Meaning fits. |
| `mug` / `.fill` | Good backup. The fill is a heavy solid block. |
| `cup.and.heat.waves` / `.fill` | Steam lines stay unfilled. Noisier at small size. |
| `eye` / `.fill` | The outline already has a solid pupil, so the states look too similar. Also reads as "visibility" or "privacy". |
| `sun.max` / `.fill` | Looks like a brightness control |
| `bolt` / `.fill` | Reads as charging or power |
| `moon.zzz` / `.fill` | Means sleep, the opposite meaning |
| `powersleep`, `sparkles`, `hourglass` | No `.fill` variant |

### Rendering

1. `NSImage(systemSymbolName:accessibilityDescription:)`
2. `.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 16, weight: .regular))`
3. Set `isTemplate = true` explicitly.
4. Build both images once at startup and reuse them.

Template images let macOS color the icon for light, dark, and tinted menu bars, and for the pressed highlight.

Tune the point size once by eye next to the system Wi-Fi and battery icons. 15 to 17 pt is the expected range.

Accessibility descriptions: `Keep Awake on` / `Keep Awake off`.

### Why not a custom menu bar icon

SF Symbols give native stroke weight, template behavior, Retina scaling, and a matching fill variant for free. A custom icon would need two hand-made assets with no gain.

### App icon (Finder, Login Items list)

- Not required by the spec.
- The SF Symbols license does not allow symbols in app icons.
- v1 uses the default generic app icon.
- Optional later: a 1024 px PNG, converted with `iconutil` into `Support/AppIcon.icns`, plus `CFBundleIconFile` in `Info.plist`.

---

## 12. App lifecycle and cleanup strategy

### Startup

```
1. macOS launches Awake.app (Finder, Spotlight, `open`, or login item).
   LSUIElement: no Dock icon, no app menu, not in Cmd-Tab.
2. AwakeMain: NSApplication.shared, create AppDelegate (strong ref), app.run().
3. applicationDidFinishLaunching:
   a. Single-instance guard: another running app with the same bundle ID
      and a different PID? Log and terminate self.
   b. preferences = Preferences()                                  [load prefs]
   c. keepAwake = KeepAwakeController(PowerAssertion(), preferences) [OFF, no assertion]
   d. loginItem = LoginItemController()
   e. statusItemController = StatusItemController(keepAwake, preferences, loginItem)
        - creates the status item with the OFF icon
        - builds the menu once
        - sets keepAwake.onChange
   f. keepAwake.applyStartupBehavior():
        target = preferences.startupBehavior
                   .initialState(lastState: preferences.lastKeepAwakeState)
        try setOn(target)          // on failure: log only, no alert at login
        preferences.lastKeepAwakeState = isOn    // always
        onChange?(isOn)                          // always, syncs the icon
4. Idle. The run loop waits for clicks.
```

Steps 3e and 3f run in the same run-loop turn. The OFF icon never gets drawn before a startup ON state.

### Runtime

All changes go through `KeepAwakeController.setOn(_:)` (section 5).

### Quit

Triggers: menu "Quit Awake", logout, shutdown, restart.

```
NSApp.terminate(nil)
  -> applicationWillTerminate
       -> keepAwake.releaseForTermination()
            -> sleepPreventer.deactivate()   // no persist, no callback
```

The system removes the status item when the process exits. There are no other resources.

### Abnormal termination

Crash, `kill -9`, SIGTERM from `pkill`, or Force Quit:

- `applicationWillTerminate` does not run.
- `powerd` releases the assertion when the process dies.
- `lastKeepAwakeState` is already correct, because it was saved at each change.
- Restore Last State still works after a crash.

### Other lifecycle points

| Point | Handling |
|---|---|
| System sleep and wake | Nothing to do. The assertion persists. |
| Launch at login | Same path as manual launch |
| State restoration | `applicationSupportsSecureRestorableState` returns `true` (silences a macOS 14+ warning). No windows to restore. |
| Sudden termination | Do not set `NSSupportsSuddenTermination`. Correctness does not depend on `applicationWillTerminate` anyway. |

---

## 13. Proposed context menu structure

```
┌─────────────────────────────┐
│ ✓ Keep Awake                │
├─────────────────────────────┤
│ ✓ Start on Login            │    ┌──────────────────────┐
│   On Launch               ▸ │ ─► │   Keep Awake         │
├─────────────────────────────┤    │ ✓ Allow Sleep        │  (default)
│   Quit Awake           ⌘Q   │    │   Restore Last State │
└─────────────────────────────┘    └──────────────────────┘
```

| Item | Action | State | Key |
|---|---|---|---|
| Keep Awake | toggle Keep Awake now | `.on` / `.off` from `isOn` | none |
| separator | | | |
| Start on Login | `LoginItemController.toggle()` | `.on` / `.off` / `.mixed` from `status` | none |
| On Launch | submenu only | | |
| ↳ Keep Awake | set `startupBehavior = .keepAwake` | `.on` if selected | none |
| ↳ Allow Sleep | set `startupBehavior = .allowSleep` | `.on` if selected | none |
| ↳ Restore Last State | set `startupBehavior = .restoreLastState` | `.on` if selected | none |
| separator | | | |
| Quit Awake | `NSApp.terminate(nil)` | | ⌘Q |

Notes:

- The 3 submenu items share one action. Each stores its `StartupBehavior` in `representedObject`.
- Native macOS uses a checkmark for the selected item in a mutually exclusive group (for example Finder's View menu). So the standard `.on` checkmark is the correct "radio" look. No custom dots.
- `menuNeedsUpdate(_:)` on the root menu refreshes all states, including the submenu items.
- The menu is built once. Titles never change. Only states change.
- "Keep Awake" appears twice. The parent "On Launch" gives the submenu item its context.
- Set every item's `target` explicitly to the controller so auto-enabling works.

---

## 14. Proposed project and file structure

```
Awake/                                 project root (iCloud Drive)
├── .plan/
│   └── macos-keep-awake-app.md        this plan
├── Package.swift
├── Sources/
│   ├── Awake/
│   │   └── AwakeMain.swift            @main entry point
│   └── AwakeKit/
│       ├── AppDelegate.swift
│       ├── StatusItemController.swift
│       ├── KeepAwakeController.swift
│       ├── PowerAssertion.swift       SleepPreventing, PowerAssertion, PowerAssertionError
│       ├── LoginItemController.swift
│       └── Preferences.swift          StartupBehavior, Preferences
├── Tests/
│   └── AwakeKitTests/
│       ├── StartupBehaviorTests.swift
│       ├── PreferencesTests.swift
│       ├── KeepAwakeControllerTests.swift   includes a FakeSleepPreventer
│       └── PowerAssertionTests.swift        real powerd integration
├── Support/
│   └── Info.plist
└── scripts/
    ├── build-app.sh                   build, assemble, sign, optional install
    └── test.sh                        swift test with an out-of-iCloud scratch path
```

Outside the project:

| Path | Purpose |
|---|---|
| `~/Library/Caches/Awake-build/spm/` | SwiftPM scratch path (build and test) |
| `~/Library/Caches/Awake-build/Awake.app` | Freshly assembled and signed app |
| `~/Applications/Awake.app` | Installed copy that you run and register for login |

Expected size: about 400 to 600 lines of Swift, including tests.

### `Package.swift` settings

- `// swift-tools-version: 6.0`
- `name: "Awake"`, `platforms: [.macOS(.v13)]`
- product: `.executable(name: "Awake", targets: ["Awake"])`
- `executableTarget("Awake", dependencies: ["AwakeKit"])`
- `target("AwakeKit")` with `linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("ServiceManagement")]`
- `testTarget("AwakeKitTests", dependencies: ["AwakeKit"])`
- No package dependencies.

### Entry point sketch

```swift
import AppKit
import AwakeKit

@main
@MainActor
enum AwakeMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()   // NSApplication.delegate is weak. This local lives until exit.
        app.delegate = delegate
        app.run()
    }
}
```

`AppDelegate` must be `public` with a `public override init()`, because it is used from the executable module.

### `Info.plist`

| Key | Value |
|---|---|
| `CFBundleIdentifier` | `com.bachana.Awake` |
| `CFBundleName` | `Awake` |
| `CFBundleDisplayName` | `Awake` |
| `CFBundleExecutable` | `Awake` |
| `CFBundlePackageType` | `APPL` |
| `CFBundleShortVersionString` | `1.0.0` |
| `CFBundleVersion` | `1` |
| `CFBundleInfoDictionaryVersion` | `6.0` |
| `LSMinimumSystemVersion` | `13.0` |
| `LSUIElement` | `true` |
| `LSApplicationCategoryType` | `public.app-category.utilities` |
| `NSPrincipalClass` | `NSApplication` |
| `NSHighResolutionCapable` | `true` |
| `CFBundleIconFile` | only if `AppIcon.icns` is added later |

No entitlements file. No App Sandbox. No hardened runtime (only needed for notarization).

---

## 15. Implementation steps (exact order)

Each step ends with a gate. Do not start the next step until the gate passes.

| # | Step | Gate |
|---|---|---|
| 1 | Confirm open decisions (section 19, top). Default: bundle ID `com.bachana.Awake`. | Decision recorded |
| 2 | Scaffold: `Package.swift`, folders, `Info.plist`, `AwakeMain.swift`, minimal `AppDelegate` showing a status item with the outline icon and a Quit item. | `swift build` with out-of-iCloud scratch path succeeds |
| 3 | `scripts/build-app.sh` and `scripts/test.sh` (section 17). | Script builds `Awake.app`. `plutil -lint` passes. `codesign --verify --strict` passes. App launches, `pgrep -x Awake` finds it. |
| 4 | `Preferences.swift`: `StartupBehavior` and `Preferences`, plus tests. | `scripts/test.sh` passes |
| 5 | `PowerAssertion.swift`, plus real-`powerd` integration tests. | Tests pass. No leftover assertion for the test process. |
| 6 | `KeepAwakeController.swift`, plus tests with the fake. | Tests pass |
| 7 | `StatusItemController.swift`: icons, tooltip, click routing, menu with Keep Awake and Quit, `onChange` hook. Wire `AppDelegate`: startup sequence and `applicationWillTerminate`. | Build and tests pass. Agent runtime checks A3 (section 16) pass. |
| 8 | On Launch submenu with the 3 options. | Build passes. Agent check: selecting behavior via `defaults` then relaunching gives the right state. |
| 9 | `LoginItemController.swift`, Start on Login item, error alerts. | Build passes. Registration itself is a manual check by you (it changes persistent login configuration). |
| 10 | Single-instance guard in `AppDelegate`. | Launching a second copy leaves one icon |
| 11 | Polish: icon point size, tooltips, accessibility descriptions, log messages. | Visual check |
| 12 | Final `build-app.sh --install`. Run all agent checks. Hand over the manual checklist. | Section 16 A passes. B handed to you. |
| 13 | Optional: custom app icon, if you provide artwork. | Icon shows in Finder and Login Items |

---

## 16. Testing and verification checklist

### A. Automated (the implementing agent runs these)

**A1. Unit and integration tests** (`scripts/test.sh`, Swift Testing):

| Suite | Cases |
|---|---|
| `StartupBehaviorTests` | All 6 behavior × lastState combinations (parameterized). Default is `allowSleep`. Raw values are exactly `keepAwake`, `allowSleep`, `restoreLastState`. |
| `PreferencesTests` | Empty defaults give `allowSleep` and `false`. Invalid raw value gives `allowSleep`. Round trip of each behavior and of both Bool values. A new `Preferences` on the same suite reads the same values (relaunch simulation). |
| `KeepAwakeControllerTests` (fake) | `setOn(true)`: activates once, persists `true`, notifies once. Repeat `setOn(true)`: no-op. `setOn(false)`: deactivates, persists `false`. `toggle()` both ways. Activation failure: `isOn == false`, nothing persisted, no callback, error thrown. `releaseForTermination()`: inactive, `lastKeepAwakeState` stays `true`, no callback. `applyStartupBehavior()` for all 6 combinations: expected `isOn`, `lastKeepAwakeState == isOn`, callback exactly once. `allowSleep` with a stale stored `true` ends with stored `false`. |
| `PowerAssertionTests` (real `powerd`, `.serialized`) | `activate()` gives exactly 1 `PreventUserIdleSystemSleep` assertion for `getpid()` (via `IOPMCopyAssertionsByProcess`). Second `activate()` still gives 1. `deactivate()` gives 0. Second `deactivate()` is safe. 500 toggles: never more than 1, and 0 at the end. `deinit` of an active instance gives 0. |

**A2. Build checks:** `build-app.sh` succeeds. `plutil -lint` passes. `codesign --verify --strict --verbose=2` passes. `LSUIElement` is present in the bundled `Info.plist`.

**A3. Runtime checks without clicking.** These write only the app's own defaults domain, with the app not running:

```bash
defaults write com.bachana.Awake startupBehavior -string keepAwake
open "$HOME/Applications/Awake.app"
pmset -g assertions | grep -i awake
pmset -g | grep -i "sleep prevented"
defaults read com.bachana.Awake lastKeepAwakeState
pkill -x Awake
pmset -g assertions | grep -i awake
```

Expected:

- After `open`: one `PreventUserIdleSystemSleep` assertion named `Awake: Keep Awake is on`.
- `pmset -g` lists Awake under "sleep prevented by".
- `lastKeepAwakeState` is `1`.
- After `pkill`: no Awake assertion. This proves release on abnormal termination.

Repeat for:

| `startupBehavior` | `lastKeepAwakeState` before launch | Expected at launch |
|---|---|---|
| `allowSleep` | `true` | OFF, stored value becomes `0` |
| `restoreLastState` | `true` | ON |
| `restoreLastState` | `false` | OFF |

Finish with `defaults delete com.bachana.Awake` to restore first-launch defaults.

### B. Manual (you)

| # | Check | How | Expected |
|---|---|---|---|
| 1 | App launches | Open `~/Applications/Awake.app` | Icon appears in the menu bar |
| 2 | No unwanted window | Look at screen, Dock, Cmd-Tab | No window, no Dock icon, not in Cmd-Tab |
| 3 | Icon appears | Menu bar | Cup icon visible |
| 4 | OFF is outline | First launch (default Allow Sleep) | Outline cup |
| 5 | ON is filled | Turn on | Filled cup |
| 6 | Left click opens menu | Left click | Native menu under the icon, icon highlighted. Arrow keys and Return work, Esc closes. |
| 7 | Menu toggles | Click "Keep Awake" | Checkmark and icon change |
| 8 | Right click toggles | Right click, Control-click, two-finger click | State toggles, no menu opens |
| 9 | Immediate update | Any toggle | Icon changes at once. Tooltip matches. |
| 10 | Sleep prevention active | `pmset -g assertions \| grep -i awake` while ON | One Awake `PreventUserIdleSystemSleep` assertion |
| 11 | Released when OFF | Same command while OFF | No Awake assertion (other apps may still hold theirs) |
| 12 | Quit releases | Quit Awake, run the command again | No Awake assertion |
| 13 | No leaks | Right-click 20+ times quickly, then `pmset -g assertions \| grep -c "Awake"` | At most 1 (0 if OFF) |
| 14 | Start on Login enable | Click "Start on Login" | Checkmark on. macOS login item notification. Listed in System Settings > General > Login Items. |
| 15 | Start on Login disable | Click again | Checkmark off. Removed from Open at Login. |
| 16 | Checkmark shows real state | Switch Awake off in System Settings, then open the menu | Mixed (–) state. Clicking opens Login Items settings. |
| 17 | Really launches at login | Enable, log out, log in | Awake running (`pgrep -x Awake`) |
| 18 | Startup behavior changes | Pick each On Launch option | Selection moves |
| 19 | Only one selected | Look at the submenu | Exactly one checkmark |
| 20 | Keep Awake on Launch | Select, quit, relaunch | Starts ON |
| 21 | Allow Sleep on Launch | Select, quit while ON, relaunch | Starts OFF |
| 22 | Restore Last State (ON) | Select, turn ON, quit, relaunch | Starts ON |
| 23 | Restore Last State (OFF) | Select, turn OFF, quit, relaunch | Starts OFF |
| 24 | Prefs survive relaunch | `defaults read com.bachana.Awake` between launches | Values kept |
| 25 | Login launch uses same behavior | Start on Login + Keep Awake on Launch, log out and in. Repeat with Allow Sleep. | ON, then OFF |

Extra manual checks:

| Check | Expected |
|---|---|
| Crash: while ON, run `kill -9 $(pgrep -x Awake)` | Assertion gone. Relaunch with Restore Last State starts ON. |
| Apple menu > Sleep while ON | Mac sleeps (explicit sleep is not blocked). After wake, icon still filled, assertion still present. |
| Lid close while ON (laptop, no external display) | Mac sleeps |
| Light and dark menu bar, pressed highlight | Icon renders correctly in all cases |
| Right click right after the menu was closed | Toggles (proves the menu was detached) |
| Launch a second copy while running | Still one icon |
| Optional real idle test: while ON, run `while true; do date +%T; sleep 20; done` in Terminal. Stay idle longer than your sleep timer. | No time gap in the output. The display may turn off, which is expected. |

### C. What is unit-testable and what is not

| Logic | How it is tested |
|---|---|
| Startup resolution, preference parsing and defaults, controller state rules and persistence timing | Unit tests |
| Assertion create, release, and no-leak | Integration tests against real `powerd` |
| Startup path end to end, release on process death | Agent runtime checks (A3) |
| Click routing, menu look, icon look, login item, real login | Manual (B) |

---

## 17. Build and `.app` generation process

### Commands

```bash
./scripts/test.sh
```

```bash
./scripts/build-app.sh
```

```bash
./scripts/build-app.sh --install
```

- `test.sh` runs `swift test --scratch-path "$HOME/Library/Caches/Awake-build/spm"`.
- `build-app.sh` builds, assembles, and signs `~/Library/Caches/Awake-build/Awake.app`.
- `--install` also stops a running Awake, copies the app to `~/Applications/Awake.app`, and launches it.

### `build-app.sh` steps

1. `set -euo pipefail`. Resolve the project root from the script location. Quote every path (spaces and `~` in the iCloud path).
2. `swift build -c release --package-path "$ROOT" --scratch-path "$BUILD/spm"`
3. Get the binary folder with the same command plus `--show-bin-path`.
4. Assemble:
   - `rm -rf "$APP"`, then `mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"`
   - copy the `Awake` binary to `Contents/MacOS/Awake`
   - copy `Support/Info.plist` to `Contents/Info.plist`
   - copy `Support/AppIcon.icns` to `Contents/Resources/` if it exists
5. `plutil -lint "$APP/Contents/Info.plist"`
6. `xattr -cr "$APP"`. Defensive: avoids the codesign error "resource fork, Finder information, or similar detritus not allowed".
7. `codesign --force --sign "${AWAKE_SIGN_IDENTITY:--}" "$APP"`
8. `codesign --verify --strict --verbose=2 "$APP"`
9. With `--install`:
   - `pkill -x Awake || true`, then wait until the process is gone
   - `mkdir -p "$HOME/Applications"`, remove the old bundle, `ditto` the new one
   - `open "$HOME/Applications/Awake.app"`

`pkill` (SIGTERM) is safe here. The app never writes state on termination, and `powerd` releases the assertion when the process exits.

### Why build outside iCloud Drive

- iCloud would sync thousands of build files.
- iCloud can add extended attributes that break `codesign`.
- "Optimize Mac Storage" can evict build files.
- `--scratch-path` also keeps `.build/` out of the project folder.

Never run bare `swift build` or `swift test` in the project folder. Always use the scripts or pass `--scratch-path`.

Never use `swift run`. An unbundled binary has no `Info.plist`: it gets a Dock icon, a wrong defaults domain, and `SMAppService` fails.

### Signing

| Topic | Decision |
|---|---|
| Default | Ad-hoc (`-`). No Apple account, no certificate. |
| Gatekeeper | Locally built apps have no quarantine attribute, so they launch without prompts. |
| Apple Silicon | Requires a signature. Ad-hoc is enough. |
| `SMAppService` | Requires code signing. Ad-hoc is expected to be enough locally (verify in step 9). |
| Entitlements, sandbox, hardened runtime, notarization | None. Only needed for distribution. |

**Ad-hoc caveat:** the signature hash changes on every rebuild. macOS may treat a rebuilt app as a new login item, leaving stale or duplicate entries.

Mitigations, in order:

1. Register once from `~/Applications`. After reinstalling, toggle Start on Login off and on.
2. If that is not enough, use a stable identity. You create a self-signed code signing certificate in Keychain Access (Certificate Assistant > Create a Certificate, type Code Signing). The agent does not create certificates. Then build with:

```bash
AWAKE_SIGN_IDENTITY="Awake Local" ./scripts/build-app.sh --install
```

3. Or install Xcode and use a free Apple Development (Personal Team) certificate.

### Xcode alternative

If you prefer an Xcode project, install Xcode first. The same source files work in an AppKit app target with `LSUIElement` and "Sign to Run Locally". Not recommended now: it needs a large install and a generated project file, and gives no benefit for this app.

---

## 18. Potential risks and macOS limitations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Ad-hoc signing rejected by `SMAppService` (`kSMErrorInvalidSignature`) | Low | Start on Login fails | Error alert shows it. Switch to a self-signed identity (section 17). |
| Stale or duplicate Login Items entries after rebuilds (ad-hoc hash changes) | Medium | Cosmetic, or login item stops working until re-toggled | Stable install path. Re-toggle. Stable identity if needed. `sfltool resetbtm` only as your last resort. |
| iCloud Drive project location | Medium | Codesign errors, sync noise | Build output outside iCloud, `xattr -cr` before signing |
| `.leftMouseDown` plus `performClick` glitch | Low | Menu flickers | Switch to `.leftMouseUp` (section 8) |
| macOS 26+ right click at the very top menu bar edge is not delivered | Known report | Minor | Click on the icon itself. Not fixable in app code. |
| Status item hidden (notch overflow, or hidden in System Settings menu bar controls on newer macOS) | Low | App looks missing, since it has no Dock icon or window | QA note. Check menu bar settings. |
| Display sleeps and screen locks while ON | By design | May surprise if you expect the screen to stay on | Documented. See the open decision in section 19. |
| Managed Mac (MDM) policies | Unknown | Could restrict login items or override power settings | Not detectable in advance. Check if behavior differs. |
| Swift 6 strict concurrency friction with AppKit or IOKit | Low | Compile errors | All UI types `@MainActor`. `PowerAssertion` not isolated. Fall back to `swiftLanguageModes: [.v5]` only if blocked. |
| `kIOPMAssertionTypePreventUserIdleSystemSleep` not imported by Swift | Low | Compile error | Use the literal `"PreventUserIdleSystemSleep" as CFString` |
| Only verified on macOS 27 | Certain | Target is 13.0, but 13 to 26 are untested | APIs used exist since 13.0. Accept for personal use. |

---

## 19. Decisions that need special attention

### Open decisions (defaults chosen, confirm or change before implementation)

| Decision | Default in this plan | Alternative |
|---|---|---|
| Bundle identifier | `com.bachana.Awake` | Any reverse-DNS ID. Must be final before the first run. |
| Screen behavior while ON | System stays awake, **display may still sleep** (spec: idle system sleep) | Also keep the display on (Caffeine/Owly style): add a second `PreventUserIdleDisplaySleep` assertion |
| App icon | Generic icon in v1 | Provide a 1024 px PNG for a custom icon |

### Implementation pitfalls

1. **Never persist state on quit.** `releaseForTermination()` must not touch `lastKeepAwakeState`. Otherwise Restore Last State always restores OFF.
2. **Always persist the actual state at the end of startup**, even without a transition (section 6).
3. **Detach the menu after it closes** (`statusItem.menu = nil` in `menuDidClose(_:)`). Otherwise the next right click opens the menu.
4. **Never keep `statusItem.menu` set permanently.** The click action would never fire.
5. **`NSApplication.delegate` is weak.** Keep a strong reference to `AppDelegate`.
6. **No stored `isOn` flag.** Derive it from the assertion.
7. **Never cache Start on Login state.** Read `SMAppService.mainApp.status` on every menu open.
8. **Treat `kSMErrorAlreadyRegistered` and `kSMErrorJobNotFound` as success.**
9. **Activate the app before `NSAlert.runModal()`.** LSUIElement apps are not frontmost.
10. **Changing On Launch never changes the current state.**
11. **Clear the assertion ID even if release fails.** Never hold two assertions.
12. **Run only the installed copy** at `~/Applications/Awake.app`. Do not run the build copy and the installed copy together.
13. **No `swift run`, no bare `swift build` in the iCloud folder.**
14. **The agent must not register the login item, run `sfltool resetbtm`, create certificates, or change system power settings.** These are your manual steps.
15. **No PII or secrets in logs.** Log state changes and error codes only.

---

## 20. Implementation deviations

Recorded during implementation. The app design is unchanged. Most deviations are toolchain workarounds in the scripts.

| # | Deviation | Reason |
|---|---|---|
| 1 | New `scripts/common.sh`, shared by both scripts. When stale Swift 5.10 `*.private.swiftinterface` files sit next to SwiftPM's current `PackageDescription` module, it points `SWIFTPM_CUSTOM_LIBS_DIR` at a clean copy without them. | This Command Line Tools install has those stale files. Every `Package.swift` failed to link. Nothing in the toolchain is modified. |
| 2 | `build-app.sh` passes `-Xlinker -platform_version macos <min> <sdk>` and fails if `vtool` shows a different SDK. | The Swift Build backend recorded SDK 13.0 (the deployment target) in the binary. AppKit uses the recorded SDK for appearance and compatibility behavior. |
| 3 | `test.sh` passes `-Xswiftc -plugin-path <toolchain>/usr/lib/swift/host/plugins/testing`. | The Swift Build backend intermittently did not give the compiler the Swift Testing macro plugin ("plugin for module 'TestingMacros' not found"). About half of the runs failed before the fix. All runs passed after it. |
| 4 | `Package.swift` sets `swiftLanguageModes: [.v6]` explicitly. | Makes the Swift 6 mode independent of the tools version default. |
| 5 | Added `StatusItemControllerTests`: click routing for synthesized events, and the login item status to checkmark mapping. | Moves part of section 16 C "click routing" from manual to unit tests. |
| 6 | GUI checks ran through a scratch test library injected into the installed app (`DYLD_INSERT_LIBRARIES`), not through System Events. | This session has no Accessibility, event posting, or Screen Recording permission. On macOS 27 the menu bar items are drawn by `MenuBarAgent`, so the icon cannot be read from outside the app. Nothing was added to the app. |
| 7 | The harness in #6 toggled Start on Login off and on, and restored the user's starting state. | This contradicts pitfall 14. It was done to verify register, unregister, and the checkmark on the real app. It ended with one clean, enabled login item record. |
| 8 | Keep Awake ON also holds a `PreventUserIdleDisplaySleep` assertion (section 19 "Screen behavior while ON" changed to the alternative). Both assertions are created and released as one unit. If one fails, the other is rolled back. | Decided after testing: with only the system assertion, the display dimmed, turned off, and locked the screen, which felt like sleep. This matches Owly. |
