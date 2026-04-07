# Souffleur

Local speech-to-text daemon for macOS, powered by [Parakeet](https://github.com/NVIDIA/NeMo) and [WhisperKit](https://github.com/argmaxinc/WhisperKit) CoreML models.

Press a hotkey, speak, release - text gets typed into the active app.

## Install

```bash
brew tap bog-dance/souffleur
brew install souffleur
sofl service install
```

Grant **Accessibility** and **Microphone** permissions when prompted.

## Usage

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

## Hotkeys

| Key | Action |
|-----|--------|
| F3 (hold) | Record + transcribe + auto-enter |
| F4 (hold) | Record + transcribe (no enter) |
| F5 (hold) | Record + transcribe with Whisper |

All hotkeys are configurable.

## Configuration

Config file: `~/.config/souffleur/config.toml`

```toml
[hotkey]
trigger_auto_enter = "f3"
trigger_no_enter = "f4"
trigger_whisper = "f5"
cancel_delay = 0.0

[audio]
device = "default"
sample_rate = 16000

[transcription]
model = "large-v3-turbo"
whisper_model = "large-v3"
language = "uk"

[output]
auto_paste = true

[overlay]
enabled = true
```

## How it works

Souffleur runs as a background daemon with a menu bar icon. It listens for global hotkeys, records audio from the microphone, transcribes it locally using CoreML models, and types the result into the active application via the pasteboard.

Two transcription backends:
- **Parakeet** (NVIDIA NeMo) - fast, used by default (F3/F4)
- **WhisperKit** (OpenAI Whisper) - more accurate for some languages (F5)

Both models run entirely on-device.
