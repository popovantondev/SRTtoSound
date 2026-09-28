# Drittanbieterkomponenten und Hinweise

Deutsche Fassung · [English](THIRD_PARTY.en.md) · [Русский](THIRD_PARTY.ru.md)

Diese Übersicht gilt für SRT to Sound. Sie ist keine Lizenz für das Projekt und ersetzt nicht die Bedingungen der Drittanbieter. Das App-Releasepaket enthält weder FFmpeg noch Python-Pakete, Silero oder Modellgewichte.

## App- und Apple-Komponenten

Der Quellcode verwendet von Apple bereitgestellte macOS-Frameworks und Befehlszeilenprogramme, darunter AppKit, AVFoundation, Swift und Ruby. Diese stammen von Apple/macOS und werden von diesem Projekt nicht in den Quellcodeexport kopiert. Für ihre Nutzung gelten die jeweiligen Apple-Bedingungen.

Die Projektsymbole und Skripte sind Projektmaterialien. Für sie gelten ausschließlich die eingeschränkten Rechte aus [RIGHTS.de.md](RIGHTS.de.md); eine projektweite Open-Source-Lizenz wird nicht erteilt.

## FFmpeg

Die App verwendet ein Programm, das der Nutzer separat installiert. Das Repository und das App-Releasepaket enthalten keine FFmpeg-Programme oder -Bibliotheken. Laut FFmpeg steht der Großteil des Codes unter LGPL 2.1 oder neuer. Durch optionale GPL-Komponenten kann stattdessen GPL 2 oder neuer gelten. Die Bedingungen eines konkret installierten Builds hängen von dessen Konfiguration und enthaltenen Komponenten ab. Siehe [rechtliche Hinweise zu FFmpeg](https://ffmpeg.org/legal.html) und [FFmpeg-Lizenzdetails](https://ffmpeg.org/doxygen/trunk/md_LICENSE.html).

## Silero und Modellgewichte

Der Quellcode verwendet das Python-Paket Silero TTS und erwartet eine lokal bereitgestellte Modelldatei `v5_5_ru.pt`; beides wird nicht mitgeliefert. Im Upstream-Commit [`639eade`](https://github.com/snakers4/silero-models/tree/639eade0329fd0d99aa15dcfd204239a10c9be7e) beschreibt die README das russische V5-Modell als `v5_ru` mit den Stimmen `aidar`, `baya`, `kseniya`, `xenia` und `eugene`. Laut README gilt MIT nur für die separat bereitgestellten Modelle `v5_cis_base`. Der installierte Silero-Loader 0.5.5 und die geprüfte Modelldatei verwenden den lokalen Dateinamen bzw. Loader-Bezeichner `v5_5_ru`; die festgehaltene Upstream-README und der Modellindex dokumentieren diese genaue Zuordnung von Alias und Datei jedoch nicht ausdrücklich. Die lokal geprüfte Datei hatte den SHA-256-Wert `50081637b602126ee06cb3bc8a744d25651d2da149ee8864b9a379bfdd934437`. Diese Prüfsumme identifiziert die geprüften Bytes, bestätigt aber weder unabhängig deren Herausgeber noch die geltende Lizenz.

Im selben Commit widersprechen sich außerdem die Lizenzangaben im Upstream: Das README-Abzeichen nennt „CC BY-NC 4.0“, und der Lizenzabschnitt bezeichnet die allgemeinen Bedingungen als „CC-NC-BY“. Die tatsächlich festgehaltene [`LICENSE`-Datei](https://github.com/snakers4/silero-models/blob/639eade0329fd0d99aa15dcfd204239a10c9be7e/LICENSE) enthält dagegen den vollständigen Text der Creative-Commons-Lizenz Attribution-NonCommercial-ShareAlike 4.0 International (CC BY-NC-SA 4.0). Dieses Projekt setzt vorsorglich den strengsten bestätigten Nutzungsrahmen: **nur persönliche, nichtkommerzielle Nutzung**. Nutzen Sie das Silero-Modell nicht kommerziell und verbreiten Sie die Modellgewichte nicht über dieses Projekt. Die genaue Zuordnung der lokal geprüften Datei `v5_5_ru.pt` zum festgehaltenen Upstream-Modell und dessen Lizenz wurde nicht unabhängig bestätigt. Dieser Hinweis ist eine vorsorgliche Projektbeschränkung, keine rechtliche Schlussfolgerung und keine Klärung des Widerspruchs. Holen Sie eine schriftliche Klarstellung oder Erlaubnis des Rechteinhabers ein, bevor Sie weitergehende Rechte voraussetzen.

Quellen: [festgehaltene Silero-README](https://github.com/snakers4/silero-models/blob/639eade0329fd0d99aa15dcfd204239a10c9be7e/README.md), [festgehaltene Upstream-LICENSE](https://github.com/snakers4/silero-models/blob/639eade0329fd0d99aa15dcfd204239a10c9be7e/LICENSE), [festgehaltener Modellindex](https://github.com/snakers4/silero-models/blob/639eade0329fd0d99aa15dcfd204239a10c9be7e/models.yml) und [offizielle Modelldatei](https://models.silero.ai/models/tts/ru/v5_5_ru.pt).

## Python-Abhängigkeiten

PyTorch, SoundFile, NumPy und weitere Python-Pakete sind nicht enthalten. `requirements-silero.txt` legt Abhängigkeitsversionen fest, ist aber keine vollständige Lizenzgewährung für Drittkomponenten. Für jedes Paket gelten dessen eigene Lizenz und Hinweise. Wer die optionale Umgebung installiert, sollte die Paketmetadaten der tatsächlich bezogenen Versionen prüfen.

In der isolierten QA-Umgebung mit Python 3.12.14 für ARM64 wurden genau die unten aufgeführten Laufzeitversionen installiert. Die Lizenzangaben fassen, soweit vorhanden, `License-Expression`, `License`, Klassifizierer und enthaltene Lizenzdateien der installierten Distributionen zusammen. Dies ist eine Bestandsaufnahme, keine Rechtsberatung. Die Abhängigkeiten werden vom Nutzer installiert und nicht in App oder Releasepaket kopiert. Einige Binär-Wheels, insbesondere NumPy, PyTorch und setuptools, können weitere Drittkomponenten mit eigenen Hinweisen enthalten; prüfen Sie die Hinweise im jeweiligen installierten Paket.

| Paket | Festgelegte Version | Angegebene Lizenz |
|---|---:|---|
| antlr4-python3-runtime | 4.9.3 | BSD |
| cffi | 2.0.0 | MIT |
| filelock | 3.19.1 | Unlicense |
| fsspec | 2025.10.0 | BSD-3-Clause |
| Jinja2 | 3.1.6 | BSD |
| MarkupSafe | 3.0.3 | BSD-3-Clause |
| mpmath | 1.3.0 | BSD |
| networkx | 3.2.1 | BSD |
| numpy | 2.0.2 | BSD; das Wheel enthält weitere lizenzierte Komponenten |
| omegaconf | 2.3.1 | BSD |
| pycparser | 2.23 | BSD-3-Clause |
| PyYAML | 6.0.3 | MIT |
| setuptools | 84.0.0 | MIT |
| silero (Python-Paket) | 0.5.5 | MIT-Metadaten; für die separaten Modellgewichte gelten die obigen Bedingungen |
| soundfile | 0.13.1 | BSD-3-Clause |
| sympy | 1.14.0 | BSD |
| torch | 2.8.0 | BSD-3-Clause; Hinweise auf im Wheel enthaltene Komponenten prüfen |
| typing_extensions | 4.16.0 | PSF-2.0 |

## Umfang der Prüfung

Dies ist eine Prüfung des Quellcodes und des Abhängigkeitspfads für den Kandidaten, keine Rechtsberatung und keine vollständige Stückliste für eine bestimmte lokale Installation. Dieser Hinweis erlaubt nicht, Drittanbieter-Modelle oder Medien in das Projekt aufzunehmen.
