import Foundation
import TOMLKit

struct ModelConfig {
    var engine: String
    var model: String
}

struct HotkeyEntry {
    var key: String
    var name: String
    var stt: String
    var postprocess: String = "none"
    var autoEnter: Bool = false
}

struct HotkeyConfig {
    var entries: [HotkeyEntry] = []
    var cancelDelay: Double = 0.0
}

struct AudioConfig {
    var device: String = "default"
    var sampleRate: Int = 16000
}

struct TranscriptionConfig {
    var language: String = "uk"
}

struct OutputConfig {
    var autoPaste: Bool = true
    var autoEnter: Bool = false
}

struct OverlayConfig {
    var enabled: Bool = true
}

struct PostProcessConfig {
    var enabled: Bool = false
    var ollamaUrl: String = "http://localhost:11434"
    var model: String = "gemma3:4b"
    var timeout: Double = 10.0
    var openaiApiKey: String = ""
    var openaiModel: String = "gpt-4.1"
    var translatePrompt: String = "Translate the following dictated text into clean, natural English. Return ONLY the final text."
    var normalizePrompt: String = "Clean up this dictated text. Fix punctuation, capitalization, grammar. Remove filler words. Keep the SAME language. Return ONLY the cleaned text."
}

struct Config {
    var models: [String: ModelConfig] = [:]
    var hotkey = HotkeyConfig()
    var audio = AudioConfig()
    var transcription = TranscriptionConfig()
    var output = OutputConfig()
    var overlay = OverlayConfig()
    var postprocess = PostProcessConfig()

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

            if let models = table["models"]?.table {
                for (alias, value) in models {
                    guard let t = value.table,
                          let engine = t["engine"]?.string,
                          let model = t["model"]?.string else { continue }
                    config.models[alias] = ModelConfig(engine: engine, model: model)
                }
            }

            if let hotkey = table["hotkey"]?.table {
                if let v = hotkey["cancel_delay"]?.double { config.hotkey.cancelDelay = v }

                if let keys = hotkey["keys"]?.array {
                    for item in keys {
                        guard let t = item.table,
                              let key = t["key"]?.string,
                              let name = t["name"]?.string,
                              let stt = t["stt"]?.string else { continue }
                        var entry = HotkeyEntry(key: key, name: name, stt: stt)
                        if let v = t["postprocess"]?.string { entry.postprocess = v }
                        if let v = t["auto_enter"]?.bool { entry.autoEnter = v }
                        config.hotkey.entries.append(entry)
                    }
                }
            }

            if let audio = table["audio"]?.table {
                if let v = audio["device"]?.string { config.audio.device = v }
                if let v = audio["sample_rate"]?.int { config.audio.sampleRate = v }
            }

            if let transcription = table["transcription"]?.table {
                if let v = transcription["language"]?.string { config.transcription.language = v }
            }

            if let output = table["output"]?.table {
                if let v = output["auto_paste"]?.bool { config.output.autoPaste = v }
            }

            if let overlay = table["overlay"]?.table {
                if let v = overlay["enabled"]?.bool { config.overlay.enabled = v }
            }

            if let pp = table["postprocess"]?.table {
                if let v = pp["enabled"]?.bool { config.postprocess.enabled = v }
                if let v = pp["ollama_url"]?.string { config.postprocess.ollamaUrl = v }
                if let v = pp["model"]?.string { config.postprocess.model = v }
                if let v = pp["timeout"]?.double { config.postprocess.timeout = v }
                if let v = pp["openai_api_key"]?.string { config.postprocess.openaiApiKey = v }
                if let v = pp["openai_model"]?.string { config.postprocess.openaiModel = v }
                if let v = pp["translate_prompt"]?.string { config.postprocess.translatePrompt = v }
                if let v = pp["normalize_prompt"]?.string { config.postprocess.normalizePrompt = v }
            }
        } catch {
            print("Warning: failed to parse config: \(error)")
        }

        return config
    }
}
