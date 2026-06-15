import Foundation

public enum SectorActionType: String, Codable, CaseIterable {
    case command = "Command"
    case openApp = "Open App"
    case shortcut = "Shortcut"
}

public struct SectorConfig: Codable, Identifiable {
    public var id: Int
    public var name: String
    public var actionType: SectorActionType
    public var command: String
    
    public init(id: Int, name: String, actionType: SectorActionType = .command, command: String) {
        self.id = id
        self.name = name
        self.actionType = actionType
        self.command = command
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case actionType
        case command
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(Int.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.actionType = try container.decodeIfPresent(SectorActionType.self, forKey: .actionType) ?? .command
        self.command = try container.decode(String.self, forKey: .command)
    }
}

public struct ProfileConfig: Codable, Identifiable {
    public var id: UUID
    public var name: String
    public var sectors: [SectorConfig]
    public var menuRadius: CGFloat
    public var themeColorHex: String
    
    public init(id: UUID = UUID(), name: String, sectors: [SectorConfig], menuRadius: CGFloat = 160.0, themeColorHex: String = "#92a8d1") {
        self.id = id
        self.name = name
        self.sectors = sectors
        self.menuRadius = menuRadius
        self.themeColorHex = themeColorHex
    }
}

public struct AppConfig: Codable {
    public var profiles: [ProfileConfig]
    public var activeProfileId: UUID
    
    public init(profiles: [ProfileConfig], activeProfileId: UUID) {
        self.profiles = profiles
        self.activeProfileId = activeProfileId
    }
    
    enum CodingKeys: String, CodingKey {
        case profiles
        case activeProfileId
        
        // Backward compatibility keys
        case sectors
        case menuRadius
        case themeColorHex
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        if let decodedProfiles = try container.decodeIfPresent([ProfileConfig].self, forKey: .profiles),
           let decodedActiveId = try container.decodeIfPresent(UUID.self, forKey: .activeProfileId) {
            self.profiles = decodedProfiles
            self.activeProfileId = decodedActiveId
        } else {
            // Backward compatibility handling: load old config format
            let sectors = try container.decodeIfPresent([SectorConfig].self, forKey: .sectors) ?? []
            let menuRadius = try container.decodeIfPresent(CGFloat.self, forKey: .menuRadius) ?? 160.0
            let themeColorHex = try container.decodeIfPresent(String.self, forKey: .themeColorHex) ?? "#92a8d1"
            
            let defaultProfile = ProfileConfig(name: "Default", sectors: sectors, menuRadius: menuRadius, themeColorHex: themeColorHex)
            self.profiles = [defaultProfile]
            self.activeProfileId = defaultProfile.id
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(profiles, forKey: .profiles)
        try container.encode(activeProfileId, forKey: .activeProfileId)
    }
}

@MainActor
public class ConfigManager: ObservableObject {
    public static let shared = ConfigManager()
    
    @Published public var config: AppConfig = AppConfig(profiles: [], activeProfileId: UUID())
    
    private let fileManager = FileManager.default
    private var configURL: URL {
        let homeDirectory = fileManager.homeDirectoryForCurrentUser
        let configDir = homeDirectory.appendingPathComponent(".config/pie-menu", isDirectory: true)
        try? fileManager.createDirectory(at: configDir, withIntermediateDirectories: true, attributes: nil)
        return configDir.appendingPathComponent("config.json")
    }
    
    // Computed property to access/update the active profile in memory
    public var activeProfile: ProfileConfig {
        get {
            if let profile = config.profiles.first(where: { $0.id == config.activeProfileId }) {
                return profile
            }
            if let first = config.profiles.first {
                return first
            }
            // Fallback profile if none exists
            let defaultProfile = ProfileConfig(name: "Default", sectors: [])
            return defaultProfile
        }
        set {
            if let index = config.profiles.firstIndex(where: { $0.id == newValue.id }) {
                config.profiles[index] = newValue
                objectWillChange.send()
            }
        }
    }
    
