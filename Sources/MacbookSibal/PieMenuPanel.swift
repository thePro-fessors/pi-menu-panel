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
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 400),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.level = .statusBar
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.ignoresMouseEvents = true // Pass mouse events through to background since EventTap handles it
        
        let container = PieMenuContainerView(viewModel: viewModel)
        self.contentView = NSHostingView(rootView: container)
        
        setupCallbacks()
    }
    
    private func setupCallbacks() {
        let tapManager = EventTapManager.shared
        
        tapManager.onForceClick = { [weak self] location in
            self?.showMenu(at: location)
        }
        
        tapManager.onMouseDragged = { [weak self] location in
            self?.dragMenu(at: location)
        }
        
        tapManager.onMouseUp = { [weak self] in
            self?.releaseMenu()
        }
    }
    
    private func showMenu(at location: NSPoint) {
        self.initialLocation = location
        self.viewModel.mouseOffset = .zero
        
        // Position panel center at click location
        let originX = location.x - 200
        let originY = location.y - 200
        self.setFrameOrigin(NSPoint(x: originX, y: originY))
        
        self.alphaValue = 0.0
        self.makeKeyAndOrderFront(nil)
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1.0
        }
    }
    
    private func dragMenu(at location: NSPoint) {
        let dx = location.x - initialLocation.x
        let dy = location.y - initialLocation.y
        self.viewModel.mouseOffset = NSSize(width: dx, height: dy)
    }
    
    private func releaseMenu() {
        executeSelectedCommand()
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().alphaValue = 0.0
        } completionHandler: {
            Task { @MainActor in
                self.orderOut(nil)
                // Restore tap manager state
                EventTapManager.shared.isMenuOpen = false
            }
        }
    }
    
    private func executeSelectedCommand() {
        let dx = viewModel.mouseOffset.width
        let dy = viewModel.mouseOffset.height
        let distance = sqrt(dx*dx + dy*dy)
        
        let sectors = ConfigManager.shared.config.sectors
        let N = sectors.count
        
        // Minimum active radius matches cancelRadius in PieMenuView (45)
        if distance >= 45 && N > 0 {
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
            
            // Perform distinct success haptic feedback
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            
            // Run the configured command
            CommandRunner.run(selectedSector.command)
        } else {
            // Cancel feedback
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }
}
