import Foundation

/// Watches the config directory and hands fresh vocabulary to the transcribers.
/// Editors replace files rather than writing in place, so the directory is the
/// stable thing to watch - a file descriptor on config.toml itself goes dead on
/// the first save.
final class VocabularyWatcher: @unchecked Sendable {
    private let onChange: @Sendable (VocabularyConfig) -> Void
    private let queue = DispatchQueue(label: "souffleur.vocabulary-watcher")
    private var source: DispatchSourceFileSystemObject?
    private var descriptor: CInt = -1
    private var pending: DispatchWorkItem?
    private var lastTermCount: Int

    init(initial: VocabularyConfig, onChange: @escaping @Sendable (VocabularyConfig) -> Void) {
        self.onChange = onChange
        self.lastTermCount = initial.terms.count
    }

    func start() {
        let directory = Config.configDirectory
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

        descriptor = open(directory, O_EVTONLY)
        guard descriptor >= 0 else {
            print("Warning: cannot watch \(directory), vocabulary edits need a restart")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete],
            queue: queue
        )
        source.setEventHandler { [weak self] in self?.scheduleReload() }
        source.setCancelHandler { [weak self] in
            guard let self, self.descriptor >= 0 else { return }
            close(self.descriptor)
            self.descriptor = -1
        }
        source.resume()
        self.source = source
    }

    func stop() {
        pending?.cancel()
        source?.cancel()
        source = nil
    }

    /// A single save fires several events, and an editor's temp file lands before the
    /// real one, so settle first and read once.
    private func scheduleReload() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.reload() }
        pending = work
        queue.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func reload() {
        let vocabulary = Config.loadVocabulary()

        // An empty read while terms were loaded means a half-written or broken file:
        // keep what is already boosting rather than dropping to nothing.
        if vocabulary.terms.isEmpty && lastTermCount > 0 {
            print("Vocabulary reload skipped: no terms parsed, keeping \(lastTermCount)")
            return
        }

        lastTermCount = vocabulary.terms.count
        print("Vocabulary reloaded: \(vocabulary.terms.count) terms.")
        onChange(vocabulary)
    }
}
