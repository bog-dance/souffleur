import Foundation
import TOMLKit

struct HotkeyConfig {
    var triggerAutoEnter: String = "f3"
    var triggerNoEnter: String = "f4"
    var triggerWhisper: String = "f8"
    var cancelDelay: Double = 0.0
}

struct AudioConfig {
    var device: String = "default"
    var sampleRate: Int = 16000
}

struct TranscriptionConfig {
    var model: String = "large-v3-turbo"
    var whisperModel: String = "large-v3"
    var language: String = "uk"
}

struct OutputConfig {
    var autoPaste: Bool = true
    var autoEnter: Bool = false
}

struct OverlayConfig {
    var enabled: Bool = true
}

struct Config {
    var hotkey = HotkeyConfig()
    var audio = AudioConfig()
    var transcription = TranscriptionConfig()
    var output = OutputConfig()
    var overlay = OverlayConfig()

    static var configPath: String {
        let xdgConfig = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"]
            ?? NSHomeDirectory() + "/.config"
        return xdgConfig + "/souffleur/config.toml"
    }

    static func load() -> Config {
        var config = Config()
        let path = configPath

        guard FileManager.default.fileExists(atPath: path),
              let data = FileManager.default.contents(atPath: path),
              let content = String(data: data, encoding: .utf8) else {
            return config
        }

        do {
            let table = try TOMLTable(string: content)

            if let hotkey = table["hotkey"]?.table {
                if let v = hotkey["trigger_auto_enter"]?.string { config.hotkey.triggerAutoEnter = v }
                if let v = hotkey["trigger_no_enter"]?.string { config.hotkey.triggerNoEnter = v }
                if let v = hotkey["trigger_whisper"]?.string { config.hotkey.triggerWhisper = v }
                if let v = hotkey["cancel_delay"]?.double { config.hotkey.cancelDelay = v }
            }

            if let audio = table["audio"]?.table {
                if let v = audio["device"]?.string { config.audio.device = v }
                if let v = audio["sample_rate"]?.int { config.audio.sampleRate = v }
            }

            if let transcription = table["transcription"]?.table {
                if let v = transcription["model"]?.string { config.transcription.model = v }
                if let v = transcription["whisper_model"]?.string { config.transcription.whisperModel = v }
                if let v = transcription["language"]?.string { config.transcription.language = v }
            }

            if let output = table["output"]?.table {
                if let v = output["auto_paste"]?.bool { config.output.autoPaste = v }
            }

            if let overlay = table["overlay"]?.table {
                if let v = overlay["enabled"]?.bool { config.overlay.enabled = v }
            }
        } catch {
            print("Warning: failed to parse config: \(error)")
        }

        return config
    }
}
