import AVFoundation
import FluidAudio
import Foundation

class Transcriber: @unchecked Sendable, TranscriberBackend {
    let engineName: String
    var isReady: Bool { isLoaded }
    private let modelName: String
    private let language: Language?
    private let vocabulary: VocabularyConfig
    private var manager: SlidingWindowAsrManager?
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

        let asr = SlidingWindowAsrManager(config: SlidingWindowAsrConfig.default.applying(language: language))
        try await asr.loadModels(models)

        if vocabulary.isActive {
            print("Loading CTC models for vocabulary boosting...")
            let ctcModels = try await CtcModels.downloadAndLoad()
            try await asr.configureVocabularyBoosting(
                vocabulary: Self.context(from: vocabulary),
                ctcModels: ctcModels
            )
            print("Vocabulary boosting: \(vocabulary.terms.count) terms.")
        }

        manager = asr
        isLoaded = true
        print("Model loaded.")
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

    func transcribe(audio: [Float], sampleRate: Double) async throws -> String {
        try await ensureModel()
        guard let manager else { return "" }

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

        try await manager.startStreaming(source: .microphone)
        await manager.streamAudio(buffer)
        let text = try await manager.finish()
        try await manager.reset()

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
