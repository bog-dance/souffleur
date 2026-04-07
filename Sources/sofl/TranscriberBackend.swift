import AVFoundation

protocol TranscriberBackend: AnyObject, Sendable {
    var engineName: String { get }
    func ensureModel() async throws
    func transcribe(audio: [Float], sampleRate: Double) async throws -> String
}
