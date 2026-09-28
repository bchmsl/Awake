import Foundation

/// What Keep Awake does when the app launches.
///
/// Raw values are persisted in `UserDefaults`. Do not rename them.
enum StartupBehavior: String, CaseIterable, Sendable {
    case keepAwake
    case allowSleep
    case restoreLastState

    /// Safe default: a fresh install or a login launch never keeps the Mac awake unasked.
    static let defaultValue: StartupBehavior = .allowSleep

    /// The Keep Awake state to apply at launch.
    func initialState(lastState: Bool) -> Bool {
        switch self {
        case .keepAwake: true
        case .allowSleep: false
        case .restoreLastState: lastState
        }
    }
}

/// Typed access to the app's small set of persisted preferences.
final class Preferences {
    private enum Key {
        static let startupBehavior = "startupBehavior"
        static let lastKeepAwakeState = "lastKeepAwakeState"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var startupBehavior: StartupBehavior {
        get {
            defaults.string(forKey: Key.startupBehavior)
                .flatMap(StartupBehavior.init(rawValue:)) ?? .defaultValue
        }
        set { defaults.set(newValue.rawValue, forKey: Key.startupBehavior) }
    }

    /// Mirrors the active Keep Awake state while the app runs. Missing means `false`.
    var lastKeepAwakeState: Bool {
        get { defaults.bool(forKey: Key.lastKeepAwakeState) }
        set { defaults.set(newValue, forKey: Key.lastKeepAwakeState) }
    }
}
