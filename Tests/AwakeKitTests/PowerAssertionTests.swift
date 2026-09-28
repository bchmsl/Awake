import Foundation
import IOKit.pwr_mgt
import Testing
@testable import AwakeKit

/// Integration tests against the real power management daemon.
///
/// Each test uses a unique assertion name and counts only this process's
/// assertions with that name, so other assertions on the system do not interfere.
@Suite(.serialized)
struct PowerAssertionTests {
    private let name = "AwakeTests \(UUID().uuidString)"
    /// Keep Awake holds exactly these, one of each.
    private let keepAwakeTypes = ["PreventUserIdleDisplaySleep", "PreventUserIdleSystemSleep"]

    @Test func activateCreatesSystemAndDisplayAssertions() throws {
        let assertion = PowerAssertion(name: name)
        try assertion.activate()
        defer { assertion.deactivate() }

        #expect(assertion.isActive)
        #expect(try assertionTypes(named: name).sorted() == keepAwakeTypes)
    }

    @Test func activatingTwiceKeepsOneSet() throws {
        let assertion = PowerAssertion(name: name)
        try assertion.activate()
        try assertion.activate()
        defer { assertion.deactivate() }

        #expect(try assertionTypes(named: name).sorted() == keepAwakeTypes)
    }

    /// If the second assertion fails, the first is released: never half on.
    @Test func failedCreateRollsBackEarlierAssertions() throws {
        let assertion = PowerAssertion(
            name: name,
            types: [kIOPMAssertionTypePreventUserIdleSystemSleep, "AwakeTestsNoSuchAssertionType"]
        )

        #expect(throws: PowerAssertionError.self) { try assertion.activate() }
        #expect(!assertion.isActive)
        #expect(try assertionTypes(named: name).isEmpty)
    }

    @Test func deactivateReleasesAssertion() throws {
        let assertion = PowerAssertion(name: name)
        try assertion.activate()
        assertion.deactivate()

        #expect(!assertion.isActive)
        #expect(try assertionTypes(named: name).isEmpty)
    }

    @Test func deactivateWhenInactiveIsSafe() throws {
        let assertion = PowerAssertion(name: name)
        assertion.deactivate()
        try assertion.activate()
        assertion.deactivate()
        assertion.deactivate()

        #expect(!assertion.isActive)
        #expect(try assertionTypes(named: name).isEmpty)
    }

    @Test func repeatedTogglingNeverLeaks() throws {
        let assertion = PowerAssertion(name: name)
        for _ in 0..<500 {
            try assertion.activate()
            #expect(try assertionTypes(named: name).count == keepAwakeTypes.count)
            assertion.deactivate()
            #expect(try assertionTypes(named: name).isEmpty)
        }
    }

    @Test func deinitReleasesActiveAssertion() throws {
        do {
            let assertion = PowerAssertion(name: name)
            try assertion.activate()
            #expect(try assertionTypes(named: name).count == keepAwakeTypes.count)
        }
        #expect(try assertionTypes(named: name).isEmpty)
    }
}

/// Assertion types currently held by this process under the given name.
private func assertionTypes(named name: String) throws -> [String] {
    var unmanaged: Unmanaged<CFDictionary>?
    let result = IOPMCopyAssertionsByProcess(&unmanaged)
    try #require(result == kIOReturnSuccess)
    guard let byProcess = unmanaged?.takeRetainedValue() as NSDictionary? else { return [] }

    let ownPID = ProcessInfo.processInfo.processIdentifier
    for (key, value) in byProcess {
        guard (key as? NSNumber)?.int32Value == ownPID, let assertions = value as? [NSDictionary] else { continue }
        return assertions
            .filter { $0["AssertName"] as? String == name }
            .compactMap { $0["AssertType"] as? String }
    }
    return []
}
