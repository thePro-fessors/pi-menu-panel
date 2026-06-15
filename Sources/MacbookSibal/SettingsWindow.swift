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
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("Pie Menu Settings")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Text("Customize the sectors, size, and color of your circular menu.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Appearance Settings
            VStack(alignment: .leading, spacing: 10) {
                Text("Appearance (Shared across profiles)")
                    .font(.system(size: 12, weight: .bold))
                
                HStack {
                    Text("Menu Radius: \(Int(menuRadius))px")
                        .font(.system(size: 12))
                        .frame(width: 130, alignment: .leading)
                    Slider(value: $menuRadius, in: 100...300, step: 10)
                }
                
                HStack {
                    Text("Theme Color")
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
                                    TextField("Sector Label", text: $sector.name)
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
                                
                                TextField(placeholderText(for: sector.actionType), text: $sector.command)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 10, design: .monospaced))
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
                    TextField("Profile Name", text: $activeProfileName)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 160)
                    
                    HStack(spacing: 4) {
                        TextField("App: e.g., com.apple.Safari", text: $targetAppBundleId)
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
                        .help("Select app from Applications folder")
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
                        Text("New")
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
                            Text("Delete")
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
                Button("Add Sector") {
                    addSector()
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("Reset Defaults") {
                    resetDefaults()
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                
                Button("Apply & Save") {
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
    }
    
    private func selectAppFromApplicationsFolder() {
        let openPanel = NSOpenPanel()
        openPanel.title = "Select Application"
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
        sectors.append(SectorConfig(id: newId, name: "New Sector", command: "echo 'hello'"))
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
            return "Shell Command (e.g., open -a Terminal)"
        case .openApp:
            return "App Name or Path (e.g., Safari or /Applications/Safari.app)"
        case .shortcut:
            return "Key Shortcut (e.g., Cmd+C, Cmd+Option+Left)"
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
    
    private func saveChanges() {
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
        newWindow.title = "Pie Menu Settings"
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
            sender.orderOut(nil)
            return false
        }
    }
}

private var delegateKey: UInt8 = 0
