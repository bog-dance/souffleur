import Foundation

/// Watches the config files and hands fresh vocabulary to the transcribers.
///
/// Both levels are needed: a descriptor on the file catches in-place appends, which
/// never touch the directory, while the directory catches the atomic replace most
/// editors do - that leaves the old descriptor pointing at an unlinked inode.
final class VocabularyWatcher: @unchecked Sendable {
    private let onChange: @Sendable (VocabularyConfig) -> Void
    private let queue = DispatchQueue(label: "souffleur.vocabulary-watcher")
    private var sources: [DispatchSourceFileSystemObject] = []
    private var pending: DispatchWorkItem?
    private var lastTermCount: Int

    private var watchedFiles: [String] { [Config.vocabularyPath, Config.configPath] }

    init(initial: VocabularyConfig, onChange: @escaping @Sendable (VocabularyConfig) -> Void) {
        self.onChange = onChange
        self.lastTermCount = initial.terms.count
    }

    func start() {
        let directory = Config.configDirectory
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

        queue.async { [weak self] in
            guard let self else { return }
            self.watchDirectory(directory)
            for path in self.watchedFiles { self.watchFile(path) }
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.pending?.cancel()
            for source in self.sources { source.cancel() }
            self.sources.removeAll()
        }
    }

    private func watchDirectory(_ path: String) {
        addSource(path: path, mask: [.write, .rename, .delete]) { [weak self] _ in
            self?.scheduleReload()
        }
    }

    private func watchFile(_ path: String) {
        addSource(path: path, mask: [.write, .extend, .attrib, .rename, .delete]) { [weak self] event in
            guard let self else { return }
            self.scheduleReload()
            // The file we were holding is gone - a replace, not an edit. Follow the new one.
            if event.contains(.rename) || event.contains(.delete) {
                self.queue.asyncAfter(deadline: .now() + 0.2) { self.watchFile(path) }
            }
        }
    }

    private func addSource(
        path: String,
        mask: DispatchSource.FileSystemEvent,
        handler: @escaping (DispatchSource.FileSystemEvent) -> Void
    ) {
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: mask,
            queue: queue
        )
        source.setEventHandler { [weak source] in
            guard let source else { return }
            handler(source.data)
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        sources.append(source)
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
            fflush(stdout)
            return
        }

        lastTermCount = vocabulary.terms.count
        print("Vocabulary reloaded: \(vocabulary.terms.count) terms.")
        fflush(stdout)
        onChange(vocabulary)
    }
}
