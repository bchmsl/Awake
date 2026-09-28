import Testing
@testable import AwakeKit

struct StartupBehaviorTests {
    @Test(arguments: [
        (StartupBehavior.keepAwake, false, true),
        (StartupBehavior.keepAwake, true, true),
        (StartupBehavior.allowSleep, false, false),
        (StartupBehavior.allowSleep, true, false),
        (StartupBehavior.restoreLastState, false, false),
        (StartupBehavior.restoreLastState, true, true),
    ])
    func initialState(behavior: StartupBehavior, lastState: Bool, expected: Bool) {
        #expect(behavior.initialState(lastState: lastState) == expected)
    }

    @Test func defaultIsAllowSleep() {
        #expect(StartupBehavior.defaultValue == .allowSleep)
    }

    /// Raw values are persisted. Renaming them would silently reset saved preferences.
    @Test func rawValuesAreStable() {
        #expect(StartupBehavior.keepAwake.rawValue == "keepAwake")
        #expect(StartupBehavior.allowSleep.rawValue == "allowSleep")
        #expect(StartupBehavior.restoreLastState.rawValue == "restoreLastState")
        #expect(StartupBehavior.allCases.count == 3)
    }
}
