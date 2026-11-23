# Souffleur

Local speech-to-text daemon for macOS. Hold a hotkey, speak, release - text gets typed into the active app.

Powered by [Parakeet](https://github.com/NVIDIA/NeMo) running on-device via CoreML. No cloud, no telemetry. The default model is a Ukrainian + English fine-tune; the stock multilingual Parakeet is one config line away (see [Models](#models)).

## Install

```bash
brew tap bog-dance/souffleur
brew install souffleur
sofl service install
```

Grant **Accessibility** and **Microphone** permissions when prompted. The launch agent runs a copy at `~/Library/Application Support/souffleur/bin/sofl` that keeps its path across releases, so the grants are asked for once, not after every upgrade. The daemon picks up the Accessibility toggle by itself.

## Upgrade

```bash
brew update && brew upgrade souffleur
```

The formula restarts the service; the daemon copies the new release over its stable copy and restarts into it. Models, config and permissions carry over. Coming from 1.7.1 or earlier, the launch agent is switched to the stable path on the first start and macOS records the grants for that path once: with the same signature it usually does this by itself, otherwise it shows the Accessibility prompt and the daemon picks up the toggle without a restart.

## Usage

Hold **F3**, speak, release. Text is transcribed locally and pasted into the active app, followed by Enter.

Press **Escape** to throw the utterance away: while holding F3, or after releasing it until the text is pasted. Nothing is pasted, no Enter, the clipboard stays as it was.

## CLI

```
sofl service start      Start the daemon (default)
sofl service install    Install as launchd service (auto-start at login)
sofl service uninstall  Remove launchd service
sofl service restart    Restart the service
sofl service status     Show service status
sofl test               Test recording and transcription (--file a.wav to transcribe a file)
sofl devices            List audio input devices
sofl config             Show current configuration
```

## Configuration

Config file: `~/.config/souffleur/config.toml`

Default config (one hotkey, Parakeet only):

```toml
[models.parakeet]
engine = "fluidaudio"
model = "parakeet-tdt-0.6b-v3-uk"

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

## Models

Two Parakeet TDT 0.6B v3 builds run through the `fluidaudio` engine. Pick one with `model` in `[models.parakeet]`:

| `model` | What it is | Languages | Download |
|---|---|---|---|
| `parakeet-tdt-0.6b-v3-uk` (default) | [ihnatov-yuri/parakeet-tdt-0.6b-v3-uk](https://huggingface.co/ihnatov-yuri/parakeet-tdt-0.6b-v3-uk), CoreML int8 | Ukrainian + English | ~630 MB, first start |
| `parakeet-tdt-0.6b-v3-stock` | NVIDIA's stock multilingual v3 via FluidAudio | 25 European languages | ~0.5 GB, first start |

**Ukrainian fine-tune (default).** Ukrainian stays Ukrainian on short phrases ("Вимкни", "тридцять вісім" instead of the stock model's "Выключи", "тридцать восемь"), and English words inside Ukrainian speech stay in Latin ("WhatsApp", "Order Go Jack from this place to my home"). It has no letter filter: the fine-tune does not produce Russian-only letters, and the filter would also strip every Latin token. `[transcription] language` is ignored for this model. It knows only Ukrainian and English and is likely worse than stock for Russian and every other language, so **if you do not dictate in Ukrainian, use the stock model.** Files go to `~/Library/Application Support/souffleur/models/parakeet-tdt-0.6b-v3-uk/`, pinned to revision `5c4bcfa`.

**Stock multilingual.** Set `model = "parakeet-tdt-0.6b-v3-stock"`. FluidAudio downloads it to `~/Library/Application Support/parakeet-tdt-0.6b-v3/` as before. Here `[transcription] language` drives the decoder's token filter: it keeps tokens in the language's script, and for `uk` also drops Russian-only letters (`ы э ъ ё`). Mind that `uk` also blocks Latin, so English words come out in Cyrillic. Any value that is not a language code (e.g. `"none"`) turns the filter off.

Upgrading from 1.7.0 or earlier: `model = "parakeet-tdt-0.6b-v3"` was the only model name, so on first start souffleur rewrites it to `parakeet-tdt-0.6b-v3-uk` (backup in `config.toml.bak-1.7.0`). To keep the multilingual model, set `parakeet-tdt-0.6b-v3-stock`; the rewrite never touches it.

Model credit: the Ukrainian fine-tune is by [ihnatov-yuri](https://huggingface.co/ihnatov-yuri), released under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/), based on [nvidia/parakeet-tdt-0.6b-v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3) (CC BY 4.0).

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

### Auto-Enter delay

With `auto_enter = true` souffleur pastes with Cmd+V and presses Return `enter_delay_ms` later (default 200). If the text lands but is not sent, for example in Claude Code inside Zellij, raise it:

```toml
[output]
enter_delay_ms = 500
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
- **Parakeet** (NVIDIA NeMo via [FluidAudio](https://github.com/FluidInference/FluidAudio)) - fast, default; Ukrainian fine-tune or stock multilingual, see [Models](#models)
- **WhisperKit** (OpenAI Whisper via [WhisperKit](https://github.com/argmaxinc/WhisperKit)) - more accurate for some languages

Both run entirely on-device. LLM post-processing (Ollama and OpenAI) is opt-in.
