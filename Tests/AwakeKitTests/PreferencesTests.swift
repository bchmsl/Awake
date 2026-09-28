import Foundation
import Testing
@testable import AwakeKit

/// Each test gets its own throwaway defaults domain.
final class PreferencesTests {
    private let suiteName = "AwakeTests.\(UUID().uuidString)"
    private let defaults: UserDefaults

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suiteName))
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func emptyDefaultsUseSafeValues() {
        let preferences = Preferences(defaults: defaults)
        #expect(preferences.startupBehavior == .allowSleep)
        #expect(preferences.lastKeepAwakeState == false)
    }

    @Test func invalidStoredBehaviorFallsBackToDefault() {
        defaults.set("somethingElse", forKey: "startupBehavior")
        #expect(Preferences(defaults: defaults).startupBehavior == .allowSleep)
    }

    @Test(arguments: StartupBehavior.allCases)
    func startupBehaviorRoundTrips(behavior: StartupBehavior) {
        let preferences = Preferences(defaults: defaults)
        preferences.startupBehavior = behavior
        #expect(preferences.startupBehavior == behavior)
        #expect(defaults.string(forKey: "startupBehavior") == behavior.rawValue)
    }

    @Test(arguments: [true, false])
    func lastStateRoundTrips(value: Bool) {
        let preferences = Preferences(defaults: defaults)
        preferences.lastKeepAwakeState = value
        #expect(preferences.lastKeepAwakeState == value)
    }

    /// A new instance on the same store behaves like a relaunch.
    @Test func valuesSurviveNewInstance() {
        let first = Preferences(defaults: defaults)
        first.startupBehavior = .restoreLastState
        first.lastKeepAwakeState = true

        let second = Preferences(defaults: defaults)
        #expect(second.startupBehavior == .restoreLastState)
        #expect(second.lastKeepAwakeState == true)
    }
}
