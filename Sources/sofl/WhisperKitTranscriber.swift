import Foundation
import WhisperKit

class WhisperKitTranscriber: @unchecked Sendable, TranscriberBackend {
    let engineName: String
    var isReady: Bool { isLoaded }
    private let modelName: String
    private let language: String
    private var whisperKit: WhisperKit?
    private var isLoaded = false
    private var loadingTask: Task<Void, Error>?
    var onProgress: ((String) -> Void)?

    init(alias: String, modelName: String, language: String) {
        self.engineName = alias
        self.modelName = modelName
        self.language = language
    }

    func ensureModel() async throws {
        guard !isLoaded else { return }

        if let existing = loadingTask {
            try await existing.value
            return
        }

        let task = Task { [self] in
            // Phase 1: Download
            onProgress?("downloading \(engineName)")
            let modelFolder = try await WhisperKit.download(
                variant: modelName,
                progressCallback: { [weak self] progress in
                    guard let self = self else { return }
                    let pct = Int(progress.fractionCompleted * 100)
                    DispatchQueue.main.async {
                        self.onProgress?("downloading \(self.engineName) \(pct)%")
                    }
                }
            )

            // Phase 2: Load & compile
            onProgress?("compiling \(engineName)")
            let wkConfig = WhisperKitConfig(
                modelFolder: modelFolder.path,
                prewarm: false,
                load: false
            )
            whisperKit = try await WhisperKit(wkConfig)

            // Phase 3: Warmup
            onProgress?("warmup \(engineName)")
            try await whisperKit?.prewarmModels()
            try await whisperKit?.loadModels()

            isLoaded = true
            onProgress?("")
        }
        loadingTask = task
        do {
            try await task.value
        } catch {
            loadingTask = nil
            throw error
        }
    }

    func transcribe(audio: [Float], sampleRate: Double) async throws -> String {
        try await ensureModel()
        guard let pipe = whisperKit else { return "" }

        let samples: [Float]
        if abs(sampleRate - 16000.0) > 1.0 {
            samples = Self.resample(audio, from: sampleRate, to: 16000.0)
        } else {
            samples = audio
        }

        let options = DecodingOptions(
            language: language,
            usePrefillPrompt: true
        )

        let results = try await pipe.transcribe(
            audioArray: samples,
            decodeOptions: options
        )

        return results.map { $0.text }.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func resample(_ audio: [Float], from srcRate: Double, to dstRate: Double) -> [Float] {
        let ratio = dstRate / srcRate
        let newCount = Int(Double(audio.count) * ratio)
        var result = [Float](repeating: 0, count: newCount)
        for i in 0..<newCount {
            let srcIdx = Double(i) / ratio
            let lo = Int(srcIdx)
            let hi = min(lo + 1, audio.count - 1)
            let frac = Float(srcIdx - Double(lo))
            result[i] = audio[lo] * (1 - frac) + audio[hi] * frac
        }
        return result
    }
}
