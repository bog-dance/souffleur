import AVFoundation
import Foundation

struct AudioDeviceInfo {
    let id: AudioDeviceID
    let name: String
    let sampleRate: Double
    let channels: Int
}

class AudioRecorder {
    private let config: AudioConfig
    private let engine = AVAudioEngine()
    private var audioBuffer: [Float] = []
    private var bufferLock = NSLock()
    private var _isRecording = false
    private var actualSampleRate: Double = 16000

    var isRecording: Bool { _isRecording }

    init(config: AudioConfig) {
        self.config = config
    }

    func start() {
        guard !_isRecording else { return }
        audioBuffer.removeAll()

        let inputNode = engine.inputNode
        let format = inputNode.inputFormat(forBus: 0)
        actualSampleRate = format.sampleRate

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self = self, self._isRecording else { return }
            guard let channelData = buffer.floatChannelData else { return }
            let frames = Int(buffer.frameLength)
            let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frames))
            self.bufferLock.lock()
            self.audioBuffer.append(contentsOf: samples)
            self.bufferLock.unlock()
        }

        do {
            try engine.start()
            _isRecording = true
        } catch {
            print("Audio error: \(error)")
        }
    }

    func stop() -> (audio: [Float], sampleRate: Double) {
        guard _isRecording else { return ([], actualSampleRate) }
        _isRecording = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        bufferLock.lock()
        let result = audioBuffer
        audioBuffer.removeAll()
        bufferLock.unlock()

        return (result, actualSampleRate)
    }

    static func listDevices() -> [AudioDeviceInfo] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress, 0, nil, &dataSize
        ) == noErr else { return [] }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress, 0, nil, &dataSize, &deviceIDs
        ) == noErr else { return [] }

        var devices: [AudioDeviceInfo] = []
        for id in deviceIDs {
            // Check input channels
            var inputAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            var inputSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &inputAddress, 0, nil, &inputSize) == noErr else { continue }

            let bufferListPtr = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
            defer { bufferListPtr.deallocate() }
            guard AudioObjectGetPropertyData(id, &inputAddress, 0, nil, &inputSize, bufferListPtr) == noErr else { continue }

            let channels = Int(bufferListPtr.pointee.mBuffers.mNumberChannels)
            guard channels > 0 else { continue }

            // Get name
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceNameCFString,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var nameRef: Unmanaged<CFString>?
            var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            AudioObjectGetPropertyData(id, &nameAddress, 0, nil, &nameSize, &nameRef)
            let name = nameRef?.takeRetainedValue() as String? ?? "Unknown"

            // Get sample rate
            var rateAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyNominalSampleRate,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var sampleRate: Double = 0
            var rateSize = UInt32(MemoryLayout<Double>.size)
            AudioObjectGetPropertyData(id, &rateAddress, 0, nil, &rateSize, &sampleRate)

            devices.append(AudioDeviceInfo(
                id: id,
                name: name as String,
                sampleRate: sampleRate,
                channels: channels
            ))
        }

        return devices
    }
}
