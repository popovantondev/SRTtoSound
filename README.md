<!-- ppk-readme:head:start -->
<a href="https://popovantondev.github.io/SRTtoSound/index.html"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/popovantondev/SRTtoSound/main/docs/readme/header-de-dark.dee1b943.svg"><img src="https://raw.githubusercontent.com/popovantondev/SRTtoSound/main/docs/readme/header-de-light.b196a704.svg" width="880" alt="SRT to Sound — Erstellt russische Sprachausgabe aus fertigen SRT-Untertiteln. macOS 15+ · Apple Silicon, Release 3.5.0"></picture></a>
<!-- ppk-readme:head:end -->

# SRT to Sound

[Русский](README.ru.md) · **Deutsch** · [English](README.en.md)

<!-- ppk-readme:body:start -->
<p>
<a href="https://github.com/popovantondev/SRTtoSound/releases/tag/v3.5.0"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/popovantondev/SRTtoSound/main/docs/readme/btn-download-de-dark.e099dd2d.svg"><img src="https://raw.githubusercontent.com/popovantondev/SRTtoSound/main/docs/readme/btn-download-de-light.12bbe56a.svg" width="171" alt="Herunterladen"></picture></a>
<a href="https://popovantondev.github.io/SRTtoSound/index.html"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/popovantondev/SRTtoSound/main/docs/readme/btn-website-de-dark.190a064e.svg"><img src="https://raw.githubusercontent.com/popovantondev/SRTtoSound/main/docs/readme/btn-website-de-light.1a0174ca.svg" width="129" alt="Webseite"></picture></a>
<a href="https://popovantondev.github.io/SRTtoSound/Guide-de.html"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/popovantondev/SRTtoSound/main/docs/readme/btn-guide-de-dark.1b9d4f6d.svg"><img src="https://raw.githubusercontent.com/popovantondev/SRTtoSound/main/docs/readme/btn-guide-de-light.1d2b5179.svg" width="134" alt="Anleitung"></picture></a>
<a href="https://github.com/popovantondev/SRTtoSound/issues/new/choose"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/popovantondev/SRTtoSound/main/docs/readme/btn-bug-de-dark.e3ca3bf4.svg"><img src="https://raw.githubusercontent.com/popovantondev/SRTtoSound/main/docs/readme/btn-bug-de-light.496f0ead.svg" width="168" alt="Fehler melden"></picture></a>
</p>

<p><a href="https://raw.githubusercontent.com/popovantondev/SRTtoSound/main/docs/screenshots/interface-de-dark.png"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/popovantondev/SRTtoSound/main/docs/readme/preview-de-dark.967233e3.webp"><img src="https://raw.githubusercontent.com/popovantondev/SRTtoSound/main/docs/readme/preview-de-light.a432e836.webp" width="880" alt="Oberfläche von SRT to Sound"></picture></a><br>
<sub><a href="https://raw.githubusercontent.com/popovantondev/SRTtoSound/main/docs/screenshots/interface-de-dark.png">Ganzer Screenshot</a></sub></p>

<picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/popovantondev/SRTtoSound/main/docs/readme/divider-dark.4bfba62c.svg"><img src="https://raw.githubusercontent.com/popovantondev/SRTtoSound/main/docs/readme/divider-light.471a8c7b.svg" width="880" alt="Trennlinie"></picture>
<!-- ppk-readme:body:end -->

<!-- public-release:start -->
Erstellt synchronisierte russische Sprachausgabe aus fertigen SRT-Untertiteln als M4A oder WAV.

**macOS 15+ · Apple Silicon · Release 3.5.0**

