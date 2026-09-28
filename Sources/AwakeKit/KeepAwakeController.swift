import Foundation
import os

private let logger = Logger(subsystem: AppInfo.subsystem, category: "KeepAwake")

/// Single source of truth and single write path for the active Keep Awake state.
///
/// The state is never stored separately. It is derived from whether the sleep
/// preventer holds an assertion, so the UI cannot disagree with the system.
@MainActor
final class KeepAwakeController {
    private let sleepPreventer: any SleepPreventing
    private let preferences: Preferences

    /// Called after every state change, and once after startup.
    var onChange: ((Bool) -> Void)?

    init(sleepPreventer: any SleepPreventing, preferences: Preferences) {
        self.sleepPreventer = sleepPreventer
        self.preferences = preferences
    }

    var isOn: Bool { sleepPreventer.isActive }

    /// Applies the configured startup behavior. Call once at launch.
    ///
    /// Always persists the resulting state, even without a transition, so a stale
    /// value from an older session never survives.
    func applyStartupBehavior() {
        let behavior = preferences.startupBehavior
        let target = behavior.initialState(lastState: preferences.lastKeepAwakeState)
        do {
            _ = try apply(target)
        } catch {
            // No alert at launch (it may be a login launch). The icon shows the real state.
            logger.error("Startup activation failed: \(error.localizedDescription, privacy: .public)")
        }
        preferences.lastKeepAwakeState = isOn
        logger.info("Startup behavior \(behavior.rawValue, privacy: .public) applied, on: \(self.isOn, privacy: .public)")
        onChange?(isOn)
    }

    /// Turns Keep Awake on or off. Persists and notifies only when the state changes.
    func setOn(_ on: Bool) throws {
        guard try apply(on) else { return }
        preferences.lastKeepAwakeState = isOn
        logger.info("Keep Awake on: \(self.isOn, privacy: .public)")
        onChange?(isOn)
    }

    func toggle() throws {
        try setOn(!isOn)
    }

    /// Releases the assertion on quit. Does not persist: quitting is not a user choice
    /// to turn Keep Awake off, so Restore Last State must still see the running state.
    func releaseForTermination() {
        sleepPreventer.deactivate()
    }

    /// Returns `true` if the state changed.
    private func apply(_ on: Bool) throws -> Bool {
        guard on != isOn else { return false }
        if on {
            try sleepPreventer.activate()
        } else {
            sleepPreventer.deactivate()
        }
        return true
    }
}
