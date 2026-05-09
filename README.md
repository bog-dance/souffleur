# Souffleur

Local speech-to-text daemon for macOS. Hold a hotkey, speak, release - text gets typed into the active app.

Powered by [Parakeet](https://github.com/NVIDIA/NeMo) running on-device via CoreML. No cloud, no telemetry.

## Install

```bash
brew tap bog-dance/souffleur
brew install souffleur
sofl service install
```

Grant **Accessibility** and **Microphone** permissions when prompted.

## Usage

Hold **F3**, speak, release. Text is transcribed locally and pasted into the active app, followed by Enter.

## CLI

```
sofl service start      Start the daemon (default)
sofl service install    Install as launchd service (auto-start at login)
sofl service uninstall  Remove launchd service
sofl service restart    Restart the service
sofl service status     Show service status
sofl test               Test recording and transcription
sofl devices            List audio input devices
sofl config             Show current configuration
```

## Configuration

Config file: `~/.config/souffleur/config.toml`

Default config (one hotkey, Parakeet only):

```toml
[models.parakeet]
engine = "fluidaudio"
model = "parakeet-tdt-0.6b-v3"

[[hotkey.keys]]
key = "f3"
name = "fast"
stt = "parakeet"
postprocess = "none"
auto_enter = true

[audio]
device = "default"
sample_rate = 16000

[transcription]
language = "uk"

[output]
auto_paste = true

[overlay]
enabled = true
```

## Advanced

Souffleur supports multiple hotkeys, multiple STT engines, and optional LLM post-processing. Add as many `[[hotkey.keys]]` blocks as you want.

### Multiple hotkeys with same engine

Add F4 for cases where you don't want auto-Enter (useful when dictating into a chat input where Enter sends):

```toml
[[hotkey.keys]]
key = "f4"
name = "no-enter"
stt = "parakeet"
postprocess = "none"
auto_enter = false
```

### WhisperKit backend

WhisperKit (OpenAI Whisper via CoreML) is more accurate for some languages but slower than Parakeet. Add it as a second model and bind to a hotkey:

```toml
[models.whisper]
engine = "whisperkit"
model = "large-v3"

[[hotkey.keys]]
key = "f5"
name = "whisper"
stt = "whisper"
postprocess = "none"
auto_enter = false
```

### LLM post-processing (Ollama)

Run a local LLM to clean up the transcription (fix punctuation, remove filler words, etc.). Requires [Ollama](https://ollama.com) running locally with the configured model pulled.

```toml
[postprocess]
enabled = true
ollama_url = "http://localhost:11434"
model = "gemma3:4b"
timeout = 10.0
normalize_prompt = """\
Clean up this dictated text. Fix punctuation, capitalization, grammar. \
Remove filler words. Keep the SAME language. \
Return ONLY the cleaned text, nothing else."""

[[hotkey.keys]]
key = "f6"
name = "normalize"
stt = "parakeet"
postprocess = "normalize"
auto_enter = false
```

### LLM post-processing (OpenAI)

Use OpenAI for translation (e.g. dictate Ukrainian, get clean English). Set `openai_api_key` and bind a hotkey with `postprocess = "translate"`:

```toml
[postprocess]
enabled = true
openai_api_key = "sk-..."
openai_model = "gpt-4.1"
translate_prompt = """\
Translate the following dictated text into clean, natural English. \
Return ONLY the final text."""

[[hotkey.keys]]
key = "f7"
name = "translate"
stt = "parakeet"
postprocess = "translate"
auto_enter = false
```

When `translate` mode is selected and an OpenAI key is set, OpenAI is used; otherwise Ollama handles it. `normalize` mode always uses Ollama.

## How it works

Souffleur runs as a background daemon with a menu bar icon. It listens for global hotkeys, records audio from the microphone, transcribes it locally using a CoreML model, and types the result into the active app via the pasteboard.

Available transcription backends:
- **Parakeet** (NVIDIA NeMo via [FluidAudio](https://github.com/FluidInference/FluidAudio)) - fast, default
- **WhisperKit** (OpenAI Whisper via [WhisperKit](https://github.com/argmaxinc/WhisperKit)) - more accurate for some languages

Both run entirely on-device. LLM post-processing (Ollama and OpenAI) is opt-in.
