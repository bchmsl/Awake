import Foundation
import IOKit
import Testing
@testable import AwakeKit

final class FakeSleepPreventer: SleepPreventing {
    private(set) var isActive = false
    private(set) var activateCalls = 0
    private(set) var deactivateCalls = 0
    var failActivation = false

    func activate() throws {
        activateCalls += 1
        if failActivation { throw PowerAssertionError.createFailed(kIOReturnError) }
        isActive = true
    }

    func deactivate() {
        deactivateCalls += 1
        isActive = false
    }
}

@MainActor
final class KeepAwakeControllerTests {
    private let suiteName = "AwakeTests.\(UUID().uuidString)"
    private let defaults: UserDefaults
    private let preferences: Preferences
    private let fake = FakeSleepPreventer()
    private var notifications: [Bool] = []

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suiteName))
        preferences = Preferences(defaults: defaults)
    }

    deinit {
        // deinit is nonisolated. Remove the domain by name instead of touching `defaults`.
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    private func makeController() -> KeepAwakeController {
        let controller = KeepAwakeController(sleepPreventer: fake, preferences: preferences)
        controller.onChange = { [unowned self] in notifications.append($0) }
        return controller
    }

    // MARK: - Runtime changes

    @Test func turningOnActivatesPersistsAndNotifies() throws {
        let controller = makeController()
        try controller.setOn(true)

        #expect(controller.isOn)
        #expect(fake.activateCalls == 1)
        #expect(preferences.lastKeepAwakeState == true)
        #expect(notifications == [true])
    }

    @Test func settingSameStateIsNoOp() throws {
        let controller = makeController()
        try controller.setOn(true)
        try controller.setOn(true)

        #expect(fake.activateCalls == 1)
        #expect(notifications == [true])
    }

    @Test func turningOffDeactivatesPersistsAndNotifies() throws {
        let controller = makeController()
        try controller.setOn(true)
        try controller.setOn(false)

        #expect(!controller.isOn)
        #expect(fake.deactivateCalls == 1)
        #expect(preferences.lastKeepAwakeState == false)
        #expect(notifications == [true, false])
    }

    @Test func toggleFlipsBothWays() throws {
        let controller = makeController()
        try controller.toggle()
        #expect(controller.isOn)
        try controller.toggle()
        #expect(!controller.isOn)
        #expect(notifications == [true, false])
    }

    @Test func failedActivationKeepsStateAndPersistsNothing() {
        preferences.lastKeepAwakeState = false
        fake.failActivation = true
        let controller = makeController()

        #expect(throws: PowerAssertionError.self) { try controller.setOn(true) }
        #expect(!controller.isOn)
        #expect(preferences.lastKeepAwakeState == false)
        #expect(notifications.isEmpty)
    }

    /// Quitting must not overwrite the last state, or Restore Last State breaks.
    @Test func releaseForTerminationDoesNotPersistOrNotify() throws {
        let controller = makeController()
        try controller.setOn(true)
        controller.releaseForTermination()

        #expect(!controller.isOn)
        #expect(!fake.isActive)
        #expect(preferences.lastKeepAwakeState == true)
        #expect(notifications == [true])
    }

    // MARK: - Startup

    @Test(arguments: [
        (StartupBehavior.keepAwake, false, true),
        (StartupBehavior.keepAwake, true, true),
        (StartupBehavior.allowSleep, false, false),
        (StartupBehavior.allowSleep, true, false),
        (StartupBehavior.restoreLastState, false, false),
        (StartupBehavior.restoreLastState, true, true),
    ])
    func startupAppliesBehaviorAndMirrorsState(behavior: StartupBehavior, lastState: Bool, expected: Bool) {
        preferences.startupBehavior = behavior
        preferences.lastKeepAwakeState = lastState
        let controller = makeController()

        controller.applyStartupBehavior()

        #expect(controller.isOn == expected)
        #expect(preferences.lastKeepAwakeState == controller.isOn)
        #expect(notifications == [expected])
    }

    /// Allow Sleep starts OFF without a transition. The stale `true` must still be replaced.
    @Test func startupOverwritesStaleLastState() {
        preferences.startupBehavior = .allowSleep
        preferences.lastKeepAwakeState = true
        let controller = makeController()

        controller.applyStartupBehavior()

        #expect(preferences.lastKeepAwakeState == false)
        #expect(fake.activateCalls == 0)
    }

    @Test func startupActivationFailureEndsOffAndMirrorsState() {
        preferences.startupBehavior = .keepAwake
        fake.failActivation = true
        let controller = makeController()

        controller.applyStartupBehavior()

        #expect(!controller.isOn)
        #expect(preferences.lastKeepAwakeState == false)
        #expect(notifications == [false])
    }

    /// Changing the startup preference never changes the running state.
    @Test func changingStartupBehaviorDoesNotChangeState() throws {
        let controller = makeController()
        try controller.setOn(true)
        preferences.startupBehavior = .allowSleep

        #expect(controller.isOn)
        #expect(preferences.lastKeepAwakeState == true)
    }
}
