import ArgumentParser
import Foundation

struct Run: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Run the daemon in foreground"
    )

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
            print("Hotkey auto_enter: \(config.hotkey.triggerAutoEnter)")
            print("Hotkey no_enter: \(config.hotkey.triggerNoEnter)")
            print("Hotkey whisper: \(config.hotkey.triggerWhisper)")
            print("Parakeet model: \(config.transcription.model)")
            print("Whisper model: \(config.transcription.whisperModel)")
        }

        // Load Parakeet model (primary)
        print("Loading Parakeet model...")
        let parakeet = Transcriber(config: config.transcription)
        let semaphore = DispatchSemaphore(value: 0)
        var loadError: Error?

        DispatchQueue.global(qos: .userInitiated).async {
            let runLoop = CFRunLoopGetCurrent()
            Task {
                do {
                    try await parakeet.ensureModel()
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
            print("Failed to load Parakeet model: \(error)")
            throw ExitCode.failure
        }
        print("Parakeet model loaded.")

        // Whisper backend (eager-loaded by daemon after UI starts)
        let whisper = WhisperKitTranscriber(config: config.transcription)

        // Start daemon with both backends
        let daemon = Daemon(config: config, parakeet: parakeet, whisper: whisper, debug: debug)
        daemon.run()
    }
}

struct Service: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Manage launchd service",
        subcommands: [Install.self, Uninstall.self, Restart.self, Status.self]
    )

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

    @Option(name: .shortAndLong, help: "Engine to test: parakeet or whisper")
    var engine: String = "parakeet"

    func run() throws {
        let config = Config.load()
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
        if engine == "whisper" {
            print("Transcribing with Whisper (\(config.transcription.whisperModel))...")
            transcriber = WhisperKitTranscriber(config: config.transcription)
        } else {
            print("Transcribing with Parakeet...")
            transcriber = Transcriber(config: config.transcription)
        }

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
        print("[hotkey]")
        print("trigger_auto_enter = \"\(config.hotkey.triggerAutoEnter)\"")
        print("trigger_no_enter = \"\(config.hotkey.triggerNoEnter)\"")
        print("trigger_whisper = \"\(config.hotkey.triggerWhisper)\"")
        print("cancel_delay = \(config.hotkey.cancelDelay)")
        print("")
        print("[audio]")
        print("device = \"\(config.audio.device)\"")
        print("sample_rate = \(config.audio.sampleRate)")
        print("")
        print("[transcription]")
        print("model = \"\(config.transcription.model)\"")
        print("whisper_model = \"\(config.transcription.whisperModel)\"")
        print("language = \"\(config.transcription.language)\"")
        print("")
        print("[output]")
        print("auto_paste = \(config.output.autoPaste)")
        print("")
        print("[overlay]")
        print("enabled = \(config.overlay.enabled)")
    }
}
