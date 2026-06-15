import Foundation
import Cocoa

public struct CommandRunner {
    private static let keyCodes: [String: CGKeyCode] = [
        "a": 0, "b": 11, "c": 8, "d": 2, "e": 14, "f": 3, "g": 5, "h": 4, "i": 34, "j": 38,
        "k": 40, "l": 37, "m": 46, "n": 45, "o": 31, "p": 35, "q": 12, "r": 15, "s": 1,
        "t": 17, "u": 32, "v": 9, "w": 13, "x": 7, "y": 16, "z": 6,
        "0": 29, "1": 18, "2": 19, "3": 20, "4": 21, "5": 23, "6": 22, "7": 26, "8": 28, "9": 25,
        "space": 49, "enter": 36, "return": 36, "tab": 48, "esc": 53, "escape": 53,
        "up": 126, "down": 125, "left": 123, "right": 124,
        "backspace": 51, "delete": 51, "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96,
        "f6": 97, "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111
    ]

    public static func execute(type: SectorActionType, target: String) {
        switch type {
        case .command:
            runShell(target)
        case .openApp:
            openApp(target)
        case .shortcut:
            triggerShortcut(target)
        }
    }

    private static func runShell(_ command: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", command]
            process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
            
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                print("Failed to run command '\(command)': \(error)")
            }
        }
    }

    private static func openApp(_ appNameOrPath: String) {
        let trimmed = appNameOrPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        if trimmed.hasSuffix(".app") || trimmed.contains("/") {
            let url = URL(fileURLWithPath: trimmed)
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open(url, configuration: config) { _, error in
                if let error = error {
                    print("Failed to open app at path \(trimmed): \(error)")
                }
            }
        } else {
            if !NSWorkspace.shared.launchApplication(trimmed) {
                // Fallback to zsh open -a
                runShell("open -a \"\(trimmed)\"")
            }
        }
    }

    private static func triggerShortcut(_ shortcutString: String) {
        let parts = shortcutString.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !parts.isEmpty else { return }
        
        var flags = CGEventFlags()
        var targetKeyCode: CGKeyCode? = nil
        
        for part in parts {
            switch part {
            case "cmd", "command":
                flags.insert(.maskCommand)
            case "opt", "option", "alt":
                flags.insert(.maskAlternate)
            case "shift":
                flags.insert(.maskShift)
            case "ctrl", "control":
                flags.insert(.maskControl)
            default:
                if let code = keyCodes[part] {
                    targetKeyCode = code
                }
            }
        }
        
        guard let key = targetKeyCode else {
            print("Failed to parse key code for shortcut: \(shortcutString)")
            return
        }
        
        DispatchQueue.main.async {
            let source = CGEventSource(stateID: .combinedSessionState)
            
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true) else { return }
            keyDown.flags = flags
            keyDown.post(tap: .cghidEventTap)
            
            guard let keyUp = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) else { return }
            keyUp.flags = flags
            keyUp.post(tap: .cghidEventTap)
        }
    }
}
