# SRT to Sound bauen und testen

Deutsche Anleitung · [English](BUILD.en.md) · [Русский](BUILD.md) · [Installation](INSTALLATION.de.md)

![Warteschlange von SRT to Sound auf Deutsch](screenshots/interface-de-dark.png)

Diese Anleitung gilt für die aktuelle Versionsreihe 3.5. Sie enthält keine gerätespezifischen Pfade oder Nutzerdaten.

## Voraussetzungen

- macOS 15 oder neuer auf Apple Silicon;
- Xcode Command Line Tools (`xcrun --find swiftc` und `/usr/bin/ruby --version` müssen funktionieren);
- eine separate FFmpeg-Installation für AAC-Export und Zeitanpassung.

Silero wird weder zum Kompilieren der App noch für die synthetischen Tests benötigt. Für einen echten Sprachtest folgen Sie der [Installationsanleitung](INSTALLATION.de.md). Dort werden die separate Python-3.12-ARM64-Umgebung und das manuell bereitgestellte Modell beschrieben.

## Prüfen und bauen

Führen Sie die Befehle im Stammverzeichnis des Repositorys aus:

```sh
./scripts/test.sh
./scripts/build.sh
```

Das Testskript meldet die tatsächliche Anzahl der ausgeführten, fehlgeschlagenen, fehlerhaften und übersprungenen Tests. Der Build erstellt ein neues `dist/SRT to Sound 3.5.0.app`, überschreibt keine vorhandene App und installiert oder startet die App nicht. Mit einem optionalen Argument wählen Sie einen anderen Ausgabeordner.

## Release-Paket erstellen

Das Paketieren eines Releases ist ein separater, zu prüfender Schritt. `PUBLIC_EXPORT_FILES.txt` enthält die genaue Dateiliste für den Quellcodeexport. Das Paketskript liest sie aus dem Release-Tag, lehnt unsichere oder nicht versionierte Pfade ab und archiviert ausschließlich die aufgeführten Dateien. Zusätzlich verlangt es einen sauberen Checkout passend zum Versions-Tag, prüft die App und das eingebettete Quellcodeverzeichnis und überschreibt keinen vorhandenen Versionsordner. Führen Sie es nicht für einen unvollständigen Prüfstand oder ein vom Eigentümer noch nicht angenommenes Release aus.

Die App ist lokal mit Ad-hoc-Signatur signiert, aber von Apple nicht notariell beglaubigt. FFmpeg, Python-Pakete, Silero und Modellgewichte sind separate Abhängigkeiten. Lesen Sie vor einem öffentlichen Paket die [Drittanbieterhinweise](../THIRD_PARTY.de.md) und die [Nutzungsrechte](../RIGHTS.de.md).
