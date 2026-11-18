import FluidAudio
import Foundation

/// Parakeet v3 builds souffleur can run. Both use FluidAudio's v3 layout, and
/// AsrModels.load only finds a build in a folder named `parakeet-tdt-0.6b-v3`.
enum ParakeetModel: String {
    /// ihnatov-yuri/parakeet-tdt-0.6b-v3-uk: Ukrainian + English fine-tune, the default.
    case ukrainian = "parakeet-tdt-0.6b-v3-uk"
    /// NVIDIA's multilingual v3 (25 languages), downloaded by FluidAudio.
    case stock = "parakeet-tdt-0.6b-v3-stock"

    static let folderName = "parakeet-tdt-0.6b-v3"

    /// The only model name before 1.7.1, so it says nothing about wanting stock;
    /// Config.load rewrites it to the default.
    static let legacyDefaultName = "parakeet-tdt-0.6b-v3"

    init(configName: String) {
        if let model = ParakeetModel(rawValue: configName) {
            self = model
        } else if configName == Self.legacyDefaultName {
            self = .ukrainian
        } else {
            print("Warning: unknown parakeet model '\(configName)', using \(ParakeetModel.ukrainian.rawValue)")
            self = .ukrainian
        }
    }

    /// The fine-tune does not emit Russian-only letters, and FluidAudio's `uk` filter
    /// also rejects every Latin token, which turns English words into Cyrillic.
    var usesLanguageFilter: Bool { self == .stock }
}

enum ParakeetModelStore {
    /// Application Support; a seam so the download and the stock hand-over can be tried in a scratch folder.
    static var appSupport: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!

    /// Where FluidAudio keeps stock v3; AsrModels.load(from:) takes this one's sibling.
    static var stockLoadDirectory: URL { appSupport.appendingPathComponent("souffleur") }
    private static var stockFolder: URL { appSupport.appendingPathComponent(ParakeetModel.folderName) }

    static var ukrainianFolder: URL {
        appSupport
            .appendingPathComponent("souffleur/models")
            .appendingPathComponent(ParakeetModel.ukrainian.rawValue)
            .appendingPathComponent(ParakeetModel.folderName)
    }

    static func isComplete(_ folder: URL) -> Bool {
        AsrModels.modelsExist(at: folder, version: .v3)
    }

    static func isUkrainianBuild(_ folder: URL) -> Bool {
        guard let data = FileManager.default.contents(atPath: folder.appendingPathComponent("config.json").path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = json["model_name"] as? String else { return false }
        return name == UkrainianModelDownload.repo
    }

    /// The fine-tune's folder, downloading it on first use. A build installed by hand
    /// in FluidAudio's stock location is used where it is, not fetched again.
    static func prepareUkrainian() async throws -> URL {
        if isComplete(ukrainianFolder) { return ukrainianFolder }
        if isComplete(stockFolder) && isUkrainianBuild(stockFolder) { return stockFolder }
        try await UkrainianModelDownload.download(to: ukrainianFolder)
        return ukrainianFolder
    }

    /// Switching to stock must not load a hand-installed fine-tune from the stock
    /// location, so it moves over to its own folder first.
    static func prepareStock() throws {
        guard FileManager.default.fileExists(atPath: stockFolder.path), isUkrainianBuild(stockFolder) else { return }
        var target = ukrainianFolder
        if FileManager.default.fileExists(atPath: target.path) {
            target = stockFolder.deletingLastPathComponent()
                .appendingPathComponent("\(ParakeetModel.folderName).uk-\(Int(Date().timeIntervalSince1970))")
        }
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: stockFolder, to: target)
        print("Moved the Ukrainian build out of the stock model folder to \(target.path)")
    }
}

/// Fetches the fine-tune's CoreML build from Hugging Face at a pinned revision.
enum UkrainianModelDownload {
    static let repo = "ihnatov-yuri/parakeet-tdt-0.6b-v3-uk"
    static let revision = "5c4bcfaca501587beaedfd23b72a678bf7194de1"
    static let subPath = "coreml/int8/parakeet-tdt-0.6b-v3"

    private struct Entry: Decodable {
        let type: String
        let path: String
        let size: Int64?
    }

