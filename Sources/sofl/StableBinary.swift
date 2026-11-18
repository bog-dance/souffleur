import Foundation

/// The daemon runs from a copy at a path that never changes between releases.
///
/// macOS keys Accessibility and Microphone grants of a bare binary to the path launchd
/// started (plus a code requirement that the stable SoflDev signature keeps satisfying).
/// Homebrew moves the binary to a new Cellar directory on every upgrade, so the launch
/// agent starts this copy instead, and the copy follows the Homebrew symlink: when the
/// release behind it changed, it takes the new files and execs them in place.
enum StableBinary {
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("souffleur/bin")
    }

    static var binary: URL { directory.appendingPathComponent("sofl") }

    /// Copies `source` and the bundles beside it over the stable copy when they differ.
    @discardableResult
    static func refresh(from source: URL) throws -> Bool {
        guard source.standardizedFileURL.path != binary.standardizedFileURL.path,
              !sameContents(source, binary) else { return false }
        try install(from: source.deletingLastPathComponent())
        print("Installed \(source.path) to \(binary.path)")
        return true
    }

    /// Called first thing in the daemon. Returns only when the current process should
    /// keep running as is.
    static func execFromStableCopy() {
        guard let current = Bundle.main.executableURL?.resolvingSymlinksInPath() else { return }
        let runningStable = current.standardizedFileURL.path == binary.standardizedFileURL.path
        let source = runningStable
            ? ServiceManager.findBinary().map { URL(fileURLWithPath: $0).resolvingSymlinksInPath() }
            : current

        var changed = false
        if let source, FileManager.default.isExecutableFile(atPath: source.path) {
            do {
                changed = try refresh(from: source)
            } catch {
                print("Warning: could not install \(binary.path): \(error.localizedDescription)")
                return
            }
        }
        if !runningStable { ServiceManager.pointAtStableCopy() }
        guard changed || !runningStable else { return }

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
