import AVFoundation
import FluidAudio
import Foundation

class Transcriber: @unchecked Sendable, TranscriberBackend {
    let engineName: String
    var isReady: Bool { isLoaded }
    private let modelName: String
    private let language: Language?
    private var vocabulary: VocabularyConfig
    private var models: AsrModels?
    private var ctcModels: CtcModels?
    private var isLoaded = false

    private static var modelsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("souffleur")
    }

    init(alias: String, modelName: String, language: String = "uk", vocabulary: VocabularyConfig = VocabularyConfig()) {
        self.engineName = alias
        self.modelName = modelName
        self.language = Language(rawValue: language)
        self.vocabulary = vocabulary
    }

    func ensureModel() async throws {
        guard !isLoaded else { return }
        print("Loading model: \(modelName) (CoreML)...")

        let modelsDir = Self.modelsDirectory
        try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)

        let models = try await AsrModels.load(from: modelsDir, version: .v3) { progress in
            let pct = Int(progress.fractionCompleted * 100)
            print("Downloading model: \(pct)%...", terminator: "\r")
            fflush(stdout)
        }
        print("")

        if vocabulary.isActive {
            print("Loading CTC models for vocabulary boosting...")
            ctcModels = try await CtcModels.downloadAndLoad()
            print("Vocabulary boosting: \(vocabulary.terms.count) terms.")
        }

        self.models = models
        isLoaded = true
        print("Model loaded.")
    }

    /// makeManager() rebuilds the boosting context per utterance, so swapping this
    /// takes effect on the next phrase without touching the loaded models.
    func updateVocabulary(_ vocabulary: VocabularyConfig) {
        self.vocabulary = vocabulary
    }

    private static func context(from config: VocabularyConfig) -> CustomVocabularyContext {
        let terms = config.terms.map { term in
            CustomVocabularyTerm(
                text: term.text,
                weight: term.weight,
                aliases: term.aliases.isEmpty ? nil : term.aliases,
                minSimilarity: term.minSimilarity
            )
        }
        let defaults = CustomVocabularyContext(terms: [])
        return CustomVocabularyContext(
            terms: terms,
            minSimilarity: config.minSimilarity ?? defaults.minSimilarity,
            minTermLength: config.minTermLength ?? defaults.minTermLength
        )
    }

    /// SlidingWindowAsrManager is single-use: finish() closes the input stream for good
    /// and reset() does not rebuild it, so each utterance gets a fresh manager over the
    /// already-loaded models.
    private func makeManager() async throws -> SlidingWindowAsrManager {
        guard let models else { throw ASRError.notInitialized }

        let manager = SlidingWindowAsrManager(
            config: SlidingWindowAsrConfig.default.applying(language: language)
        )
        try await manager.loadModels(models)

        if let ctcModels, vocabulary.isActive {
            try await manager.configureVocabularyBoosting(
                vocabulary: Self.context(from: vocabulary),
                ctcModels: ctcModels
            )
        }

        return manager
    }

    func transcribe(audio: [Float], sampleRate: Double) async throws -> String {
        try await ensureModel()

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else { return "" }

        let frameCount = AVAudioFrameCount(audio.count)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return "" }
        buffer.frameLength = frameCount

        if let channelData = buffer.floatChannelData {
            audio.withUnsafeBufferPointer { src in
                channelData[0].update(from: src.baseAddress!, count: audio.count)
            }
        }

        let manager = try await makeManager()
        try await manager.startStreaming(source: .microphone)
        await manager.streamAudio(buffer)
        let text = try await manager.finish()
        await manager.cleanup()

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