**[Herunterladen](https://github.com/popovantondev/SRTtoSound/releases/tag/v3.5.0)** · **[Anleitung](https://popovantondev.github.io/SRTtoSound/Guide-de.html)** · **[Fehler melden](https://github.com/popovantondev/SRTtoSound/issues/new/choose)**

**Voraussetzungen und Grenzen:** Python 3.12 ARM64, FFmpeg, Silero-Pakete und Modell v5_5_ru.pt separat installieren; nicht im ZIP enthalten. Keine Apple-Notarisierung.

**Erste Schritte:** App entpacken und zuerst die Abhängigkeiten nach Anleitung einrichten. .ru.srt hinzufügen, Stimme, Format und Ausgabeordner wählen.

**App-Dateien:**

- [`SRT-to-Sound-3.5.0-macOS-arm64.zip`](https://github.com/popovantondev/SRTtoSound/releases/download/v3.5.0/SRT-to-Sound-3.5.0-macOS-arm64.zip)

**Prüfsummen:** [`SHA256SUMS`](https://github.com/popovantondev/SRTtoSound/releases/download/v3.5.0/SHA256SUMS)
<!-- public-release:end -->

## Schnellstart

Das aktuelle Release 3.5.0 ist verfügbar. Laden Sie das Archiv herunter, entpacken Sie es und lesen Sie vor der Nutzung die Versionshinweise. Befolgen Sie vor der Sprachsynthese die [deutsche Installationsanleitung](docs/INSTALLATION.de.md), um FFmpeg, die separate Python-/Silero-Umgebung und das Modell einzurichten. Fügen Sie anschließend fertige russische Untertiteldateien (`.ru.srt`) oder einen Ordner hinzu. Wählen Sie eine von fünf Silero-Stimmen (Kseniya ist voreingestellt), AAC/M4A oder WAV sowie den Speicherort. Die Quelldatei bleibt unverändert.

Die Verarbeitung läuft lokal. Siri und macOS-Systemstimmen sind in dieser Version nicht enthalten.

### Abhängigkeiten und erste Audiospur

FFmpeg, eine separate Python-3.12-ARM64-Umgebung und das Silero-Modell `v5_5_ru.pt` sind erforderlich und müssen separat eingerichtet werden. Sie sind nicht im App-Bundle enthalten. Das Release-Archiv enthält die Liste der festgelegten Abhängigkeiten, jedoch nicht die installierten Pakete oder Modellgewichte. Während der Vertonung lädt oder installiert die App nichts. Für Silero gilt in diesem Projekt strikt: nur private, nichtkommerzielle Nutzung; Modellgewichte werden nicht weitergegeben. Lesen Sie vor der Nutzung die [Drittanbieterhinweise](THIRD_PARTY.de.md).

Voraussetzung sind macOS 15+ und Apple Silicon. Releases sind nicht notarisiert; macOS kann eine Sicherheitswarnung anzeigen. Prüfen Sie vor dem Öffnen die veröffentlichte SHA-256-Prüfsumme. Umgehen Sie Sicherheitsabfragen nur, wenn Sie dem verifizierten Release vertrauen.

## Dokumentation für Benutzer

- [Installationsanleitung](docs/INSTALLATION.de.md)
- [Änderungsprotokoll](CHANGELOG.de.md)
- [Hinweise zu Drittkomponenten und Modellbedingungen](THIRD_PARTY.de.md)

## Dokumentation für Entwickler

Folgen Sie der [deutschen Bau- und Testanleitung](docs/BUILD.de.md). Dort stehen die Testbefehle, der sichere Ausgabeordner und die Grenzen der Release-Paketierung.

## Fehlerberichte

Ersetzen Sie echte Namen und Inhalte durch synthetische Beispiele. Entfernen Sie persönliche Daten, private Untertitel, Audio/Video, Logs, absolute Pfade, Benutzernamen sowie gerätebezogene Stimmen- und Modelldetails. Verwenden Sie das [deutsche Fehlerformular](https://github.com/popovantondev/SRTtoSound/issues/new?template=bug_report_de.yml) oder das [Formular für Funktionswünsche](https://github.com/popovantondev/SRTtoSound/issues/new?template=feature_request_de.yml). Beide Vorlagen sind lokalisiert und erinnern an den Datenschutz. Screenshots dürfen nur synthetische Dateien zeigen.

## Downloads und Rechte

Das aktuelle macOS-Release, das Quellcodearchiv und die SHA-256-Prüfsummen finden Sie unter [SRT to Sound 3.5.0](https://github.com/popovantondev/SRTtoSound/releases/tag/v3.5.0). Die App ist ad-hoc signiert und von Apple nicht notarisiert; FFmpeg, Python 3.12 ARM64, Silero-Pakete und Modellgewichte müssen separat installiert werden. Lesen Sie vor der Nutzung die [deutschen Nutzungsrechte](RIGHTS.de.md) und [Drittanbieterhinweise](THIRD_PARTY.de.md).
