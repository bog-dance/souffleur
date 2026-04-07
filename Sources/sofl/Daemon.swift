import AppKit
import Foundation

class Daemon: @unchecked Sendable {
    let config: Config
    let stateManager: AppStateManager
    let parakeetTranscriber: TranscriberBackend
    let whisperTranscriber: TranscriberBackend?
    let debug: Bool
    var recorder: AudioRecorder?
    var hotkeyListener: HotkeyListener?
    var menuBar: MenuBarController?
    var overlay: OverlayController?

    init(config: Config, parakeet: TranscriberBackend, whisper: TranscriberBackend? = nil, debug: Bool = false) {
        self.config = config
        self.stateManager = AppStateManager()
        self.parakeetTranscriber = parakeet
        self.whisperTranscriber = whisper
        self.debug = debug
    }

    private func transcriber(for keyName: String) -> TranscriberBackend {
        if keyName == "whisper", let w = whisperTranscriber {
            return w
        }
        return parakeetTranscriber
    }

    private func log(_ message: String) {
        if debug { print(message) }
    }


    func run() {
        setupSignalHandlers()

        recorder = AudioRecorder(config: config.audio)

        // Setup hotkey listener (runs on main run loop)
        hotkeyListener = HotkeyListener(
            config: config.hotkey,
            onPress: { [weak self] keyName in
                self?.onHotkeyPress(keyName)
            },
            onRelease: { [weak self] keyName in
                self?.onHotkeyRelease(keyName)
            },
            onCancel: { [weak self] in
                self?.onCancel()
            },
            onToggleStart: { [weak self] keyName in
                self?.onToggleStart(keyName)
            },
            onToggleStop: { [weak self] keyName in
                self?.onToggleStop(keyName)
            }
        )
        hotkeyListener?.start()

        // Setup UI
        if config.overlay.enabled {
            overlay = OverlayController(stateManager: stateManager)
        }
        menuBar = MenuBarController(stateManager: stateManager, onQuit: { [weak self] in
            self?.stop()
            NSApp.terminate(nil)
        })

        stateManager.transition(to: .idle)
        setAppIcon()
        print("Ready.")

        // Eager-load whisper model in background (parakeet remains usable)
        if let whisper = whisperTranscriber {
            log("Eager-loading whisper model in background...")
            Task.detached {
                do {
                    try await whisper.ensureModel()
                } catch {
                    print("Failed to load Whisper model: \(error)")
                }
            }
        }

        // Run NSApplication event loop (blocks)
        NSApplication.shared.run()
    }

    private func onHotkeyPress(_ keyName: String) {
        guard let recorder = recorder else { return }
        log("Recording... [\(keyName)]")
        stateManager.transition(to: .recording)
        recorder.start()
    }

