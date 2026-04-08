import ArgumentParser
import Foundation

struct Service: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Manage souffleur daemon",
        subcommands: [Start.self, Install.self, Uninstall.self, Restart.self, Status.self],
        defaultSubcommand: Start.self
    )

    struct Start: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Start the daemon")

        @Flag(name: .long, help: "Enable debug logging (unbuffered output)")
        var debug = false

        func run() throws {
            if debug {
                setbuf(stdout, nil)
                setbuf(stderr, nil)
            }

            let config = Config.load()

            print("Starting souffleur daemon...")
            if debug {
                for (alias, m) in config.models {
                    print("Model \(alias): \(m.model) (engine: \(m.engine))")
                }
                for entry in config.hotkey.entries {
                    print("Hotkey \(entry.name): \(entry.key) (stt: \(entry.stt), pp: \(entry.postprocess), enter: \(entry.autoEnter))")
                }
            }

            // Build transcribers from config
            var transcribers: [String: TranscriberBackend] = [:]
            // Find which STT aliases are actually used by hotkeys
            let usedAliases = Set(config.hotkey.entries.map { $0.stt })

            for alias in usedAliases {
                guard let modelConfig = config.models[alias] else {
                    print("Warning: hotkey references stt=\(alias) but no [models.\(alias)] defined")
                    continue
                }
                let backend: TranscriberBackend
                switch modelConfig.engine {
                case "fluidaudio":
                    backend = Transcriber(alias: alias, modelName: modelConfig.model)
                case "whisperkit":
                    backend = WhisperKitTranscriber(alias: alias, modelName: modelConfig.model, language: config.transcription.language)
                default:
                    print("Warning: unknown engine '\(modelConfig.engine)' for model \(alias)")
                    continue
                }
                transcribers[alias] = backend
            }

            guard !transcribers.isEmpty else {
                print("Error: no transcribers configured")
                throw ExitCode.failure
            }

            // Eager-load the first transcriber (blocking) so it's ready immediately
            let firstAlias = config.hotkey.entries.first!.stt
            if let first = transcribers[firstAlias] {
                print("Loading \(firstAlias) model...")
                let semaphore = DispatchSemaphore(value: 0)
                var loadError: Error?

                DispatchQueue.global(qos: .userInitiated).async {
                    let runLoop = CFRunLoopGetCurrent()
                    Task {
                        do {
                            try await first.ensureModel()
                        } catch {
                            loadError = error
                        }
                        CFRunLoopStop(runLoop!)
                    }
                    CFRunLoopRun()
                    semaphore.signal()
                }
                semaphore.wait()

                if let error = loadError {
                    print("Failed to load \(firstAlias) model: \(error)")
                    throw ExitCode.failure
                }
                print("\(firstAlias) model loaded.")
            }

            let daemon = Daemon(config: config, transcribers: transcribers, debug: debug)
            daemon.run()
        }
    }

    struct Install: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Install and start service")
        func run() { ServiceManager.install() }
    }

    struct Uninstall: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Stop and remove service")
        func run() { ServiceManager.uninstall() }
    }

    struct Restart: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Restart service")
        func run() { ServiceManager.restart() }
    }

    struct Status: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show service status")
        func run() { ServiceManager.status() }
    }
}

struct Test: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Test recording and transcription"
    )

    @Option(name: .shortAndLong, help: "Recording duration in seconds")
    var duration: Double = 3.0

    @Option(name: .shortAndLong, help: "STT model alias (as defined in config [models])")
    var engine: String?

    func run() throws {
        let config = Config.load()
        let alias = engine ?? config.hotkey.entries.first?.stt ?? "parakeet"

        guard let modelConfig = config.models[alias] else {
            print("Error: no model '\(alias)' in config. Available: \(config.models.keys.joined(separator: ", "))")
            throw ExitCode.failure
        }

        print("Recording for \(duration) seconds...")
        let recorder = AudioRecorder(config: config.audio)
        recorder.start()
        Thread.sleep(forTimeInterval: duration)
        let (audio, sampleRate) = recorder.stop()

        guard audio.count > 0 else {
            print("No audio captured.")
            return
        }

        let transcriber: TranscriberBackend
        switch modelConfig.engine {
        case "fluidaudio":
            transcriber = Transcriber(alias: alias, modelName: modelConfig.model)
        case "whisperkit":
            transcriber = WhisperKitTranscriber(alias: alias, modelName: modelConfig.model, language: config.transcription.language)
        default:
            print("Error: unknown engine '\(modelConfig.engine)'")
            throw ExitCode.failure
        }

        print("Transcribing with \(alias) (\(modelConfig.model))...")

        let semaphore = DispatchSemaphore(value: 0)
        var result = ""
        var err: Error?

        let thread = Thread {
            Task {
                do {
                    result = try await transcriber.transcribe(audio: audio, sampleRate: sampleRate)
                } catch {
                    err = error
                }
                semaphore.signal()
            }
            RunLoop.current.run(until: Date.distantFuture)
        }
        thread.start()
        semaphore.wait()
        thread.cancel()

        if let error = err {
            print("Transcription error: \(error)")
            throw ExitCode.failure
        }

        if result.isEmpty {
            print("No speech detected.")
        } else {
            print("Result: \(result)")
        }
    }
}

struct Devices: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List audio input devices"
    )

    func run() {
        let devices = AudioRecorder.listDevices()
        if devices.isEmpty {
            print("No input devices found.")
            return
        }
        for device in devices {
            print("[\(device.id)] \(device.name) (\(Int(device.sampleRate)) Hz, \(device.channels) ch)")
        }
    }
}

struct ShowConfig: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "config",
        abstract: "Show current configuration"
    )

    func run() {
        let config = Config.load()
        print("Config: \(Config.configPath)")
        print("")
        print("[models]")
        for (alias, m) in config.models {
            print("\(alias) = \"\(m.model)\" (engine: \(m.engine))")
        }
        print("")
        print("[hotkey]")
        for entry in config.hotkey.entries {
            print("\(entry.key) = \(entry.name) (stt: \(entry.stt), postprocess: \(entry.postprocess), auto_enter: \(entry.autoEnter))")
        }
        print("cancel_delay = \(config.hotkey.cancelDelay)")
        print("")
        print("[audio]")
        print("device = \"\(config.audio.device)\"")
        print("sample_rate = \(config.audio.sampleRate)")
        print("")
        print("[transcription]")
        print("language = \"\(config.transcription.language)\"")
        print("")
        print("[output]")
        print("auto_paste = \(config.output.autoPaste)")
        print("")
        print("[overlay]")
        print("enabled = \(config.overlay.enabled)")
        print("")
        print("[postprocess]")
        print("enabled = \(config.postprocess.enabled)")
        print("model = \"\(config.postprocess.model)\"")
    }
}
