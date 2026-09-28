import AppKit
import AwakeKit

@main
@MainActor
enum AwakeMain {
    static func main() {
        let app = NSApplication.shared
        // NSApplication.delegate is weak. This local stays alive until the process exits.
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
