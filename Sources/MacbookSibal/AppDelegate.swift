import Cocoa

@MainActor
public class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Prevent app from showing in the Dock (agent background app)
        NSApp.setActivationPolicy(.accessory)
        
        setupStatusItem()
        
        // Touch/initialize PieMenuPanel to register callbacks
        _ = PieMenuPanel.shared
        
        // Start monitoring if permission is already granted
        let tapManager = EventTapManager.shared
        if tapManager.isPermissionGranted {
            tapManager.startMonitoring()
        } else {
            // Prompt for permission on launch if not granted
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                tapManager.requestPermission()
                if tapManager.isPermissionGranted {
                    tapManager.startMonitoring()
                }
            }
        }
        
        // Show startup notification alert asynchronously AFTER launch completes
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Pie Menu Started"
            alert.informativeText = "Pie Menu is now running in the background. You can access it via the menu bar icon (🎛️) or by Force Clicking on your trackpad."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            
            // Bring the app to the front so the alert is visible
            NSApp.activate(ignoringOtherApps: true)
            
            alert.runModal()
        }
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        guard let button = statusItem?.button else { return }
        
        // Use a built-in symbol that resembles a radial menu
        if let image = NSImage(systemSymbolName: "circle.circle", accessibilityDescription: "Pie Menu") {
            image.isTemplate = true // Auto adapts to light/dark modes
            button.image = image
        } else {
            button.title = "🎛️"
        }
        
        let menu = NSMenu()
        
        let settingsItem = NSMenuItem(title: "Edit Commands...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        let fallbackItem = NSMenuItem(title: "Use 0.45s Long Press Fallback", action: #selector(toggleLongPressFallback), keyEquivalent: "")
        fallbackItem.target = self
        fallbackItem.state = ConfigManager.shared.config.enableLongPressFallback ? .on : .off
        menu.addItem(fallbackItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let permissionItem = NSMenuItem(title: "Check Accessibility Permission...", action: #selector(checkPermission), keyEquivalent: "")
        permissionItem.target = self
        menu.addItem(permissionItem)
        
        let quitItem = NSMenuItem(title: "Quit Pie Menu", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem?.menu = menu
    }
    
    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }
    
    @objc private func checkPermission() {
        let tapManager = EventTapManager.shared
        tapManager.checkPermission()
        
        if tapManager.isPermissionGranted {
            let alert = NSAlert()
            alert.messageText = "Accessibility Permission Granted"
            alert.informativeText = "Pie Menu is successfully monitoring Force Click events globally."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
            tapManager.startMonitoring()
        } else {
            let alert = NSAlert()
            alert.messageText = "Accessibility Permission Required"
            alert.informativeText = "Pie Menu requires Accessibility permission to monitor Force Click events system-wide. Please enable it in System Settings."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Cancel")
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                tapManager.requestPermission()
            }
        }
    }
    
    @objc private func toggleLongPressFallback(_ sender: NSMenuItem) {
        let newValue = !ConfigManager.shared.config.enableLongPressFallback
        ConfigManager.shared.config.enableLongPressFallback = newValue
        ConfigManager.shared.saveConfig()
        
        sender.state = newValue ? .on : .off
        print("[AppDelegate] Long press fallback option updated to: \(newValue)")
    }
    
    @objc private func quitApp() {
        EventTapManager.shared.stopMonitoring()
        NSApp.terminate(nil)
    }
}
