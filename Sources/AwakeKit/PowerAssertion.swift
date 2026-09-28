import Foundation
import IOKit.pwr_mgt
import os

private let logger = Logger(subsystem: AppInfo.subsystem, category: "PowerAssertion")

/// Something that can keep the Mac and its display awake.
protocol SleepPreventing: AnyObject {
    var isActive: Bool { get }
    /// Starts preventing idle sleep. Does nothing if already active.
    func activate() throws
    /// Stops preventing idle sleep. Does nothing if not active. Never fails.
    func deactivate()
}

enum PowerAssertionError: LocalizedError {
    case createFailed(IOReturn)

    var errorDescription: String? {
        switch self {
        case .createFailed(let code):
            "macOS refused the sleep prevention request (IOReturn \(Self.hex(code)))."
        }
    }

    static func hex(_ code: IOReturn) -> String {
        String(format: "0x%08X", UInt32(bitPattern: code))
    }
}

/// Holds the IOKit assertions that keep the Mac awake, as one all-or-nothing unit.
///
/// - `PreventUserIdleSystemSleep` keeps the Mac awake.
/// - `PreventUserIdleDisplaySleep` keeps the display from dimming, turning off, and locking.
///
/// Both are needed. The system assertion alone lets the display dim and lock the screen.
/// The display assertion alone lets the Mac sleep once the display is turned off by hand.
/// Explicit sleep (Apple menu, lid close, low battery) still works. If the process dies,
/// `powerd` releases the assertions automatically.
///
/// Not actor-isolated so `deinit` can release the assertions. Use from the main thread only.
final class PowerAssertion: SleepPreventing {
    static let keepAwakeTypes = [
        kIOPMAssertionTypePreventUserIdleSystemSleep,
        kIOPMAssertionTypePreventUserIdleDisplaySleep,
    ]

    private let name: String
    private let types: [String]
    private var assertionIDs: [IOPMAssertionID] = []

    /// `types` exists for tests. The app always uses `keepAwakeTypes`.
    init(name: String = "Awake: Keep Awake is on", types: [String] = PowerAssertion.keepAwakeTypes) {
        self.name = name
        self.types = types
    }

    deinit {
        deactivate()
    }

    var isActive: Bool { !assertionIDs.isEmpty }

    func activate() throws {
        guard assertionIDs.isEmpty else { return }

        var created: [IOPMAssertionID] = []
        for type in types {
            var id = IOPMAssertionID(0)
            let result = IOPMAssertionCreateWithName(
                type as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                name as CFString,
                &id
            )
            guard result == kIOReturnSuccess else {
                logger.error("Assertion \(type, privacy: .public) create failed: \(PowerAssertionError.hex(result), privacy: .public)")
                // All or nothing: never stay half on.
                created.forEach(Self.release)
                throw PowerAssertionError.createFailed(result)
            }
            created.append(id)
        }
        assertionIDs = created
        logger.info("Assertions created: \(created, privacy: .public)")
    }

    func deactivate() {
        guard !assertionIDs.isEmpty else { return }
        // Clear first: after a failed release the IDs are invalid anyway. Never hold two sets.
        let ids = assertionIDs
        assertionIDs = []
        ids.forEach(Self.release)
    }

    private static func release(_ id: IOPMAssertionID) {
        let result = IOPMAssertionRelease(id)
        if result == kIOReturnSuccess {
            logger.info("Assertion released: \(id, privacy: .public)")
        } else {
            logger.error("Assertion release failed: \(PowerAssertionError.hex(result), privacy: .public)")
        }
    }
}
