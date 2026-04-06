import Foundation
import TOMLKit

struct HotkeyConfig {
    var triggerAutoEnter: String = "f6"
    var triggerNoEnter: String = "f7"
    var cancelDelay: Double = 0.0
}

struct AudioConfig {
    var device: String = "default"
    var sampleRate: Int = 16000
}

struct TranscriptionConfig {
    var model: String = "large-v3-turbo"
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

            if let hotkey = table["hotkey"] as? TOMLTable {
                if let v = hotkey["trigger_auto_enter"] as? String { config.hotkey.triggerAutoEnter = v }
                if let v = hotkey["trigger_no_enter"] as? String { config.hotkey.triggerNoEnter = v }
                if let v = hotkey["cancel_delay"] as? Double { config.hotkey.cancelDelay = v }
            }

            if let audio = table["audio"] as? TOMLTable {
                if let v = audio["device"] as? String { config.audio.device = v }
                if let v = audio["sample_rate"] as? Int { config.audio.sampleRate = v }
            }

            if let transcription = table["transcription"] as? TOMLTable {
                if let v = transcription["model"] as? String { config.transcription.model = v }
                if let v = transcription["language"] as? String { config.transcription.language = v }
            }

            if let output = table["output"] as? TOMLTable {
                if let v = output["auto_paste"] as? Bool { config.output.autoPaste = v }
            }

            if let overlay = table["overlay"] as? TOMLTable {
                if let v = overlay["enabled"] as? Bool { config.overlay.enabled = v }
            }
        } catch {
            print("Warning: failed to parse config: \(error)")
        }

        return config
    }
}
