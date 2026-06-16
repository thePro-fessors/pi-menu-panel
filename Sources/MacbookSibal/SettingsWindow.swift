import SwiftUI
import Cocoa
import UniformTypeIdentifiers

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
    
    func toHex() -> String {
        guard let nsColor = NSColor(self).usingColorSpace(.sRGB) else { return "#92a8d1" }
        let r = Int(nsColor.redComponent * 255)
        let g = Int(nsColor.greenComponent * 255)
        let b = Int(nsColor.blueComponent * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

struct SettingsView: View {
    @ObservedObject var configManager = ConfigManager.shared
    @State private var sectors: [SectorConfig] = []
    @State private var menuRadius: CGFloat = 160.0
    @State private var themeColor: Color = Color(hex: "#92a8d1")
    @State private var activeProfileName: String = ""
    @State private var targetAppBundleId: String = ""
    @State private var recordingSectorId: Int? = nil
    @State private var localEventMonitor: Any? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("Pie Menu 설정")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Text("원형 메뉴의 섹터 구성, 크기 및 테마 색상을 설정합니다.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Appearance Settings
            VStack(alignment: .leading, spacing: 10) {
                Text("화면 설정 (모든 프로필 공용)")
                    .font(.system(size: 12, weight: .bold))
                
                HStack {
                    Text("메뉴 반경: \(Int(menuRadius))px")
                        .font(.system(size: 12))
                        .frame(width: 130, alignment: .leading)
                    Slider(value: $menuRadius, in: 100...300, step: 10)
                }
                
                HStack {
                    Text("테마 색상")
                        .font(.system(size: 12))
                        .frame(width: 130, alignment: .leading)
                    ColorPicker("", selection: $themeColor)
                        .labelsHidden()
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // List of sectors
            ScrollView {
                VStack(spacing: 10) {
                    ForEach($sectors) { $sector in
                        HStack(spacing: 12) {
                            Text("\(sector.id)")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundColor(.secondary)
                                .frame(width: 18)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    TextField("섹터 이름", text: $sector.name)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(size: 12, weight: .semibold))
                                    
                                    Picker("", selection: $sector.actionType) {
                                        ForEach(SectorActionType.allCases, id: \.self) { type in
                                            Text(type.rawValue).tag(type)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .frame(width: 100)
                                    .font(.system(size: 10))
                                }
                                
                                HStack(spacing: 4) {
                                    if sector.actionType == .shortcut && recordingSectorId == sector.id {
                                        Text("단축키를 누르세요...")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(.blue)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(.horizontal, 8)
                                            .frame(height: 22)
                                            .background(Color.blue.opacity(0.1))
                                            .cornerRadius(4)
                                        
                                        Button("취소") {
                                            stopRecordingShortcut()
                                        }
                                        .buttonStyle(.plain)
                                        .font(.system(size: 10))
                                        .foregroundColor(.red)
                                    } else {
                                        TextField(placeholderText(for: sector.actionType), text: $sector.command)
                                            .textFieldStyle(.roundedBorder)
                                            .font(.system(size: 10, design: .monospaced))
                                        
                                        if sector.actionType == .openApp {
                                            Button(action: {
                                                selectAppForSector(sectorId: sector.id)
                                            }) {
                                                Image(systemName: "folder")
                                                    .font(.system(size: 10))
                                            }
                                            .buttonStyle(.plain)
                                            .help("응용 프로그램 선택")
                                        } else if sector.actionType == .shortcut {
                                            Button(action: {
                                                startRecordingShortcut(for: sector.id)
                                            }) {
                                                Image(systemName: "record.circle")
                                                    .foregroundColor(.red)
                                                    .font(.system(size: 10))
                                            }
                                            .buttonStyle(.plain)
                                            .help("단축키 입력 감지 시작")
                                        }
                                    }
                                }
                            }
                            
                            Button(action: {
                                deleteSector(sector.id)
                            }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 4)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(6)
                    }
                }
                .padding()
            }
            
            Divider()
            
            // Profile switcher bar
            HStack(spacing: 12) {
                Button(action: {
                    switchToPreviousProfile()
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .bold))
                }
                .buttonStyle(.plain)
                
                VStack(alignment: .leading, spacing: 3) {
                    TextField("프로필 이름", text: $activeProfileName)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 160)
                    
                    HStack(spacing: 4) {
                        TextField("연결할 앱 번들 ID (예: com.apple.Safari)", text: $targetAppBundleId)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 9))
                            .frame(width: 130)
                        
                        Button(action: {
                            selectAppFromApplicationsFolder()
                        }) {
                            Image(systemName: "folder")
                                .font(.system(size: 10))
                        }
                        .buttonStyle(.plain)
                        .help("응용 프로그램 폴더에서 앱 선택")
                    }
                    .frame(width: 160)
                }
                
                Button(action: {
                    switchToNextProfile()
                }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .bold))
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Button(action: {
                    createNewProfile()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle")
                        Text("새 프로필")
                    }
                    .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.bordered)
                
                if configManager.config.profiles.count > 1 {
                    Button(action: {
                        deleteActiveProfile()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "minus.circle")
                            Text("삭제")
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.red)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Footer buttons
            HStack(spacing: 12) {
                Button("섹터 추가") {
                    addSector()
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("기본값 초기화") {
                    resetDefaults()
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                
                Button("적용 및 저장") {
                    saveChanges()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 450, height: 565)
        .onAppear {
            // Reload configuration from disk to discard unsaved transitions
            configManager.loadConfig()
            self.menuRadius = configManager.config.menuRadius
            loadProfile(configManager.activeProfile)
        }
        .onDisappear {
            stopRecordingShortcut()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SettingsWindowWillClose"))) { _ in
            saveChangesWithoutClosing()
        }
    }
    
    private func selectAppFromApplicationsFolder() {
        let openPanel = NSOpenPanel()
        openPanel.title = "애플리케이션 선택"
        openPanel.showsResizeIndicator = true
        openPanel.showsHiddenFiles = false
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = false
        openPanel.allowedContentTypes = [.application]
        openPanel.directoryURL = URL(fileURLWithPath: "/Applications")
        
        openPanel.begin { response in
            if response == .OK, let url = openPanel.url {
                if let bundle = Bundle(url: url), let bundleId = bundle.bundleIdentifier {
                    self.targetAppBundleId = bundleId
                } else {
                    let name = url.deletingPathExtension().lastPathComponent
                    self.targetAppBundleId = name
                }
            }
        }
    }
    
    private func selectAppForSector(sectorId: Int) {
        let openPanel = NSOpenPanel()
        openPanel.title = "애플리케이션 선택"
        openPanel.showsResizeIndicator = true
        openPanel.showsHiddenFiles = false
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = false
        openPanel.allowedContentTypes = [.application]
        openPanel.directoryURL = URL(fileURLWithPath: "/Applications")
        
        openPanel.begin { response in
            if response == .OK, let url = openPanel.url {
                let appName = url.deletingPathExtension().lastPathComponent
                if let index = sectors.firstIndex(where: { $0.id == sectorId }) {
                    sectors[index].command = appName
                }
            }
        }
    }
    
    private func startRecordingShortcut(for sectorId: Int) {
        stopRecordingShortcut()
        
        self.recordingSectorId = sectorId
        
        self.localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            guard let currentRecId = self.recordingSectorId else { return event }
            
            if let shortcut = self.parseShortcut(from: event) {
                if let index = self.sectors.firstIndex(where: { $0.id == currentRecId }) {
                    self.sectors[index].command = shortcut
                }
                self.stopRecordingShortcut()
            }
            
            return nil
        }
    }
    
    private func stopRecordingShortcut() {
        self.recordingSectorId = nil
        if let monitor = self.localEventMonitor {
            NSEvent.removeMonitor(monitor)
            self.localEventMonitor = nil
        }
    }
    
    private func parseShortcut(from event: NSEvent) -> String? {
        var modifiers: [String] = []
        let flags = event.modifierFlags
        
        if flags.contains(.command) { modifiers.append("Cmd") }
        if flags.contains(.option) { modifiers.append("Option") }
        if flags.contains(.shift) { modifiers.append("Shift") }
        if flags.contains(.control) { modifiers.append("Ctrl") }
        
        var key = ""
        switch event.keyCode {
        case 123: key = "Left"
        case 124: key = "Right"
        case 125: key = "Down"
        case 126: key = "Up"
        case 53: key = "Esc"
        case 36: key = "Enter"
        case 49: key = "Space"
        case 51: key = "Delete"
        case 48: key = "Tab"
        default:
            if let chars = event.charactersIgnoringModifiers, !chars.isEmpty {
                let firstChar = chars.prefix(1).lowercased()
                key = firstChar
            } else {
                return nil
            }
        }
        
        if key.isEmpty { return nil }
        
        if modifiers.isEmpty {
            return key.uppercased()
        } else {
            let modifierStr = modifiers.joined(separator: "+")
            return "\(modifierStr)+\(key.uppercased())"
        }
    }

    private func loadProfile(_ profile: ProfileConfig) {
        self.sectors = profile.sectors
        self.themeColor = Color(hex: profile.themeColorHex)
        self.activeProfileName = profile.name
        self.targetAppBundleId = profile.targetAppBundleId ?? ""
    }
    
    private func backupCurrentProfileState() {
        var profile = configManager.activeProfile
        profile.name = activeProfileName
        profile.sectors = sectors
        profile.themeColorHex = themeColor.toHex()
        profile.targetAppBundleId = targetAppBundleId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : targetAppBundleId.trimmingCharacters(in: .whitespacesAndNewlines)
        configManager.updateActiveProfileWithoutSaving(profile)
    }
    
    private func switchToPreviousProfile() {
        backupCurrentProfileState()
        configManager.switchToPreviousProfile()
        loadProfile(configManager.activeProfile)
    }
    
    private func switchToNextProfile() {
        backupCurrentProfileState()
        configManager.switchToNextProfile()
        loadProfile(configManager.activeProfile)
    }
    
    private func createNewProfile() {
        backupCurrentProfileState()
        configManager.createNewProfile()
        loadProfile(configManager.activeProfile)
    }
    
    private func deleteActiveProfile() {
        configManager.deleteActiveProfile()
        loadProfile(configManager.activeProfile)
    }
    
    private func addSector() {
        let newId = (sectors.map { $0.id }.max() ?? 0) + 1
        sectors.append(SectorConfig(id: newId, name: "새 섹터", command: "echo 'hello'"))
    }
    
    private func deleteSector(_ id: Int) {
        sectors.removeAll { $0.id == id }
        // Reindex IDs
        for i in 0..<sectors.count {
            sectors[i].id = i + 1
        }
    }
    
    private func placeholderText(for type: SectorActionType) -> String {
        switch type {
        case .command:
            return "쉘 명령 (예: open -a Terminal)"
        case .openApp:
            return "앱 이름 또는 경로 (예: Safari 또는 /Applications/Safari.app)"
        case .shortcut:
            return "단축키 입력 (예: Cmd+C, Cmd+Option+Left)"
        }
    }

    private func resetDefaults() {
        let defaultSectors = [
            SectorConfig(id: 1, name: "Terminal", actionType: .openApp, command: "Terminal"),
            SectorConfig(id: 2, name: "VS Code", actionType: .command, command: "open -a 'Visual Studio Code' || open -a 'VS Code'"),
            SectorConfig(id: 3, name: "Finder", actionType: .command, command: "open ."),
            SectorConfig(id: 4, name: "Screenshot", actionType: .command, command: "screencapture -ic"),
            SectorConfig(id: 5, name: "Browser", actionType: .command, command: "open https://google.com"),
            SectorConfig(id: 6, name: "Activity Monitor", actionType: .openApp, command: "Activity Monitor")
        ]
        self.sectors = defaultSectors
        self.menuRadius = 160.0
        self.themeColor = Color(hex: "#92a8d1")
        self.targetAppBundleId = ""
    }
    
    private func saveChangesWithoutClosing() {
        // Apply global menuRadius setting
        configManager.config.menuRadius = menuRadius
        
        var profile = configManager.activeProfile
        profile.name = activeProfileName
        profile.sectors = sectors
        profile.themeColorHex = themeColor.toHex()
        profile.targetAppBundleId = targetAppBundleId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : targetAppBundleId.trimmingCharacters(in: .whitespacesAndNewlines)
        configManager.updateActiveProfile(profile)
        
        // Broadcast configuration change so PieMenuPanel can update its size if needed
        NotificationCenter.default.post(name: NSNotification.Name("ConfigUpdated"), object: nil)
    }
    
    private func saveChanges() {
        saveChangesWithoutClosing()
        NSSound.beep()
        SettingsWindowController.shared.close()
    }
}


@MainActor
public class SettingsWindowController {
    public static let shared = SettingsWindowController()
    
    private var window: NSWindow?
    
    private init() {}
    
    public func show() {
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let contentView = SettingsView()
        
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 490),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "Pie Menu 설정"
        newWindow.contentView = NSHostingView(rootView: contentView)
        newWindow.isReleasedWhenClosed = false
        newWindow.center()
        
        // Custom window delegate to prevent close, instead hiding the window
        let delegate = WindowDelegate()
        newWindow.delegate = delegate
        
        // Retain delegate via window property
        objc_setAssociatedObject(newWindow, &delegateKey, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        
        self.window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    public func close() {
        window?.orderOut(nil)
    }
    
    private class WindowDelegate: NSObject, NSWindowDelegate {
        func windowShouldClose(_ sender: NSWindow) -> Bool {
            NotificationCenter.default.post(name: NSNotification.Name("SettingsWindowWillClose"), object: nil)
            sender.orderOut(nil)
            return false
        }
    }
}

private var delegateKey: UInt8 = 0