    enum DownloadError: LocalizedError {
        case http(URL, Int)
        case sizeMismatch(String, expected: Int64, got: Int64)
        case incomplete(URL)

        var errorDescription: String? {
            switch self {
            case .http(let url, let code): return "HTTP \(code) for \(url.absoluteString)"
            case .sizeMismatch(let path, let expected, let got): return "\(path): expected \(expected) bytes, got \(got)"
            case .incomplete(let folder): return "Downloaded model at \(folder.path) is incomplete"
            }
        }
    }

    static func download(to folder: URL) async throws {
        let fm = FileManager.default
        let files = try await listFiles()
        let total = files.reduce(Int64(0)) { $0 + ($1.size ?? 0) }

        // Files land in a staging folder and it is renamed into place at the end, so a
        // complete-looking model folder always means a finished download. Staged files
        // survive an interrupted run and are skipped next time.
        let staging = folder.deletingLastPathComponent().appendingPathComponent(folder.lastPathComponent + ".partial")
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)

        var done: Int64 = 0
        for file in files {
            let size = file.size ?? 0
            let relative = String(file.path.dropFirst(subPath.count + 1))
            let destination = staging.appendingPathComponent(relative)

            if fileSize(destination) == size {
                done += size
                continue
            }

            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            let base = done
            let tmp = try await fetch(path: file.path) { written in
                printProgress(base + written, of: total)
            }
            let got = fileSize(tmp) ?? -1
            guard got == size else {
                try? fm.removeItem(at: tmp)
                throw DownloadError.sizeMismatch(file.path, expected: size, got: got)
            }
            if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
            try fm.moveItem(at: tmp, to: destination)
            done += size
            printProgress(done, of: total)
        }
        print("")

        if fm.fileExists(atPath: folder.path) { try fm.removeItem(at: folder) }
        try fm.moveItem(at: staging, to: folder)
        guard ParakeetModelStore.isComplete(folder) else { throw DownloadError.incomplete(folder) }
    }

    private static func listFiles() async throws -> [Entry] {
        var next: URL? = URL(string: "https://huggingface.co/api/models/\(repo)/tree/\(revision)/\(subPath)?recursive=true")
        var files: [Entry] = []
        while let url = next {
            let (data, response) = try await URLSession.shared.data(from: url)
            let http = response as? HTTPURLResponse
            guard http?.statusCode == 200 else { throw DownloadError.http(url, http?.statusCode ?? 0) }
            files += try JSONDecoder().decode([Entry].self, from: data).filter { $0.type == "file" }
            next = (http?.value(forHTTPHeaderField: "Link")).flatMap(nextPage)
        }
        return files
    }

    private static func nextPage(_ link: String) -> URL? {
        for part in link.split(separator: ",") where part.contains("rel=\"next\"") {
            guard let start = part.firstIndex(of: "<"), let end = part.firstIndex(of: ">") else { continue }
            return URL(string: String(part[part.index(after: start)..<end]))
        }
        return nil
    }

    private static func fetch(path: String, progress: @escaping (Int64) -> Void) async throws -> URL {
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        let url = URL(string: "https://huggingface.co/\(repo)/resolve/\(revision)/\(encoded)")!
        let (downloaded, response) = try await URLSession.shared.download(from: url, delegate: ProgressDelegate(progress))
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else {
            try? FileManager.default.removeItem(at: downloaded)
            throw DownloadError.http(url, code)
        }
        let kept = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.moveItem(at: downloaded, to: kept)
        return kept
    }

    private static func fileSize(_ url: URL) -> Int64? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
    }

    private static func printProgress(_ done: Int64, of total: Int64) {
        guard total > 0 else { return }
        print("Downloading model: \(Int(done * 100 / total))%...", terminator: "\r")
        fflush(stdout)
    }

    private final class ProgressDelegate: NSObject, URLSessionDownloadDelegate {
        private let progress: (Int64) -> Void
        private var lastPrinted: Int64 = 0

        init(_ progress: @escaping (Int64) -> Void) { self.progress = progress }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
            guard totalBytesWritten - lastPrinted >= 8 << 20 else { return }
            lastPrinted = totalBytesWritten
            progress(totalBytesWritten)
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
    }
}
