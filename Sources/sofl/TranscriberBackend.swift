import AVFoundation

protocol TranscriberBackend: AnyObject, Sendable {
    var engineName: String { get }
    var isReady: Bool { get }
    func ensureModel() async throws
    func transcribe(audio: [Float], sampleRate: Double) async throws -> String
}
