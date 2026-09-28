import AppKit
import ServiceManagement
import Testing
@testable import AwakeKit

@MainActor
struct StatusItemControllerTests {
    @Test(arguments: [
        (NSEvent.EventType.rightMouseUp, NSEvent.ModifierFlags(), true),
        (NSEvent.EventType.rightMouseDown, NSEvent.ModifierFlags(), true),
        (NSEvent.EventType.leftMouseDown, NSEvent.ModifierFlags.control, true),
        (NSEvent.EventType.leftMouseDown, NSEvent.ModifierFlags(), false),
        (NSEvent.EventType.leftMouseUp, NSEvent.ModifierFlags(), false),
        (NSEvent.EventType.leftMouseDown, NSEvent.ModifierFlags.option, false),
    ])
    func clickRouting(type: NSEvent.EventType, modifiers: NSEvent.ModifierFlags, isSecondary: Bool) throws {
        let event = try #require(NSEvent.mouseEvent(
            with: type,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ))
        #expect(StatusItemController.isSecondaryClick(event) == isSecondary)
    }

    /// Keyboard and VoiceOver presses have no mouse event. They must open the menu.
    @Test func missingEventOpensMenu() {
        #expect(StatusItemController.isSecondaryClick(nil) == false)
    }

    @Test func loginItemStatusMapsToMenuState() {
        #expect(StatusItemController.menuState(for: .enabled) == .on)
        #expect(StatusItemController.menuState(for: .requiresApproval) == .mixed)
        #expect(StatusItemController.menuState(for: .notRegistered) == .off)
        #expect(StatusItemController.menuState(for: .notFound) == .off)
    }
}
