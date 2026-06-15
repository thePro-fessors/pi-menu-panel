import Cocoa
import CoreGraphics
import ApplicationServices

@MainActor
public class EventTapManager: ObservableObject {
    public static let shared = EventTapManager()
    
    @Published public var isPermissionGranted = false
    @Published public var isMonitoring = false
    @Published public var isMenuOpen = false
    
    public var initialLocation: NSPoint = .zero
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var hasTriggeredForCurrentClick = false
    
    // State variables for Long Press fallback (꾹 누르기 감지)
    private var isMouseDown = false
    private var mouseDownTime = Date()
    private let longPressThreshold: TimeInterval = 0.45
    private let dragCancelDistance: CGFloat = 35.0
    
    public var onForceClick: ((NSPoint) -> Void)?
    public var onMouseDragged: ((NSPoint) -> Void)?
    public var onMouseUp: (() -> Void)?
    
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
        
        let eventMask: UInt64 = (1 << CGEventType.leftMouseDown.rawValue) |
                        (1 << CGEventType.leftMouseDragged.rawValue) |
                        (1 << CGEventType.leftMouseUp.rawValue) |
                        (1 << 29) // 29 is the rawValue for NSEvent.EventType.pressure
        
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else {
                    return Unmanaged.passRetained(event)
                }
                
                return MainActor.assumeIsolated {
                    let manager = Unmanaged<EventTapManager>.fromOpaque(refcon).takeUnretainedValue()
                    return manager.handleEvent(proxy: proxy, type: type, event: event)
                }
            },
            userInfo: selfPointer
        ) else {
            print("Failed to create event tap.")
            return
        }
        
        self.eventTap = tap
        self.runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            self.isMonitoring = true
            print("Global event tap started monitoring.")
        }
    }
    
    public func stopMonitoring() {
        guard isMonitoring, let tap = eventTap, let source = runLoopSource else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        self.eventTap = nil
        self.runLoopSource = nil
        self.isMonitoring = false
        print("Global event tap stopped monitoring.")
    }
    
    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Safe debug logging using CGEvent C-API to prevent AppKit stage/pressure exception crashes
        let typeRaw = type.rawValue
        let subtype = event.getIntegerValueField(.mouseEventSubtype)
        let pressure = event.getDoubleValueField(.mouseEventPressure)
        print("[EventTap] Intercepted event type=\(typeRaw), subtype=\(subtype), pressure=\(String(format: "%.2f", pressure))")
        
        // If the menu is open, handle dragging and mouse up, and consume events
        if isMenuOpen {
            if type == .leftMouseDragged {
                let location = NSEvent.mouseLocation
                DispatchQueue.main.async { [weak self] in
                    self?.onMouseDragged?(location)
                }
                return nil // Consume event
            } else if type == .leftMouseUp {
                DispatchQueue.main.async { [weak self] in
                    self?.onMouseUp?()
                }
                isMouseDown = false
                hasTriggeredForCurrentClick = false
                return nil // Consume event
            }
        }
        
        // standard trigger logic
        if type == .leftMouseDown {
            if isMenuOpen {
                print("[EventTap] 메뉴가 열린 상태에서 새로운 클릭(MouseDown) 감지. 마우스 먹통 방지를 위해 메뉴 상태 강제 초기화.")
                isMenuOpen = false
                isMouseDown = false
                hasTriggeredForCurrentClick = false
                DispatchQueue.main.async {
                    PieMenuPanel.shared.alphaValue = 0.0
                    PieMenuPanel.shared.orderOut(nil)
                }
            }
            
            hasTriggeredForCurrentClick = false
            isMouseDown = true
            let clickTime = Date()
            mouseDownTime = clickTime
            let location = NSEvent.mouseLocation
            initialLocation = location
            
            let enableFallback = ConfigManager.shared.config.enableLongPressFallback
            print("[EventTap] Left mouse down at \(location). (롱프레스 예비 감지: \(enableFallback))")
            
            if enableFallback {
                // Start Long Press fallback timer
                DispatchQueue.main.asyncAfter(deadline: .now() + longPressThreshold) { [weak self] in
                    guard let self = self else { return }
                    if self.isMouseDown && self.mouseDownTime == clickTime && !self.isMenuOpen && !self.hasTriggeredForCurrentClick {
                        print("[EventTap] 꾹 누르기(Long-press) 시간 초과 조건 충족 (물리 압력 미지원 기기용). 메뉴 표시 시작.")
                        self.hasTriggeredForCurrentClick = true
                        self.isMenuOpen = true
                        
                        self.postFakeMouseUp(at: self.initialLocation)
                        
                        // Trigger haptic feedback
                        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                        
                        self.onForceClick?(self.initialLocation)
                    }
                }
            }
        }
        
        if type == .leftMouseUp {
            print("[EventTap] Left mouse up.")
            isMouseDown = false
            hasTriggeredForCurrentClick = false
        }
        
        if type == .leftMouseDragged && isMouseDown && !isMenuOpen {
            let currentLocation = NSEvent.mouseLocation
            let dx = currentLocation.x - initialLocation.x
            let dy = currentLocation.y - initialLocation.y
            let dist = sqrt(dx*dx + dy*dy)
            
            let enableFallback = ConfigManager.shared.config.enableLongPressFallback
            
            if enableFallback && dist > dragCancelDistance {
                print("[EventTap] 꾹 누르기 취소됨. 너무 많이 움직임: \(String(format: "%.1f", dist))px")
                isMouseDown = false
            }
        }
        
        // 4. Force Click 감지 (트랙패드 전용)
        if !hasTriggeredForCurrentClick && !isMenuOpen && isMouseDown {
            if let nsEvent = NSEvent(cgEvent: event) {
                let stageValue = SafeNSEvent.safeStage(for: nsEvent)
                
                // Force Click은 stage가 2가 됨
                if stageValue == 2 {
                    print("[EventTap] 물리 압력(Force Click) 임계값 도달 (Stage: 2). 즉시 메뉴 표시 시작.")
                    hasTriggeredForCurrentClick = true
                    isMouseDown = false
                    let location = NSEvent.mouseLocation
                    self.initialLocation = location
                    self.isMenuOpen = true
                    
                    self.postFakeMouseUp(at: location)
                    
                    NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                    
                    DispatchQueue.main.async { [weak self] in
                        self?.onForceClick?(location)
                    }
                    
                    return nil // Consume event
                }
            }
        }
        
        return Unmanaged.passRetained(event)
    }
    
    private func postFakeMouseUp(at location: NSPoint) {
        // CoreGraphics uses top-left origin, NSEvent uses bottom-left origin
        // But for CGEvent post, if we use the same CGEvent source it might be easier.
        // Actually, let's just use CGEvent mouse location
        guard let currentEvent = CGEvent(source: nil) else { return }
        let cgLocation = currentEvent.location
        if let fakeUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: cgLocation, mouseButton: .left) {
            fakeUp.post(tap: .cghidEventTap)
            print("[EventTap] 🖱️ Posted fake leftMouseUp to release system mouse lock")
        }
    }
}
