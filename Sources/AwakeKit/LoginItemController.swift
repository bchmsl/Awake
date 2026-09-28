import Foundation
import ServiceManagement
import os

private let logger = Logger(subsystem: AppInfo.subsystem, category: "LoginItem")

/// Start on Login through `SMAppService.mainApp` (macOS 13+).
///
/// macOS is the source of truth. The state is never cached, so changes made in
/// System Settings are always reflected.
@MainActor
final class LoginItemController {
    var status: SMAppService.Status { SMAppService.mainApp.status }

    func toggle() throws {
        switch status {
        case .enabled:
            try unregister()
        case .requiresApproval:
            // Registered, but the user switched it off in System Settings.
            SMAppService.openSystemSettingsLoginItems()
        case .notRegistered, .notFound:
            try register()
        @unknown default:
            try register()
        }
    }

    private func register() throws {
        do {
            try SMAppService.mainApp.register()
            logger.info("Registered as login item")
        } catch let error as NSError where error.code == kSMErrorAlreadyRegistered {
            logger.info("Already registered as login item")
        } catch let error as NSError where error.code == kSMErrorLaunchDeniedByUser {
            logger.info("Login item needs approval, opening System Settings")
            SMAppService.openSystemSettingsLoginItems()
        } catch {
            logger.error("Login item register failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    private func unregister() throws {
        do {
            try SMAppService.mainApp.unregister()
            logger.info("Unregistered login item")
        } catch let error as NSError where error.code == kSMErrorJobNotFound {
            logger.info("Login item was already unregistered")
        } catch {
            logger.error("Login item unregister failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }
}
