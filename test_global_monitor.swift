import Cocoa

class Monitor {
    var monitor: Any?
    func start() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.pressure, .leftMouseDown]) { event in
            print("Global event: type=\(event.type.rawValue), stage=\(event.responds(to: #selector(getter: NSEvent.stage)) ? String(describing: event.stage) : "N/A"), pressure=\(event.pressure)")
            if event.type == .pressure && event.stage == 2 {
                print("FORCE CLICK DETECTED!")
            }
        }
        print("Monitoring started. Press hard anywhere. Press Ctrl+C to exit.")
    }
}

let m = Monitor()
m.start()
RunLoop.main.run()
