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

struct VocabularyTerm {
    var text: String
    var aliases: [String] = []
    var weight: Float?
    var minSimilarity: Float?
}

struct VocabularyConfig {
    var enabled: Bool = true
    var terms: [VocabularyTerm] = []
    var minSimilarity: Float?
    var minTermLength: Int?
    /// Acoustic rescue recovers mangled terms but over-fires on short vocabularies.
    var spotterRescue: Bool = true

    var isActive: Bool { enabled && !terms.isEmpty }
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
    var vocabulary = VocabularyConfig()
    var output = OutputConfig()
    var overlay = OverlayConfig()
    var postprocess = PostProcessConfig()

    static var configDirectory: String {
        let xdgConfig = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"]
            ?? NSHomeDirectory() + "/.config"
        return xdgConfig + "/souffleur"
    }

    static var configPath: String { configDirectory + "/config.toml" }

    /// Terms live in their own file because they are the one thing edited mid-session,
    /// often by voice. A typo there must not be able to break hotkeys or models.
    static var vocabularyPath: String { configDirectory + "/vocabulary.toml" }

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

            if let vocab = table["vocabulary"]?.table {
                applyVocabulary(vocab, to: &config.vocabulary)
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

        mergeVocabularyFile(into: &config.vocabulary)

        return config
    }

    /// Reads vocabulary.toml alone, for the watcher: a bad edit there costs the terms,
    /// never the running daemon.
    static func loadVocabulary() -> VocabularyConfig {
        var vocabulary = VocabularyConfig()

        if let data = FileManager.default.contents(atPath: configPath),
           let content = String(data: data, encoding: .utf8),
           let table = try? TOMLTable(string: content),
           let vocab = table["vocabulary"]?.table {
            applyVocabulary(vocab, to: &vocabulary)
        }

        mergeVocabularyFile(into: &vocabulary)
        return vocabulary
    }

    /// vocabulary.toml may hold the terms bare at the top level or under [vocabulary];
    /// both read the same, and its terms are appended to whatever config.toml declared.
    private static func mergeVocabularyFile(into vocabulary: inout VocabularyConfig) {
        guard let data = FileManager.default.contents(atPath: vocabularyPath),
              let content = String(data: data, encoding: .utf8) else { return }

        do {
            let table = try TOMLTable(string: content)
            applyVocabulary(table["vocabulary"]?.table ?? table, to: &vocabulary)
        } catch {
            print("Warning: failed to parse \(vocabularyPath): \(error)")
        }
    }

    private static func applyVocabulary(_ table: TOMLTable, to vocabulary: inout VocabularyConfig) {
        if let v = table["enabled"]?.bool { vocabulary.enabled = v }
        if let v = table["min_similarity"]?.double { vocabulary.minSimilarity = Float(v) }
        if let v = table["min_term_length"]?.int { vocabulary.minTermLength = v }
        if let v = table["spotter_rescue"]?.bool { vocabulary.spotterRescue = v }

        guard let terms = table["terms"]?.array else { return }
        for item in terms {
            if let text = item.string {
                vocabulary.terms.append(VocabularyTerm(text: text))
                continue
            }
            guard let t = item.table, let text = t["text"]?.string else { continue }
            var term = VocabularyTerm(text: text)
            if let a = t["aliases"]?.array { term.aliases = a.compactMap { $0.string } }
            if let v = t["weight"]?.double { term.weight = Float(v) }
            if let v = t["min_similarity"]?.double { term.minSimilarity = Float(v) }
            vocabulary.terms.append(term)
        }
    }
}
