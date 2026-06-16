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
    
    private func getNumberFromKeyCode(_ keyCode: UInt16) -> Int? {
        switch keyCode {
        case 18: return 1
        case 19: return 2
        case 20: return 3
        case 21: return 4
        case 23: return 5
        case 22: return 6
        case 26: return 7
        case 28: return 8
        case 25: return 9
        default: return nil
        }
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
        
        // Monitor for mouse down to close/execute menu, mouse moved for hover, scroll wheel, and ESC/arrows/numbers to control profiles
        let mouseHandler: (NSEvent) -> Void = { [weak self] event in
            guard let self = self else { return }
            if self.isMenuOpen {
                if event.type == .keyDown {
                    let keyCode = event.keyCode
                    if keyCode == 53 { // ESC key
                        DispatchQueue.main.async { [weak self] in
                            self?.isMenuOpen = false
                            PieMenuPanel.shared.releaseMenu(execute: false)
                        }
                        return
                    }
                    
                    // Left Arrow (123) / Right Arrow (124) keys
                    if keyCode == 123 {
                        DispatchQueue.main.async {
                            ConfigManager.shared.switchToPreviousProfile()
                            NotificationCenter.default.post(name: NSNotification.Name("ConfigUpdated"), object: nil)
                            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                        }
                        return
                    } else if keyCode == 124 {
                        DispatchQueue.main.async {
                            ConfigManager.shared.switchToNextProfile()
                            NotificationCenter.default.post(name: NSNotification.Name("ConfigUpdated"), object: nil)
                            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                        }
                        return
                    }
                    
                    // Number keys 1-9
                    if let number = self.getNumberFromKeyCode(keyCode) {
                        DispatchQueue.main.async {
                            let targetIndex = number - 1
                            let profiles = ConfigManager.shared.config.profiles
                            if targetIndex < profiles.count {
                                ConfigManager.shared.config.activeProfileId = profiles[targetIndex].id
                                ConfigManager.shared.objectWillChange.send()
                                ConfigManager.shared.saveConfig()
                                NotificationCenter.default.post(name: NSNotification.Name("ConfigUpdated"), object: nil)
                                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                            }
                        }
                        return
                    }
                    return
                }
                
                if event.type == .scrollWheel {
                    let dy = event.deltaY
                    if abs(dy) > 0.1 {
                        DispatchQueue.main.async {
                            if dy > 0 {
                                ConfigManager.shared.switchToPreviousProfile()
                            } else {
                                ConfigManager.shared.switchToNextProfile()
                            }
                            NotificationCenter.default.post(name: NSNotification.Name("ConfigUpdated"), object: nil)
                            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
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
        
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .mouseMoved, .keyDown, .scrollWheel], handler: mouseHandler)
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .mouseMoved, .keyDown, .scrollWheel]) { event in
            mouseHandler(event)
            
            if self.isMenuOpen {
                // Consume ESC, Arrow keys, Number keys to prevent system beep
                if event.type == .keyDown {
                    let keyCode = event.keyCode
                    if keyCode == 53 || keyCode == 123 || keyCode == 124 || self.getNumberFromKeyCode(keyCode) != nil {
                        return nil
                    }
                }
                // Consume Scroll wheel events to prevent scrolling background apps
                if event.type == .scrollWheel {
                    return nil
                }
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
        let cleanFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        
        // 1. Reset double tap state if any other modifier combination (Cmd, Shift, Ctrl) is pressed
        if cleanFlags.contains(.command) || cleanFlags.contains(.shift) || cleanFlags.contains(.control) {
            lastOptionPressTime = nil
            return
        }
        
        // 2. Only care about when the Option key is PRESSED (added to flags), not released
        // When Option is pressed exclusively, cleanFlags is exactly .option
        if cleanFlags == .option {
            let now = Date()
            if let last = lastOptionPressTime {
                let diff = now.timeIntervalSince(last)
                if diff < doubleTapThreshold {
                    // Double tap detected!
                    lastOptionPressTime = nil // Reset
                    
                    if !isMenuOpen {
                        print("[EventTap] Option Double-Tap detected! Opening menu.")
                        
                        // Switch active profile based on the current frontmost application
                        if let frontmostApp = NSWorkspace.shared.frontmostApplication {
                            let bundleId = frontmostApp.bundleIdentifier
                            let appName = frontmostApp.localizedName
                            ConfigManager.shared.switchProfileForApp(bundleId: bundleId, appName: appName)
                        }
                        
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
        // 3. When Option is released, cleanFlags becomes empty ([]), which we bypass safely without resetting
    }
}
