# Installing SRT to Sound 3.5.0

English instructions · [Deutsch](INSTALLATION.de.md) · [Русский](INSTALLATION.md) · [Build and test](BUILD.en.md)

![SRT to Sound queue in English](screenshots/interface-en.png)

## Requirements

The app is for macOS 15+ on Apple silicon. The app archive does not contain Python, PyTorch, Silero, model weights, or FFmpeg. The app does not install or download them when it starts or synthesizes speech.

Speech synthesis requires a separate **Python 3.12 ARM64** environment, the pinned packages in `requirements-silero.txt`, and the Silero `v5_5_ru.pt` model. FFmpeg is required for AAC/M4A and timing adjustment. Silero runs locally and provides Kseniya, Xenia, Baya, Aidar, and Eugene. Within this project, Silero use is restricted to personal, non-commercial tasks; do not use it for commercial work. The model is not bundled. The exact mapping of this model file to the upstream license has not been independently confirmed; see [third-party notices](../THIRD_PARTY.en.md) for details and primary-source links.

> For this 3.5.0 candidate, Python 3.12 ARM64, the pinned packages, the local model, and short real synthesis runs were tested in an isolated QA folder on one Mac. A separate Mac and macOS account were not tested. Do not reuse the old Python 3.9 environment or folders belonging to SRT Озвучка 2.

## New app data folders

- Settings and pronunciation dictionary: `~/Library/Application Support/SRTtoSound`
- Python: `~/Library/Application Support/SRTtoSound/.venv-silero-py312`
- Model: `~/Library/Application Support/SRTtoSound/models/v5_5_ru.pt`
- Reports: `~/Library/Logs/SRTtoSound`
- Temporary files: `~/Library/Caches/SRTtoSound`

These paths are separate from the old app. The new version does not import old settings automatically. To reuse your own dictionary, copy only `произношение.txt` into the new Application Support folder; keep the original.

## FFmpeg

Install FFmpeg separately. If Homebrew is already installed, run:

```bash
brew install ffmpeg
ffmpeg -version
```

Make sure it is available at `/opt/homebrew/bin/ffmpeg` or on `PATH`. The app should use the same executable for readiness checks and processing. FFmpeg is required for AAC-LC/M4A and smooth timing adjustment. M4A is the default; WAV is an alternative.

If Homebrew is not installed, use its official installation instructions at [brew.sh](https://brew.sh/) or install a trusted Apple-silicon FFmpeg build by another method. Do not paste installation commands from unofficial websites.

## Silero: separate manual setup

First make sure there is enough free disk space; PyTorch is large. Do not install Python or packages inside the `.app` bundle.

Install the versioned Homebrew interpreter without replacing macOS's system Python:

```bash
brew install python@3.12
/opt/homebrew/bin/python3.12 --version
/opt/homebrew/bin/python3.12 -c 'import platform; print(platform.machine())'
```

Expect Python 3.12.x and `arm64`. If the architecture is `x86_64`, stop; do not create this environment through Rosetta.

In Finder, open the extracted `SRT to Sound 3.5.0` folder inside the release archive. It contains the app and `requirements-silero.txt`. In Terminal, type `cd ` (including the trailing space), drag that folder from Finder into Terminal, and press Return. Then run these commands in the same Terminal window:

```bash
PYTHON="/opt/homebrew/bin/python3.12"
REQUIREMENTS="$PWD/requirements-silero.txt"
APP_DATA="$HOME/Library/Application Support/SRTtoSound"
mkdir -p "$APP_DATA/models"
"$PYTHON" -m venv "$APP_DATA/.venv-silero-py312"
"$APP_DATA/.venv-silero-py312/bin/python" -m pip install -r "$REQUIREMENTS"
```

Do not upgrade pip separately; this setup uses the package versions pinned in that file.

If you accept the restriction above and the model provider's terms, manually download Silero v5.5 Russian from:

`https://models.silero.ai/models/tts/ru/v5_5_ru.pt`

In Finder, choose Go → Go to Folder…, enter `~/Library/Application Support/SRTtoSound/models`, and press Return. Drag the downloaded file into this folder; its filename must be exactly `v5_5_ru.pt`. Do not rename a different model version to this filename. Record its checksum:

```bash
shasum -a 256 "$HOME/Library/Application Support/SRTtoSound/models/v5_5_ru.pt"
```

Compare the result with the verified model SHA-256 in `THIRD_PARTY.en.md` from the same release. If they differ, do not synthesize; report the mismatch.

The app loads this local model directly and does not contact a model registry. The **Check setup** button tests the located FFmpeg for `atempo` and an AAC encoder, and separately checks Python 3.12 and `arm64`. For the model, it checks only that a non-empty file exists; compatibility is confirmed by actually running a voice. If a check fails, use the path and technical details shown in the dialog. Nothing is installed or downloaded by that check.

Use **Preview Voice** to test Kseniya, then try a short synthetic `.ru.srt`.

## First use

1. Open the app and add a final Russian `.ru.srt` file or folder.
2. Choose a voice; Kseniya is selected by default.
3. Keep AAC/M4A for an MP4 soundtrack; choose WAV only if needed.
4. Choose to save beside the SRT or in Downloads.
5. Start the queue. The app checks the whole queue first; if it finds problems, it offers to process only usable files or return to fix them.
6. Check the resulting `.ru.m4a`/`.ru.wav` and its report. Select a queue row and click **Open report** to open that file's report; with no selected report, the button opens the reports folder. The source SRT is not modified.

## Updating, rollback, and security

Before installing an update, quit SRT to Sound, download the release only from the project's Releases page, and verify its archive against the published SHA-256 checksum. Extract it and keep the previous app until the new copy has passed a short test. App names include the version, so you can place the updated app beside the earlier SRT to Sound release instead of overwriting it. SRT Озвучка 2 remains separate.

To roll back, quit the newer copy and open the earlier SRT to Sound app. SRT to Sound 3.5.x versions use the same `~/Library/Application Support/SRTtoSound` data folder; rollback does not restore older settings automatically. Do not delete that folder or the separate Logs/Caches folders as part of an app update. Removing an app bundle does not remove its data folders.

This app is ad-hoc signed and not notarized by Apple. macOS may warn that it cannot verify the developer or check the app for malicious software. Apple recommends caution because an unnotarized app has not been reviewed. The safest choice is not to open software you cannot verify. If you choose to proceed, first verify the exact archive checksum from the official release; then use Apple's documented one-app **Open Anyway** flow in Privacy & Security—not a global security change. See [Apple's safety guidance](https://support.apple.com/en-us/102445). If the checksum does not match, do not open the app.

The installation status for a particular release must be recorded in its release notes. This guide alone is not proof of compatibility; a clean Python 3.12 ARM64 environment must complete a real synthesis run.
