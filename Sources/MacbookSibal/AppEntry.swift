import Cocoa

@main
struct AppEntry {
    static var sharedDelegate: AppDelegate?
    
    static func main() {
        let app = NSApplication.shared
        let delegate = MainActor.assumeIsolated {
            AppDelegate()
        }
        sharedDelegate = delegate
        app.delegate = delegate
        app.run()
    }
}
