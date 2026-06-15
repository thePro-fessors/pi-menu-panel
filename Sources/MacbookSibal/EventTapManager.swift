import Cocoa

@MainActor
public class EventTapManager: ObservableObject {
    public static let shared = EventTapManager()
    
    @Published public var isPermissionGranted = false
    @Published public var isMonitoring = false
    @Published public var isMenuOpen = false
    
    private var globalFlagsMonitor: Any?
    private var localFlagsMonitor: Any?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    
    private var lastOptionPressTime: Date?
    private let doubleTapThreshold: TimeInterval = 0.3
    
    public var onMenuTrigger: ((NSPoint) -> Void)?
    public var onMouseMoved: ((NSPoint) -> Void)?
    public var onMouseClick: ((NSPoint) -> Void)?
    
    private init() {
        checkPermission()
    }
    
    public func checkPermission() {
        self.isPermissionGranted = AXIsProcessTrusted()
    }
    
    public func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        self.isPermissionGranted = trusted
    }
    
    public func startMonitoring() {
        guard !isMonitoring else { return }
        checkPermission()
        
        guard isPermissionGranted else {
            print("Cannot start monitoring: Accessibility permission is not granted.")
            return
        }
        
        // Monitor for Option key double tap
        let handler: (NSEvent) -> Void = { [weak self] event in
            self?.handleFlagsChanged(event)
        }
        
        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: handler)
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            handler(event)
            return event
        }
        
        // Monitor for mouse down to close/execute menu, mouse moved for hover, and ESC to cancel
        let mouseHandler: (NSEvent) -> Void = { [weak self] event in
            guard let self = self else { return }
            if self.isMenuOpen {
                if event.type == .keyDown {
                    if event.keyCode == 53 { // ESC key
                        DispatchQueue.main.async { [weak self] in
                            self?.isMenuOpen = false
                            PieMenuPanel.shared.releaseMenu(execute: false)
                        }
                    }
                    return
                }
                
                let location = NSEvent.mouseLocation
                if event.type == .mouseMoved {
                    DispatchQueue.main.async { [weak self] in
                        self?.onMouseMoved?(location)
                    }
                } else if event.type == .leftMouseDown {
                    DispatchQueue.main.async { [weak self] in
                        self?.onMouseClick?(location)
                    }
                }
            }
        }
        
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .mouseMoved, .keyDown], handler: mouseHandler)
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .mouseMoved, .keyDown]) { event in
            mouseHandler(event)
            // Consume ESC event locally to prevent system beep if PieMenu is active
            if event.type == .keyDown && event.keyCode == 53 && self.isMenuOpen {
                return nil
            }
            return event
        }
        
        self.isMonitoring = true
        print("Input monitor started (Option Double-Tap mode).")
    }
    
    public func stopMonitoring() {
        guard isMonitoring else { return }
        if let gm = globalFlagsMonitor { NSEvent.removeMonitor(gm) }
        if let lm = localFlagsMonitor { NSEvent.removeMonitor(lm) }
        if let gmm = globalMouseMonitor { NSEvent.removeMonitor(gmm) }
        if let lmm = localMouseMonitor { NSEvent.removeMonitor(lmm) }
        
        globalFlagsMonitor = nil
        localFlagsMonitor = nil
        globalMouseMonitor = nil
        localMouseMonitor = nil
        
        self.isMonitoring = false
        print("Input monitor stopped.")
    }
    
    private func handleFlagsChanged(_ event: NSEvent) {
        // Only care about when the Option key is PRESSED (added to flags), not released
        // When Option is pressed alone, the flags contain .option
        if event.modifierFlags.contains(.option) {
            let now = Date()
            if let last = lastOptionPressTime {
                let diff = now.timeIntervalSince(last)
                if diff < doubleTapThreshold {
                    // Double tap detected!
                    lastOptionPressTime = nil // Reset
                    
                    if !isMenuOpen {
                        print("[EventTap] Option Double-Tap detected! Opening menu.")
                        isMenuOpen = true
                        let location = NSEvent.mouseLocation
                        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                        
                        DispatchQueue.main.async { [weak self] in
                            self?.onMenuTrigger?(location)
                        }
                    }
                    return
                }
            }
            lastOptionPressTime = now
        }
    }
}
