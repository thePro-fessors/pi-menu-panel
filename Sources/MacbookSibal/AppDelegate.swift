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
            alert.messageText = "Pie Menu 시작됨"
            alert.informativeText = "Pie Menu가 백그라운드에서 실행 중입니다. 메뉴 바의 과녁(🎯) 아이콘이나 Option(⌥) 키를 두 번 더블 탭하여 원형 메뉴를 호출할 수 있습니다."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "확인")
            
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
        if let image = NSImage(systemSymbolName: "target", accessibilityDescription: "Pie Menu") {
            image.isTemplate = true // Auto adapts to light/dark modes
            button.image = image
        } else {
            button.title = "☺︎"
        }
        
        let menu = NSMenu()
        menu.delegate = self
        
        let settingsItem = NSMenuItem(title: "명령어 편집...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        let autoStartItem = NSMenuItem(title: "로그인 시 자동 실행", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        autoStartItem.target = self
        menu.addItem(autoStartItem)
        self.launchAtLoginItem = autoStartItem
        updateLaunchAtLoginMenuItemState()
        
        menu.addItem(NSMenuItem.separator())
        
        let permissionItem = NSMenuItem(title: "손쉬운 사용 권한 확인...", action: #selector(checkPermission), keyEquivalent: "")
        permissionItem.target = self
        menu.addItem(permissionItem)
        
        let quitItem = NSMenuItem(title: "Pie Menu 종료", action: #selector(quitApp), keyEquivalent: "q")
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
            alert.messageText = "손쉬운 사용 권한 승인됨"
            alert.informativeText = "Pie Menu가 정상적으로 Option 키 이벤트를 감지하고 있습니다."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "확인")
            alert.runModal()
            tapManager.startMonitoring()
        } else {
            let alert = NSAlert()
            alert.messageText = "손쉬운 사용 권한 필요"
            alert.informativeText = "Pie Menu가 키보드 이벤트를 시스템 전역에서 감지하려면 손쉬운 사용(Accessibility) 권한이 필요합니다. 시스템 설정에서 권한을 부여해 주세요."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "시스템 설정 열기")
            alert.addButton(withTitle: "취소")
            
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
            alert.messageText = "자동 실행 설정 오류"
            alert.informativeText = "자동 실행 설정을 업데이트할 수 없습니다: \(error.localizedDescription)"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "확인")
            alert.runModal()
        }
        updateLaunchAtLoginMenuItemState()
    }
}
