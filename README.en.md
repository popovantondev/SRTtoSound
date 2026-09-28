# SRT to Sound 3.5.0 — User and developer guide

English documentation. Other languages: [Deutsch](README.de.md) · [Русский](README.ru.md) · [Repository overview](README.md).

![SRT to Sound queue in English](docs/screenshots/interface-en.png)

## Quick start

When a reviewed release is available, download and extract its archive and read the release notes. Before synthesizing speech, follow the [English installation guide](docs/INSTALLATION.en.md) to install FFmpeg, the separate Python/Silero environment, and the model. Then add final Russian subtitle files (`.ru.srt`) or a folder. Select one of five Silero voices (Kseniya is the default), AAC/M4A or WAV, and an output location. The source SRT remains unchanged.

The project runs locally and does not call ChatGPT or a paid API. It has no Siri or macOS system-voice synthesis path.

### Dependencies and first output

FFmpeg, a separate Python 3.12 ARM64 environment, and the Silero `v5_5_ru.pt` model are required and set up separately. They are not included in the app bundle. The release archive includes the pinned dependency list, but not the installed packages or model weights. The app does not download or install dependencies during synthesis. This project adopts a strict personal, non-commercial-only use scope for Silero; model weights are not redistributed. Read the [English installation guide](docs/INSTALLATION.en.md) and [third-party notices](THIRD_PARTY.en.md) before use.

The software requires macOS 15+ and Apple silicon. Releases are not notarized; macOS may display a security warning. The [installation guide](docs/INSTALLATION.en.md) explains checksum verification and Apple's one-app security flow. Never disable macOS security globally, and do not open an archive whose checksum does not match.

## User documentation

- [English changelog](CHANGELOG.en.md)
- [Third-party notices and model terms](THIRD_PARTY.en.md)
- [Rights](RIGHTS.en.md)

## Developer documentation

Follow the [English build and test guide](docs/BUILD.en.md). It explains the safe build output, test commands, and release-packaging boundary.

## Reports

Before filing an issue, replace real names and content with synthetic examples. Remove personal information, private subtitles, audio/video, logs, absolute paths, usernames, and machine-specific voice/model details. Use the [English bug-report form](.github/ISSUE_TEMPLATE/bug_report.yml) or [feature-request form](.github/ISSUE_TEMPLATE/feature_request.yml); both have localized alternatives. Screenshots must show only synthetic files.

## Downloads and rights

The Releases area is the download source when releases are published. Each entry should contain the archive, SHA-256 checksums, release notes, and explicit non-notarized/dependency information. Read the [English rights notice](RIGHTS.en.md) and [third-party notices](THIRD_PARTY.en.md) before use.
