import SwiftUI
import Cocoa

struct SettingsView: View {
    @ObservedObject var configManager = ConfigManager.shared
    @State private var sectors: [SectorConfig] = []
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("Pie Menu Command Settings")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Text("Customize the sectors of your circular menu. Re-order, add, or edit commands.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.windowBackgroundColor))
            
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
                                TextField("Sector Label (e.g., Terminal)", text: $sector.name)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 12, weight: .semibold))
                                
                                TextField("Shell Command (e.g., open -a Terminal)", text: $sector.command)
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
        .frame(width: 450, height: 420)
        .onAppear {
            self.sectors = configManager.config.sectors
        }
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
    
    private func resetDefaults() {
        let defaultSectors = [
            SectorConfig(id: 1, name: "Terminal", command: "open -a Terminal"),
            SectorConfig(id: 2, name: "VS Code", command: "open -a 'Visual Studio Code' || open -a 'VS Code'"),
            SectorConfig(id: 3, name: "Finder", command: "open ."),
            SectorConfig(id: 4, name: "Screenshot", command: "screencapture -i ~/Desktop/screenshot.png"),
            SectorConfig(id: 5, name: "Browser", command: "open https://google.com"),
            SectorConfig(id: 6, name: "Activity Monitor", command: "open -a 'Activity Monitor'")
        ]
        self.sectors = defaultSectors
    }
    
    private func saveChanges() {
        configManager.config.sectors = sectors
        configManager.saveConfig()
        NSSound.beep()
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
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 420),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "Pie Menu Settings"
        newWindow.contentView = NSHostingView(rootView: contentView)
        newWindow.center()
        
        // Custom window delegate to release window on close
        let delegate = WindowDelegate { [weak self] in
            self?.window = nil
        }
        newWindow.delegate = delegate
        
        // Retain delegate via window property
        objc_setAssociatedObject(newWindow, &delegateKey, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        
        self.window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private class WindowDelegate: NSObject, NSWindowDelegate {
        let onClose: () -> Void
        
        init(onClose: @escaping () -> Void) {
            self.onClose = onClose
        }
        
        func windowWillClose(_ notification: Notification) {
            onClose()
        }
    }
}

private var delegateKey: UInt8 = 0