    private init() {
        loadConfig()
    }
    
    public func loadConfig() {
        let path = configURL.path
        let defaultSectors = [
            SectorConfig(id: 1, name: "Terminal", actionType: .openApp, command: "Terminal"),
            SectorConfig(id: 2, name: "VS Code", actionType: .command, command: "open -a 'Visual Studio Code' || open -a 'VS Code'"),
            SectorConfig(id: 3, name: "Finder", actionType: .command, command: "open ."),
            SectorConfig(id: 4, name: "Screenshot", actionType: .command, command: "screencapture -ic"),
            SectorConfig(id: 5, name: "Browser", actionType: .command, command: "open https://google.com"),
            SectorConfig(id: 6, name: "Activity Monitor", actionType: .openApp, command: "Activity Monitor")
        ]
        let defaultProfile = ProfileConfig(name: "Default", sectors: defaultSectors)
        
        if !fileManager.fileExists(atPath: path) {
            self.config = AppConfig(profiles: [defaultProfile], activeProfileId: defaultProfile.id)
            saveConfig()
        } else {
            do {
                let data = try Data(contentsOf: configURL)
                let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
                self.config = decoded
            } catch {
                print("Error loading config: \(error)")
                self.config = AppConfig(profiles: [defaultProfile], activeProfileId: defaultProfile.id)
            }
        }
    }
    
    public func saveConfig() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(config)
            try data.write(to: configURL)
        } catch {
            print("Error saving config: \(error)")
        }
    }
    
    // Updates active profile without committing to file immediately
    public func updateActiveProfileWithoutSaving(_ profile: ProfileConfig) {
        if let index = config.profiles.firstIndex(where: { $0.id == profile.id }) {
            config.profiles[index] = profile
            objectWillChange.send()
        }
    }
    
    // Updates active profile and writes config to file
    public func updateActiveProfile(_ profile: ProfileConfig) {
        updateActiveProfileWithoutSaving(profile)
        saveConfig()
    }
    
    // Switches to the previous profile in the loop
    public func switchToPreviousProfile() {
        guard !config.profiles.isEmpty else { return }
        if let index = config.profiles.firstIndex(where: { $0.id == config.activeProfileId }) {
            let prevIndex = (index - 1 + config.profiles.count) % config.profiles.count
            config.activeProfileId = config.profiles[prevIndex].id
            objectWillChange.send()
        }
    }
    
    // Switches to the next profile in the loop
    public func switchToNextProfile() {
        guard !config.profiles.isEmpty else { return }
        if let index = config.profiles.firstIndex(where: { $0.id == config.activeProfileId }) {
            let nextIndex = (index + 1) % config.profiles.count
            config.activeProfileId = config.profiles[nextIndex].id
            objectWillChange.send()
        }
    }
    
    // Creates a new profile with basic default sectors
    public func createNewProfile() {
        let count = config.profiles.count
        let defaultSectors = [
            SectorConfig(id: 1, name: "Terminal", actionType: .openApp, command: "Terminal"),
            SectorConfig(id: 2, name: "Finder", actionType: .command, command: "open ."),
            SectorConfig(id: 3, name: "Browser", actionType: .command, command: "open https://google.com")
        ]
        let newProfile = ProfileConfig(name: "Profile \(count + 1)", sectors: defaultSectors)
        config.profiles.append(newProfile)
        config.activeProfileId = newProfile.id
        objectWillChange.send()
    }
    
    // Deletes the active profile and falls back to the first available profile
    public func deleteActiveProfile() {
        guard config.profiles.count > 1 else { return }
        if let index = config.profiles.firstIndex(where: { $0.id == config.activeProfileId }) {
            config.profiles.remove(at: index)
            config.activeProfileId = config.profiles[0].id
            objectWillChange.send()
        }
    }
}
