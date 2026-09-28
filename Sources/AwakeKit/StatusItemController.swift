import AppKit
import ServiceManagement
import os

private let logger = Logger(subsystem: AppInfo.subsystem, category: "StatusItem")

/// Owns the menu bar item: icon, click routing, and the menu.
///
/// Left click opens the menu. Right click (or Control-click) toggles Keep Awake.
/// The menu is attached to the status item only while it is open. If it stayed
/// attached, AppKit would open it on every click and never send the click action.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let keepAwake: KeepAwakeController
    private let preferences: Preferences
    private let loginItem: LoginItemController

    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let keepAwakeItem = NSMenuItem()
    private let startOnLoginItem = NSMenuItem()
    private var startupBehaviorItems: [NSMenuItem] = []

    private let onImage = StatusItemController.symbolImage("cup.and.saucer.fill", description: "Keep Awake on")
    private let offImage = StatusItemController.symbolImage("cup.and.saucer", description: "Keep Awake off")

    init(keepAwake: KeepAwakeController, preferences: Preferences, loginItem: LoginItemController) {
        self.keepAwake = keepAwake
        self.preferences = preferences
        self.loginItem = loginItem
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        statusItem.autosaveName = "AwakeStatusItem"
        configureButton()
        buildMenu()
        keepAwake.onChange = { [weak self] isOn in
            self?.updateButton(isOn: isOn)
        }
        updateButton(isOn: keepAwake.isOn)
    }

    // MARK: - Button

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        // Menus open on mouse down natively. The toggle fires once, on a completed right click.
        button.sendAction(on: [.leftMouseDown, .rightMouseUp])
    }

    private func updateButton(isOn: Bool) {
        guard let button = statusItem.button else { return }
        button.image = isOn ? onImage : offImage
        button.toolTip = isOn
            ? "Keep Awake is on. Right-click to turn off."
            : "Keep Awake is off. Right-click to turn on."
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if Self.isSecondaryClick(NSApp.currentEvent) {
            toggleKeepAwake()
        } else {
            showMenu()
        }
    }

    /// Right click, or Control-click (the macOS secondary click convention).
    /// Anything else, including keyboard or VoiceOver presses, opens the menu.
    static func isSecondaryClick(_ event: NSEvent?) -> Bool {
        guard let event else { return false }
        switch event.type {
        case .rightMouseDown, .rightMouseUp:
            return true
        case .leftMouseDown, .leftMouseUp:
            return event.modifierFlags.contains(.control)
        default:
            return false
        }
    }

    private func showMenu() {
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
    }

    // MARK: - Menu

    private func buildMenu() {
        menu.delegate = self

        keepAwakeItem.title = "Keep Awake"
        keepAwakeItem.action = #selector(keepAwakeSelected(_:))
        keepAwakeItem.target = self
        menu.addItem(keepAwakeItem)

        menu.addItem(.separator())

        startOnLoginItem.title = "Start on Login"
        startOnLoginItem.action = #selector(startOnLoginSelected(_:))
        startOnLoginItem.target = self
        menu.addItem(startOnLoginItem)

        let onLaunchMenu = NSMenu()
        startupBehaviorItems = StartupBehavior.allCases.map { behavior in
            let item = NSMenuItem(
                title: Self.title(for: behavior),
                action: #selector(startupBehaviorSelected(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = behavior
            onLaunchMenu.addItem(item)
            return item
        }
        let onLaunchItem = NSMenuItem(title: "On Launch", action: nil, keyEquivalent: "")
        onLaunchItem.submenu = onLaunchMenu
        menu.addItem(onLaunchItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Awake",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = NSApp
        menu.addItem(quitItem)
    }

    private static func title(for behavior: StartupBehavior) -> String {
        switch behavior {
        case .keepAwake: "Keep Awake"
        case .allowSleep: "Allow Sleep"
        case .restoreLastState: "Restore Last State"
        }
    }

    /// Reads every state fresh when the menu opens, so nothing can go stale.
    func menuNeedsUpdate(_ menu: NSMenu) {
        keepAwakeItem.state = keepAwake.isOn ? .on : .off

        let loginStatus = loginItem.status
        startOnLoginItem.state = Self.menuState(for: loginStatus)
        startOnLoginItem.toolTip = loginStatus == .requiresApproval
            ? "Turned off in System Settings. Click to open Login Items."
            : nil

        let selected = preferences.startupBehavior
        for item in startupBehaviorItems {
            item.state = (item.representedObject as? StartupBehavior) == selected ? .on : .off
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        // Detach, so the next right click toggles instead of opening the menu.
        statusItem.menu = nil
    }

    static func menuState(for status: SMAppService.Status) -> NSControl.StateValue {
        switch status {
        case .enabled: .on
        case .requiresApproval: .mixed
        default: .off
        }
    }

    // MARK: - Actions

    @objc private func keepAwakeSelected(_ sender: NSMenuItem) {
        toggleKeepAwake()
    }

    @objc private func startOnLoginSelected(_ sender: NSMenuItem) {
        do {
            try loginItem.toggle()
        } catch {
            showError(title: "Couldn't change Start on Login", error: error)
        }
    }

    @objc private func startupBehaviorSelected(_ sender: NSMenuItem) {
        guard let behavior = sender.representedObject as? StartupBehavior else { return }
        // Only the preference changes. The current state stays as it is.
        preferences.startupBehavior = behavior
    }

    private func toggleKeepAwake() {
        do {
            try keepAwake.toggle()
        } catch {
            // Only turning on can fail.
            showError(title: "Couldn't turn on Keep Awake", error: error)
        }
    }

    private func showError(title: String, error: Error) {
        logger.error("\(title, privacy: .public): \(error.localizedDescription, privacy: .public)")
        // Menu bar apps are never frontmost. Activate so the alert appears in front.
        if #available(macOS 14, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }

    // MARK: - Icons

    private static func symbolImage(_ name: String, description: String) -> NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: description)?
            .withSymbolConfiguration(configuration)
        else {
            logger.fault("Missing SF Symbol \(name, privacy: .public)")
            return NSImage(size: NSSize(width: 18, height: 18))
        }
        // Template: macOS tints it for light, dark, and tinted menu bars and the pressed state.
        image.isTemplate = true
        return image
    }
}
