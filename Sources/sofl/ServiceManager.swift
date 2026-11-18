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
        guard let source = findBinary() else {
            print("Error: could not find sofl binary.")
            return
        }

        try? FileManager.default.createDirectory(atPath: logDir, withIntermediateDirectories: true)

        do {
            try StableBinary.refresh(from: URL(fileURLWithPath: source).resolvingSymlinksInPath())
            try plist(program: StableBinary.binary.path).write(toFile: plistPath, atomically: true, encoding: .utf8)
            shell("launchctl", "bootstrap", "gui/\(uid)", plistPath)
            print("Service installed and started.")
            print("Logs: \(logDir)/stdout.log")
            openAccessibilitySettings()
        } catch {
            print("Error installing service: \(error)")
        }
    }

    /// Plists from 1.7.1 and earlier start the Homebrew symlink. launchd keeps the job it
    /// loaded, so after rewriting the plist the job is reloaded from a helper in its own
    /// session: launchd kills the job's process group on bootout, and the helper must
    /// outlive it to bootstrap the new definition.
    static func pointAtStableCopy() {
        let program = StableBinary.binary.path
        guard let current = try? String(contentsOfFile: plistPath, encoding: .utf8),
              !current.contains("<string>\(program)</string>") else { return }
        do {
            try plist(program: program).write(toFile: plistPath, atomically: true, encoding: .utf8)
        } catch {
            print("Warning: could not update \(plistPath): \(error.localizedDescription)")
            return
        }
        print("Launch agent now starts \(program); reloading it")
        // bootstrap fails with EIO while the old job is still tearing down, hence the retries.
        let script = """
            sleep 2; /bin/launchctl bootout gui/\(uid)/\(label)
            for i in 1 2 3 4 5 6 7 8 9 10; do /bin/launchctl bootstrap gui/\(uid) '\(plistPath)' && break; sleep 1; done
            """
        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID))
        var pid: pid_t = 0
        let args = ["/bin/sh", "-c", script].map { strdup($0) } + [nil]
        if posix_spawn(&pid, "/bin/sh", nil, &attr, args, environ) != 0 {
            print("Warning: could not reload the launch agent; it switches at the next login")
        }
        posix_spawnattr_destroy(&attr)
    }

    private static func plist(program: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(program)</string>
                <string>service</string>
                <string>start</string>
                <string>--daemon</string>
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
    }

    static func uninstall() {
        shell("launchctl", "bootout", "gui/\(uid)/\(label)")
        try? FileManager.default.removeItem(atPath: plistPath)
        print("Service uninstalled.")
    }

    static func start() {
        guard FileManager.default.fileExists(atPath: plistPath) else {
            print("Service not installed. Run: sofl service install")
            return
        }
        shell("launchctl", "bootstrap", "gui/\(uid)", plistPath)
        print("Service started.")
    }

    static func stop() {
        shell("launchctl", "bootout", "gui/\(uid)/\(label)")
        print("Service stopped.")
    }

    static func restart() {
        shell("launchctl", "bootout", "gui/\(uid)/\(label)")
        if FileManager.default.fileExists(atPath: plistPath) {
            shell("launchctl", "bootstrap", "gui/\(uid)", plistPath)
        }
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

    static func findBinary() -> String? {
        // The Homebrew symlink, so the stable copy can follow it to each new Cellar release.
        let stable: [String] = [
            "/opt/homebrew/bin/sofl",
            "/usr/local/bin/sofl",
        ]
        for path in stable where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }

        let argv0 = ProcessInfo.processInfo.arguments.first ?? ""
        guard !argv0.isEmpty, FileManager.default.isExecutableFile(atPath: argv0) else { return nil }
        return (argv0 as NSString).resolvingSymlinksInPath
    }

    private static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        shell("open", url.absoluteString)
    }
}
