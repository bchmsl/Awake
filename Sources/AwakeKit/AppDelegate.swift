import AppKit
import os

enum AppInfo {
    static let subsystem = Bundle.main.bundleIdentifier ?? "com.bachana.Awake"
}

private let logger = Logger(subsystem: AppInfo.subsystem, category: "App")

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var keepAwake: KeepAwakeController?
    private var statusItemController: StatusItemController?

    override public init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        if isAnotherInstanceRunning() {
            logger.info("Another instance is running, quitting")
            NSApp.terminate(nil)
            return
        }

        let preferences = Preferences()
        let keepAwake = KeepAwakeController(sleepPreventer: PowerAssertion(), preferences: preferences)
        self.keepAwake = keepAwake
        statusItemController = StatusItemController(
            keepAwake: keepAwake,
            preferences: preferences,
            loginItem: LoginItemController()
        )
        // Same run-loop turn as status item creation, so the icon never flashes the wrong state.
        keepAwake.applyStartupBehavior()
    }

    public func applicationWillTerminate(_ notification: Notification) {
        keepAwake?.releaseForTermination()
    }

    public func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    private func isAnotherInstanceRunning() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .contains { $0.processIdentifier != ownPID }
    }
}
