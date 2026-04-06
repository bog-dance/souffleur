import Foundation

enum ServiceManager {
    private static let label = "com.souffleur.daemon"
    private static let uid = getuid()

    private static var plistPath: String {
        NSHomeDirectory() + "/Library/LaunchAgents/\(label).plist"
    }

    private static var logDir: String {
        NSHomeDirectory() + "/.local/share/souffleur"
    }

    static func install() {
        guard let binaryPath = findBinary() else {
            print("Error: could not find sofl binary.")
            return
        }

        // Create log directory
        try? FileManager.default.createDirectory(atPath: logDir, withIntermediateDirectories: true)

        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(binaryPath)</string>
                <string>run</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
            <key>StandardOutPath</key>
            <string>\(logDir)/stdout.log</string>
            <key>StandardErrorPath</key>
            <string>\(logDir)/stderr.log</string>
        </dict>
        </plist>
        """

        do {
            try plist.write(toFile: plistPath, atomically: true, encoding: .utf8)
            shell("launchctl", "bootstrap", "gui/\(uid)", plistPath)
            print("Service installed and started.")
            print("Logs: \(logDir)/stdout.log")
            openAccessibilitySettings()
        } catch {
            print("Error writing plist: \(error)")
        }
    }

    static func uninstall() {
        shell("launchctl", "bootout", "gui/\(uid)/\(label)")
        try? FileManager.default.removeItem(atPath: plistPath)
        print("Service uninstalled.")
    }

    static func restart() {
        shell("launchctl", "kickstart", "-k", "gui/\(uid)/\(label)")
        print("Service restarted.")
    }

    static func status() {
        let result = shell("launchctl", "print", "gui/\(uid)/\(label)")
        if result == nil {
            print("Service is not installed.")
        }
    }

    @discardableResult
    private static func shell(_ args: String...) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)
            if let output = output, !output.isEmpty {
                print(output)
            }
            return process.terminationStatus == 0 ? output : nil
        } catch {
            return nil
        }
    }

    private static func findBinary() -> String? {
        // Check common locations
        let candidates: [String] = [
            "/opt/homebrew/bin/sofl",
            "/usr/local/bin/sofl",
            ProcessInfo.processInfo.arguments.first ?? "",
        ]
        for path in candidates {
            guard !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) else { continue }
            return path
        }
        return nil
    }

    private static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        shell("open", url.absoluteString)
    }
}
