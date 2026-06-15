import Cocoa
import ServiceManagement

@MainActor
public class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var launchAtLoginItem: NSMenuItem?
    
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
            alert.informativeText = "Pie Menu is now running in the background. You can access it via the menu bar icon (🎛️) or by double-tapping the Option (⌥) key."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            
            // Bring the app to the front so the alert is visible
            NSApp.activate(ignoringOtherApps: true)
            
            alert.runModal()
        }
    }
    
    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
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
        menu.delegate = self
        
        let settingsItem = NSMenuItem(title: "Edit Commands...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        let autoStartItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        autoStartItem.target = self
        menu.addItem(autoStartItem)
        self.launchAtLoginItem = autoStartItem
        updateLaunchAtLoginMenuItemState()
        
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
            alert.informativeText = "Pie Menu is successfully monitoring Option key events globally."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
            tapManager.startMonitoring()
        } else {
            let alert = NSAlert()
            alert.messageText = "Accessibility Permission Required"
            alert.informativeText = "Pie Menu requires Accessibility permission to monitor keyboard events system-wide. Please enable it in System Settings."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Cancel")
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                tapManager.requestPermission()
            }
        }
    }
    
    @objc private func quitApp() {
        EventTapManager.shared.stopMonitoring()
        NSApp.terminate(nil)
    }
    
    // MARK: - NSMenuDelegate
    
    public func menuWillOpen(_ menu: NSMenu) {
        updateLaunchAtLoginMenuItemState()
    }
    
    private func updateLaunchAtLoginMenuItemState() {
        let status = SMAppService.mainApp.status
        launchAtLoginItem?.state = (status == .enabled) ? .on : .off
    }
    
    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
                print("Successfully unregistered Launch at Login")
            } else {
                try service.register()
                print("Successfully registered Launch at Login")
            }
        } catch {
            print("Failed to toggle Launch at Login: \(error)")
            let alert = NSAlert()
            alert.messageText = "Launch at Login Error"
            alert.informativeText = "Could not update launch setting: \(error.localizedDescription)"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
        updateLaunchAtLoginMenuItemState()
    }
}
