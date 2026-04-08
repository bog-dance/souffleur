import AVFoundation
import FluidAudio
import Foundation

class Transcriber: @unchecked Sendable, TranscriberBackend {
    let engineName: String
    var isReady: Bool { isLoaded }
    private let modelName: String
    private var asrManager: AsrManager?
    private var isLoaded = false

    private static var modelsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("souffleur")
    }

    init(alias: String, modelName: String) {
        self.engineName = alias
        self.modelName = modelName
    }

    func ensureModel() async throws {
        guard !isLoaded else { return }
        print("Loading model: \(modelName) (CoreML)...")

        let modelsDir = Self.modelsDirectory
        try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)

        let manager = AsrManager()
        let models = try await AsrModels.load(from: modelsDir, version: .v3) { progress in
            let pct = Int(progress.fractionCompleted * 100)
            print("Downloading model: \(pct)%...", terminator: "\r")
            fflush(stdout)
        }
        print("")
        try await manager.loadModels(models)

        asrManager = manager
        isLoaded = true
        print("Model loaded.")
    }

    func transcribe(audio: [Float], sampleRate: Double) async throws -> String {
        try await ensureModel()
        guard let manager = asrManager else { return "" }

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

        let result = try await manager.transcribe(buffer, source: .microphone)
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
