import Cocoa
import SwiftUI

public class PieMenuViewModel: ObservableObject {
    @Published public var mouseOffset: NSSize = .zero
    
    public init() {}
}

struct PieMenuContainerView: View {
    @ObservedObject var viewModel: PieMenuViewModel
    
    var body: some View {
        PieMenuView(mouseOffset: viewModel.mouseOffset)
    }
}

@MainActor
public class PieMenuPanel: NSPanel {
    public static let shared = PieMenuPanel()
    
    private var viewModel = PieMenuViewModel()
    private var initialLocation: NSPoint = .zero
    
    private init() {
        let r = ConfigManager.shared.config.menuRadius
        let size = r * 2 + 50
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: size, height: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.level = .statusBar
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.ignoresMouseEvents = false // Allow mouse events, though global monitors also handle interaction
        
        let container = PieMenuContainerView(viewModel: viewModel)
        self.contentView = NSHostingView(rootView: container)
        
        setupCallbacks()
        
        NotificationCenter.default.addObserver(forName: NSNotification.Name("ConfigUpdated"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.updateSize()
            }
        }
    }
    
    private func updateSize() {
        let r = ConfigManager.shared.config.menuRadius
        let size = r * 2 + 50
        self.setContentSize(NSSize(width: size, height: size))
    }
    
    private func setupCallbacks() {
        let tapManager = EventTapManager.shared
        
        tapManager.onMenuTrigger = { [weak self] location in
            self?.showMenu(at: location)
        }
        
        tapManager.onMouseMoved = { [weak self] location in
            self?.hoverMenu(at: location)
        }
        
        tapManager.onMouseClick = { [weak self] location in
            self?.executeOrCancel(at: location)
        }
    }
    
    private func showMenu(at location: NSPoint) {
        self.initialLocation = location
        self.viewModel.mouseOffset = .zero
        
        // Position panel center at click location
        let r = ConfigManager.shared.config.menuRadius
        let size = r * 2 + 50
        let originX = location.x - size / 2
        let originY = location.y - size / 2
        self.setFrameOrigin(NSPoint(x: originX, y: originY))
        
        self.alphaValue = 0.0
        self.makeKeyAndOrderFront(nil)
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1.0
        }
    }
    
    private func hoverMenu(at location: NSPoint) {
        let dx = location.x - initialLocation.x
        let dy = location.y - initialLocation.y
        self.viewModel.mouseOffset = NSSize(width: dx, height: dy)
    }
    
    private func executeOrCancel(at location: NSPoint) {
        let dx = location.x - initialLocation.x
        let dy = location.y - initialLocation.y
        let distance = sqrt(dx*dx + dy*dy)
        
        let r = ConfigManager.shared.config.menuRadius
        let cancelRadius = r * 0.28125
        
        if distance >= cancelRadius {
            releaseMenu(execute: true)
        } else {
            releaseMenu(execute: false)
        }
    }
    
    public func releaseMenu(execute: Bool) {
        if execute {
            executeSelectedCommand()
        } else {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().alphaValue = 0.0
        } completionHandler: {
            Task { @MainActor in
                self.orderOut(nil)
                EventTapManager.shared.isMenuOpen = false
            }
        }
    }
    
    private func executeSelectedCommand() {
        let dx = viewModel.mouseOffset.width
        let dy = viewModel.mouseOffset.height
        let distance = sqrt(dx*dx + dy*dy)
        
        let sectors = ConfigManager.shared.activeProfile.sectors
        let N = sectors.count
        
        let r = ConfigManager.shared.config.menuRadius
        let cancelRadius = r * 0.28125
        
        if distance >= cancelRadius && N > 0 {
            let angle = atan2(dy, dx)
            var degrees = angle * 180.0 / .pi
            if degrees < 0 {
                degrees += 360.0
            }
            
            // Convert to clockwise degrees from North
            var clockDegrees = 90.0 - degrees
            if clockDegrees < 0 {
                clockDegrees += 360.0
            }
            
            let sectorWidth = 360.0 / Double(N)
            let index = Int(clockDegrees / sectorWidth) % N
            
            let selectedSector = sectors[index]
            
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            CommandRunner.execute(type: selectedSector.actionType, target: selectedSector.command)
        }
    }
}
