import Foundation

public struct SectorConfig: Codable, Identifiable {
    public var id: Int
    public var name: String
    public var command: String
    
    public init(id: Int, name: String, command: String) {
        self.id = id
        self.name = name
        self.command = command
    }
}

public struct AppConfig: Codable {
    public var sectors: [SectorConfig]
    public var enableLongPressFallback: Bool
    
    public init(sectors: [SectorConfig], enableLongPressFallback: Bool = true) {
        self.sectors = sectors
        self.enableLongPressFallback = enableLongPressFallback
    }
    
    enum CodingKeys: String, CodingKey {
        case sectors
        case enableLongPressFallback
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.sectors = try container.decode([SectorConfig].self, forKey: .sectors)
        self.enableLongPressFallback = try container.decodeIfPresent(Bool.self, forKey: .enableLongPressFallback) ?? true
    }
}

@MainActor
public class ConfigManager: ObservableObject {
    public static let shared = ConfigManager()
    
    @Published var config: AppConfig = AppConfig(sectors: [])
    
    private let fileManager = FileManager.default
    private var configURL: URL {
        let homeDirectory = fileManager.homeDirectoryForCurrentUser
        let configDir = homeDirectory.appendingPathComponent(".config/pie-menu", isDirectory: true)
        try? fileManager.createDirectory(at: configDir, withIntermediateDirectories: true, attributes: nil)
        return configDir.appendingPathComponent("config.json")
    }
    
    private init() {
        loadConfig()
    }
    
    public func loadConfig() {
        let path = configURL.path
        if !fileManager.fileExists(atPath: path) {
            let defaultSectors = [
                SectorConfig(id: 1, name: "Terminal", command: "open -a Terminal"),
                SectorConfig(id: 2, name: "VS Code", command: "open -a 'Visual Studio Code' || open -a 'VS Code'"),
                SectorConfig(id: 3, name: "Finder", command: "open ."),
                SectorConfig(id: 4, name: "Screenshot", command: "screencapture -i ~/Desktop/screenshot.png"),
                SectorConfig(id: 5, name: "Browser", command: "open https://google.com"),
                SectorConfig(id: 6, name: "Activity Monitor", command: "open -a 'Activity Monitor'")
            ]
            self.config = AppConfig(sectors: defaultSectors, enableLongPressFallback: true)
            saveConfig()
        } else {
            do {
                let data = try Data(contentsOf: configURL)
                let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
                self.config = decoded
            } catch {
                print("Error loading config: \(error)")
                let defaultSectors = [
                    SectorConfig(id: 1, name: "Terminal", command: "open -a Terminal"),
                    SectorConfig(id: 2, name: "VS Code", command: "open -a 'Visual Studio Code' || open -a 'VS Code'"),
                    SectorConfig(id: 3, name: "Finder", command: "open ."),
                    SectorConfig(id: 4, name: "Screenshot", command: "screencapture -i ~/Desktop/screenshot.png"),
                    SectorConfig(id: 5, name: "Browser", command: "open https://google.com"),
                    SectorConfig(id: 6, name: "Activity Monitor", command: "open -a 'Activity Monitor'")
                ]
                self.config = AppConfig(sectors: defaultSectors, enableLongPressFallback: true)
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
}
