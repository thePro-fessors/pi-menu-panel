import Foundation

public struct CommandRunner {
    public static func run(_ command: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", command]
            
            // Set home directory as current working directory
            process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
            
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                print("Failed to run command '\(command)': \(error)")
            }
        }
    }
}
