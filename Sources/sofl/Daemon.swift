import AppKit
import Foundation

class Daemon: @unchecked Sendable {
    let config: Config
    let stateManager: AppStateManager
    let transcriberMap: [String: TranscriberBackend]
    let debug: Bool
    let postProcessor: PostProcessor?
    var recorder: AudioRecorder?
    var hotkeyListener: HotkeyListener?
    var menuBar: MenuBarController?
    var overlay: OverlayController?

    init(config: Config, transcribers: [String: TranscriberBackend], debug: Bool = false) {
        self.config = config
        self.stateManager = AppStateManager()
        self.transcriberMap = transcribers
        self.debug = debug
        self.postProcessor = config.postprocess.enabled ? PostProcessor(config: config.postprocess) : nil
    }

    private func transcriber(for entry: HotkeyEntry) -> TranscriberBackend? {
        return transcriberMap[entry.stt]
    }

    private func postMode(for entry: HotkeyEntry) -> PostProcessMode? {
        switch entry.postprocess {
        case "normalize": return .normalize
        case "translate": return .translate
        default: return nil
        }
    }

    private func log(_ message: String) {
        if debug { print(message) }
    }


    func run() {
        setupSignalHandlers()

        recorder = AudioRecorder(config: config.audio)

        hotkeyListener = HotkeyListener(
            config: config.hotkey,
            onPress: { [weak self] entry in
                self?.onHotkeyPress(entry)
            },
            onRelease: { [weak self] entry in
                self?.onHotkeyRelease(entry)
            },
            onCancel: { [weak self] in
                self?.onCancel()
            },
            onToggleStart: { [weak self] entry in
                self?.onToggleStart(entry)
            },
            onToggleStop: { [weak self] entry in
                self?.onToggleStop(entry)
            }
        )
        hotkeyListener?.start()

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

        for (alias, backend) in transcriberMap where !backend.isReady {
            log("Eager-loading \(alias) model in background...")
            Task.detached {
                do {
                    try await backend.ensureModel()
                } catch {
                    print("Failed to load \(alias) model: \(error)")
                }
            }
        }

        NSApplication.shared.run()
    }

    private func onHotkeyPress(_ entry: HotkeyEntry) {
        guard let recorder = recorder else { return }
        log("Recording... [\(entry.name)]")
        stateManager.transition(to: .recording)
        recorder.start()
    }

    private func onHotkeyRelease(_ entry: HotkeyEntry) {
        guard let recorder = recorder, recorder.isRecording else { return }
        let (audio, sampleRate) = recorder.stop()

        let minSamples = Int(Double(sampleRate) * 0.3)
        guard audio.count >= minSamples else {
            log("Audio too short, skipping.")
            stateManager.transition(to: .idle)
            return
        }

        guard let backend = transcriber(for: entry) else {
            log("No transcriber for stt=\(entry.stt), skipping.")
            stateManager.transition(to: .idle)
            return
        }
        let mode = postMode(for: entry)

        if config.hotkey.cancelDelay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + config.hotkey.cancelDelay) { [self] in
                guard let listener = hotkeyListener, !listener.isCancelled else {
                    hotkeyListener?.resetCancel()
                    log("Cancelled.")
                    stateManager.transition(to: .idle)
                    return
                }
                transcribeAndOutput(audio: audio, sampleRate: sampleRate, entry: entry, postMode: mode, backend: backend)
            }
        } else {
            transcribeAndOutput(audio: audio, sampleRate: sampleRate, entry: entry, postMode: mode, backend: backend)
        }
    }

    private func transcribeAndOutput(audio: [Float], sampleRate: Double, entry: HotkeyEntry, postMode: PostProcessMode?, backend: TranscriberBackend) {
        if !backend.isReady {
            stateManager.transition(to: .loading, text: "loading \(entry.stt)")
            if let wk = backend as? WhisperKitTranscriber {
                wk.onProgress = { [weak self] text in
                    DispatchQueue.main.async {
                        self?.stateManager.transition(to: .loading, text: text)
                    }
                }
            }
        } else {
            stateManager.transition(to: .processing)
        }
        let audioDuration = Double(audio.count) / sampleRate
        log("Transcribing \(String(format: "%.1f", audioDuration))s audio via \(backend.engineName) [\(entry.name)]...")
        let startTime = CFAbsoluteTimeGetCurrent()
        let cpuBefore = Self.getCPUTime()

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

                    if let mode = postMode, let pp = self.postProcessor {
                        let ppLabel = mode == .translate ? "translating" : "postprocess"
                        self.stateManager.transition(to: .postprocessing, text: ppLabel)
                        Task.detached {
                            let ppStart = CFAbsoluteTimeGetCurrent()
                            var finalText = result
                            var ppFailed = false
                            do {
                                finalText = try await pp.process(result, mode: mode)
                                let ppMs = Int((CFAbsoluteTimeGetCurrent() - ppStart) * 1000)
                                self.log("[pp \(ppMs)ms] \(finalText)")
                            } catch {
                                ppFailed = true
                                self.log("Post-process failed, using raw: \(error)")
                            }
                            DispatchQueue.main.async {
                                var outConfig = self.config.output
                                outConfig.autoEnter = entry.autoEnter
                                Output.outputText(finalText, config: outConfig)
                                if ppFailed {
                                    self.stateManager.transition(to: .error, text: "postprocess error")
                                } else {
                                    self.stateManager.transition(to: .done)
                                }
                            }
                        }
                    } else {
                        var outConfig = self.config.output
                        outConfig.autoEnter = entry.autoEnter
                        Output.outputText(result, config: outConfig)
                        self.stateManager.transition(to: .done)
                    }
                }
            }
        }
    }

    private func onToggleStart(_ entry: HotkeyEntry) {
        log("Toggle mode: recording... tap again to stop [\(entry.name)]")
    }

    private func onToggleStop(_ entry: HotkeyEntry) {
        guard let recorder = recorder, recorder.isRecording else { return }
        let (audio, sampleRate) = recorder.stop()
        log("Toggle mode: stopped [\(entry.name)]")

        let minSamples = Int(Double(sampleRate) * 0.3)
        guard audio.count >= minSamples else {
            log("Audio too short, skipping.")
            stateManager.transition(to: .idle)
            return
        }

        guard let backend = transcriber(for: entry) else {
            log("No transcriber for stt=\(entry.stt), skipping.")
            stateManager.transition(to: .idle)
            return
        }
        let mode = postMode(for: entry)
        transcribeAndOutput(audio: audio, sampleRate: sampleRate, entry: entry, postMode: mode, backend: backend)
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