    private func onHotkeyRelease(_ keyName: String) {
        guard let recorder = recorder, recorder.isRecording else { return }
        let (audio, sampleRate) = recorder.stop()

        let minSamples = Int(Double(sampleRate) * 0.3)
        guard audio.count >= minSamples else {
            log("Audio too short, skipping.")
            stateManager.transition(to: .idle)
            return
        }

        let autoEnter = keyName == "auto_enter"
        let backend = transcriber(for: keyName)

        if config.hotkey.cancelDelay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + config.hotkey.cancelDelay) { [self] in
                guard let listener = hotkeyListener, !listener.isCancelled else {
                    hotkeyListener?.resetCancel()
                    log("Cancelled.")
                    stateManager.transition(to: .idle)
                    return
                }
                transcribeAndOutput(audio: audio, sampleRate: sampleRate, autoEnter: autoEnter, backend: backend)
            }
        } else {
            transcribeAndOutput(audio: audio, sampleRate: sampleRate, autoEnter: autoEnter, backend: backend)
        }
    }

    private func transcribeAndOutput(audio: [Float], sampleRate: Double, autoEnter: Bool, backend: TranscriberBackend) {
        stateManager.transition(to: backend.isReady ? .processing : .loading)
        let audioDuration = Double(audio.count) / sampleRate
        log("Transcribing \(String(format: "%.1f", audioDuration))s audio via \(backend.engineName)...")
        let startTime = CFAbsoluteTimeGetCurrent()
        let cpuBefore = Self.getCPUTime()

        // Run transcription on background thread, bridge async via semaphore
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let semaphore = DispatchSemaphore(value: 0)
            var result = ""
            var err: Error?

            Task.detached {
                do {
                    result = try await backend.transcribe(audio: audio, sampleRate: sampleRate)
                } catch {
                    err = error
                }
                semaphore.signal()
            }
            semaphore.wait()

            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            let latencyMs = Int(elapsed * 1000)

            DispatchQueue.main.async {
                if let error = err {
                    print("Transcription error: \(error)")
                    self.stateManager.transition(to: .idle)
                } else if result.isEmpty {
                    self.log("No speech detected. (\(latencyMs)ms)")
                    self.stateManager.transition(to: .idle)
                } else {
                    let rtf = elapsed / audioDuration
                    let rss = Self.getRSSMB()
                    let cpuAfter = Self.getCPUTime()
                    let cpuMs = Int((cpuAfter - cpuBefore) * 1000)
                    self.log("[\(latencyMs)ms, cpu \(cpuMs)ms, RTF \(String(format: "%.2f", rtf)), RSS \(rss)MB] \(result)")
                    var outConfig = self.config.output
                    outConfig.autoEnter = autoEnter
                    Output.outputText(result, config: outConfig)
                    self.stateManager.transition(to: .done)
                }
            }
        }
    }

    private func onToggleStart(_ keyName: String) {
        // Short tap detected - switch to toggle mode, recording continues
        log("Toggle mode: recording... tap again to stop [\(keyName)]")
    }

    private func onToggleStop(_ keyName: String) {
        // Second tap - stop recording and transcribe
        guard let recorder = recorder, recorder.isRecording else { return }
        let (audio, sampleRate) = recorder.stop()
        log("Toggle mode: stopped [\(keyName)]")

        let minSamples = Int(Double(sampleRate) * 0.3)
        guard audio.count >= minSamples else {
            log("Audio too short, skipping.")
            stateManager.transition(to: .idle)
            return
        }

        let autoEnter = keyName == "auto_enter"
        let backend = transcriber(for: keyName)
        transcribeAndOutput(audio: audio, sampleRate: sampleRate, autoEnter: autoEnter, backend: backend)
    }

    private func onCancel() {
        if let recorder = recorder, recorder.isRecording {
            _ = recorder.stop()
        }
        hotkeyListener?.resetToggle()
        log("Cancelled.")
        stateManager.transition(to: .idle)
    }

    func stop() {
        hotkeyListener?.stop()
        if let recorder = recorder, recorder.isRecording {
            _ = recorder.stop()
        }
        log("Daemon stopped.")
    }

    private static func getRSSMB() -> Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), intPtr, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Int(info.resident_size) / 1024 / 1024
    }

    private static func getCPUTime() -> Double {
        var info = task_thread_times_info()
        var count = mach_msg_type_number_t(MemoryLayout<task_thread_times_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                task_info(mach_task_self_, task_flavor_t(TASK_THREAD_TIMES_INFO), intPtr, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        let user = Double(info.user_time.seconds) + Double(info.user_time.microseconds) / 1_000_000
        let sys = Double(info.system_time.seconds) + Double(info.system_time.microseconds) / 1_000_000
        return user + sys
    }

    private func setAppIcon() {
        if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            NSApplication.shared.applicationIconImage = img
        }
    }

    private func setupSignalHandlers() {
        signal(SIGINT) { _ in
            print("\nShutting down...")
            exit(0)
        }
        signal(SIGTERM) { _ in
            print("\nShutting down...")
            exit(0)
        }
    }
}
