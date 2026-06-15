import Cocoa

@main
struct AppEntry {
    static func main() {
        let app = NSApplication.shared
        let delegate = MainActor.assumeIsolated {
            AppDelegate()
        }
        app.delegate = delegate
        app.run()
    }
}
