import Foundation

/// The daemon runs from a copy at a path that never changes between releases.
///
/// macOS keys Accessibility and Microphone grants of a bare binary to its path (plus a
/// code requirement that the stable SoflDev signature keeps satisfied). Homebrew moves
/// the binary to a new Cellar directory on every upgrade, so running from there costs a
/// re-grant each release. launchd still starts the Homebrew symlink; that process
/// refreshes the copy when the release changed and execs it, keeping the same PID.
enum StableBinary {
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("souffleur/bin")
    }

    static var binary: URL { directory.appendingPathComponent("sofl") }

    static func execFromStableCopy() {
        guard let current = Bundle.main.executableURL?.resolvingSymlinksInPath() else { return }
        let sourceDir = current.deletingLastPathComponent()
        guard sourceDir.standardizedFileURL.path != directory.standardizedFileURL.path else { return }

        do {
            if !sameContents(current, binary) {
                try install(from: sourceDir)
                print("Installed \(current.path) to \(binary.path)")
            }
        } catch {
            print("Warning: could not install \(binary.path): \(error.localizedDescription). Running from \(current.path)")
            return
        }

        var args = CommandLine.arguments
        args[0] = binary.path
        fflush(stdout)
        fflush(stderr)
        let cArgs = args.map { strdup($0) } + [nil]
        execv(binary.path, cArgs)
        print("Warning: exec \(binary.path) failed (errno \(errno)). Running from \(current.path)")
    }

    /// The binary loads its SwiftPM resource bundles from its own directory, so they
    /// travel with it. The new set is staged and swapped in whole.
    private static func install(from sourceDir: URL) throws {
        let fm = FileManager.default
        let parent = directory.deletingLastPathComponent()
        let staging = parent.appendingPathComponent("bin.new")
        let previous = parent.appendingPathComponent("bin.old")
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        for leftover in [staging, previous] where fm.fileExists(atPath: leftover.path) {
            try fm.removeItem(at: leftover)
        }
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)

        let items = try fm.contentsOfDirectory(atPath: sourceDir.path)
            .filter { $0 == "sofl" || $0.hasSuffix(".bundle") }
        for item in items {
            try fm.copyItem(at: sourceDir.appendingPathComponent(item), to: staging.appendingPathComponent(item))
        }

        if fm.fileExists(atPath: directory.path) { try fm.moveItem(at: directory, to: previous) }
        try fm.moveItem(at: staging, to: directory)
        try? fm.removeItem(at: previous)
    }

    private static func sameContents(_ a: URL, _ b: URL) -> Bool {
        guard let da = FileManager.default.contents(atPath: a.path),
              let db = FileManager.default.contents(atPath: b.path) else { return false }
        return da == db
    }
}
