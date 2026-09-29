# SRT to Sound

[User guide](https://popovantondev.github.io/SRTtoSound/Guide-en.html)

Apple silicon · macOS 15+ · Version 3.5.0

Offline macOS software that turns Russian subtitle files (`.ru.srt`) into synchronized AAC/M4A or WAV voiceover. Designed for macOS 15+ and Apple silicon. Speech synthesis uses only the locally installed Silero model; five Russian voices are available, with Kseniya selected by default. No Siri, macOS system-voice, network API, translation, or video-muxing feature is included.

## Documentation

- [English](README.en.md) · [Deutsch](README.de.md) · [Русский](README.ru.md)
- Installation: [English](docs/INSTALLATION.en.md) · [Deutsch](docs/INSTALLATION.de.md) · [Русский](docs/INSTALLATION.md)
- Developer build guide: [English](docs/BUILD.en.md) · [Deutsch](docs/BUILD.de.md) · [Русский](docs/BUILD.md)
- Changelog: [English](CHANGELOG.en.md) · [Deutsch](CHANGELOG.de.md) · [Русский](CHANGELOG.md)
- Third-party notices: [English](THIRD_PARTY.en.md) · [Deutsch](THIRD_PARTY.de.md) · [Русский](THIRD_PARTY.ru.md)
- Rights: [English](RIGHTS.en.md) · [Deutsch](RIGHTS.de.md) · [Русский](RIGHTS.ru.md)

## Screenshots

The screenshots use synthetic queue entries only; no real lecture, audio, account, filesystem path, or personal voice/model setting is shown. Each translated guide embeds the screenshot matching its interface language.

![SRT to Sound main window, English interface](docs/screenshots/interface-en.png)

Localized examples: [Русский интерфейс](docs/screenshots/interface-ru.png) · [Deutsche Oberfläche im dunklen Modus](docs/screenshots/interface-de-dark.png)

## Downloads

Download the current macOS release, source archive, and SHA-256 checksums from [SRT to Sound 3.5.0](https://github.com/popovantondev/SRTtoSound/releases/tag/v3.5.0). The app is ad-hoc signed and not notarized; FFmpeg, Python 3.12 ARM64, Silero packages, and model weights must be installed separately. Verify the archive checksum and signature before opening it.

## Quick start

1. Download and extract a reviewed release archive from the Releases area; read its release notes.
2. Before using speech generation, complete the separate FFmpeg, Python 3.12 ARM64, Silero dependencies, and model setup in the [installation guide](docs/INSTALLATION.en.md). These runtime components and model weights are not bundled with the app. This project restricts Silero use to personal, non-commercial tasks; model weights are not redistributed. See [third-party notices](THIRD_PARTY.en.md) for the disclosed model/license mapping uncertainty.
3. Open the app, add final `.ru.srt` files or a folder, choose a voice, AAC/M4A or WAV, and an output location, then start the queue.

The app does not modify source SRT files. AAC/M4A is the default output; WAV is also available. Speech preparation runs locally. See the translated guides for setup details and limitations.

## Development

```sh
./scripts/test.sh
./scripts/build.sh
```

Build in an isolated development copy. The translated guides include user and developer instructions. Run `./scripts/test.sh` for the test suite and `./scripts/build.sh` for a local build.

## Rights

This repository grants source viewing only. The only permission granted for the application binary is personal use of an unmodified copy. No open-source license or permission to modify, redistribute, sublicense, or commercially use project materials is granted. See [RIGHTS.en.md](RIGHTS.en.md); third-party components retain their own terms.
