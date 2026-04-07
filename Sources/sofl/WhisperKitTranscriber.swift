import Foundation
import WhisperKit

class WhisperKitTranscriber: @unchecked Sendable, TranscriberBackend {
    let engineName = "whisper"
    var isReady: Bool { isLoaded }
    private let config: TranscriptionConfig
    private var whisperKit: WhisperKit?
    private var isLoaded = false

    init(config: TranscriptionConfig) {
        self.config = config
    }

    func ensureModel() async throws {
        guard !isLoaded else { return }
        let modelName = config.whisperModel
        print("Loading model: whisper \(modelName) (CoreML)...")

        let wkConfig = WhisperKitConfig(model: modelName)
        whisperKit = try await WhisperKit(wkConfig)

        isLoaded = true
        print("Whisper model loaded.")
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
            language: config.language,
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
