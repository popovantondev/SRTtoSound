# SRT to Sound 3.5.0 installieren

Deutsche Anleitung · [English](INSTALLATION.en.md) · [Русский](INSTALLATION.md) · [Bauen und testen](BUILD.de.md)

![Warteschlange von SRT to Sound auf Deutsch](screenshots/interface-de-dark.png)

## Voraussetzungen

Die App ist für macOS 15+ auf Apple Silicon vorgesehen. Das App-Archiv enthält weder Python, PyTorch, Silero, Modellgewichte noch FFmpeg. Die App installiert oder lädt diese Komponenten beim Start und während der Sprachsynthese nicht herunter.

Für die Sprachsynthese benötigen Sie eine separate **Python-3.12-ARM64**-Umgebung, die in `requirements-silero.txt` festgelegten Pakete und das Silero-Modell `v5_5_ru.pt`. Für AAC/M4A und die Zeitanpassung ist FFmpeg erforderlich. Silero läuft lokal und unterstützt Kseniya, Xenia, Baya, Aidar und Eugene. In diesem Projekt ist die Nutzung von Silero strikt auf private, nichtkommerzielle Zwecke beschränkt; eine kommerzielle Nutzung ist ausgeschlossen. Das Modell ist nicht enthalten. Die genaue Zuordnung dieser Modelldatei zur Upstream-Lizenz wurde nicht unabhängig bestätigt; Einzelheiten und Primärquellen finden Sie in den [Drittanbieterhinweisen](../THIRD_PARTY.de.md).

> Für diesen Kandidaten 3.5.0 wurden Python 3.12 ARM64, die festgelegten Pakete, das lokale Modell und kurze echte Synthesen in einem isolierten QA-Ordner auf einem Mac geprüft. Ein separater Mac und ein separates macOS-Benutzerkonto wurden nicht getestet. Verwenden Sie weder die alte Python-3.9-Umgebung noch Ordner von SRT Озвучка 2 weiter.

## Datenordner der neuen App

- Einstellungen und Aussprachewörterbuch: `~/Library/Application Support/SRTtoSound`
- Python: `~/Library/Application Support/SRTtoSound/.venv-silero-py312`
- Modell: `~/Library/Application Support/SRTtoSound/models/v5_5_ru.pt`
- Berichte: `~/Library/Logs/SRTtoSound`
- Temporäre Dateien: `~/Library/Caches/SRTtoSound`

Diese Pfade sind von der alten App getrennt. Die neue Version importiert alte Einstellungen nicht automatisch. Wenn Sie Ihr Wörterbuch weiterverwenden möchten, kopieren Sie nur die Datei `произношение.txt` in den neuen Application-Support-Ordner und bewahren Sie das Original auf.

## FFmpeg

Installieren Sie FFmpeg separat. Wenn Homebrew bereits installiert ist, führen Sie Folgendes aus:

```bash
brew install ffmpeg
ffmpeg -version
```

FFmpeg muss unter `/opt/homebrew/bin/ffmpeg` oder über `PATH` verfügbar sein. Die App sollte für Bereitschaftsprüfung und Verarbeitung dieselbe ausführbare Datei verwenden. FFmpeg wird für AAC-LC/M4A und die gleichmäßige Zeitanpassung benötigt. M4A ist das Standardformat, WAV eine Alternative.

Falls Homebrew noch nicht installiert ist, nutzen Sie die offizielle Anleitung unter [brew.sh](https://brew.sh/) oder installieren Sie eine vertrauenswürdige FFmpeg-Version für Apple Silicon auf anderem Weg. Fügen Sie keine Installationsbefehle von inoffiziellen Webseiten ein.

## Silero: separate manuelle Einrichtung

Sorgen Sie zuerst für genügend freien Speicherplatz; PyTorch benötigt viel Platz. Installieren Sie Python und Pakete nicht innerhalb des `.app`-Bundles.

Installieren Sie den versionierten Homebrew-Interpreter, ohne das macOS-System-Python zu ersetzen:

```bash
brew install python@3.12
/opt/homebrew/bin/python3.12 --version
/opt/homebrew/bin/python3.12 -c 'import platform; print(platform.machine())'
```

Erwartet werden Python 3.12.x und `arm64`. Wenn `x86_64` angezeigt wird, brechen Sie ab und erstellen Sie die Umgebung nicht über Rosetta.

Öffnen Sie im Finder den entpackten Ordner `SRT to Sound 3.5.0` im Release-Archiv. Darin befinden sich die App und `requirements-silero.txt`. Geben Sie im Terminal `cd ` ein (einschließlich des Leerzeichens), ziehen Sie den Ordner aus dem Finder ins Terminal und drücken Sie Return. Führen Sie anschließend im selben Terminal-Fenster diese Befehle aus:

```bash
PYTHON="/opt/homebrew/bin/python3.12"
REQUIREMENTS="$PWD/requirements-silero.txt"
APP_DATA="$HOME/Library/Application Support/SRTtoSound"
mkdir -p "$APP_DATA/models"
"$PYTHON" -m venv "$APP_DATA/.venv-silero-py312"
"$APP_DATA/.venv-silero-py312/bin/python" -m pip install -r "$REQUIREMENTS"
```

Aktualisieren Sie pip nicht separat: Diese Einrichtung verwendet die in der Datei festgelegten Paketversionen.

Wenn Sie diese Einschränkung und die Bedingungen des Modellanbieters akzeptieren, laden Sie danach manuell das russische Silero-v5.5-Modell herunter:

`https://models.silero.ai/models/tts/ru/v5_5_ru.pt`

Wählen Sie im Finder „Gehe zu“ → „Gehe zum Ordner …“, geben Sie `~/Library/Application Support/SRTtoSound/models` ein und drücken Sie Return. Ziehen Sie die heruntergeladene Datei in diesen Ordner; der Dateiname muss genau `v5_5_ru.pt` lauten. Benennen Sie keine andere Modellversion in diesen Dateinamen um. Notieren Sie die Prüfsumme:

```bash
shasum -a 256 "$HOME/Library/Application Support/SRTtoSound/models/v5_5_ru.pt"
```

Vergleichen Sie das Ergebnis mit der SHA-256-Prüfsumme des geprüften Modells in `THIRD_PARTY.de.md` desselben Releases. Bei Abweichung führen Sie keine Synthese aus und melden Sie die Differenz.

Die App lädt dieses lokale Modell direkt und greift nicht auf ein Modellregister zu. Die Schaltfläche **„Installation prüfen“** prüft das gefundene FFmpeg auf `atempo` und einen AAC-Encoder sowie Python 3.12 und `arm64`. Beim Modell wird nur geprüft, ob eine nicht leere Datei vorhanden ist; die Kompatibilität wird durch einen echten Sprachlauf bestätigt. Bei einem Fehler beachten Sie den Pfad und die technischen Details im Dialog. Die Prüfung installiert oder lädt nichts herunter.

Testen Sie Kseniya mit **Stimme anhören** und probieren Sie danach eine kurze synthetische `.ru.srt`-Datei aus.

## Erste Verwendung

1. Öffnen Sie die App und fügen Sie eine fertige russische `.ru.srt`-Datei oder einen Ordner hinzu.
2. Wählen Sie eine Stimme; Kseniya ist voreingestellt.
3. Lassen Sie AAC/M4A für eine MP4-Tonspur ausgewählt; verwenden Sie WAV nur bei Bedarf.
4. Wählen Sie den Speicherort neben der SRT-Datei oder „Downloads“.
5. Starten Sie die Warteschlange. Die App prüft zuerst alle Dateien und bietet bei Problemen an, nur geeignete Dateien zu verarbeiten oder zur Korrektur zurückzukehren.
6. Prüfen Sie die erstellte `.ru.m4a`/`.ru.wav` und den Bericht. Wählen Sie zum Öffnen des Berichts einer bestimmten Zeile diese in der Warteschlange aus und klicken Sie auf „Bericht öffnen“; ohne ausgewählten Bericht öffnet die Schaltfläche den Berichtsordner. Die ursprüngliche SRT-Datei wird nicht verändert.

## Aktualisierung, Rückkehr und Sicherheit

Beenden Sie SRT to Sound vor einem Update. Laden Sie den Release ausschließlich von der Projektseite „Releases“ herunter und vergleichen Sie das Archiv mit der veröffentlichten SHA-256-Prüfsumme. Entpacken Sie es und behalten Sie die bisherige App, bis die neue Kopie einen kurzen Test bestanden hat. Die App-Namen enthalten die Versionsnummer; legen Sie die aktualisierte App daher neben die frühere SRT-to-Sound-Version, statt sie zu überschreiben. SRT Озвучка 2 bleibt getrennt.

Für eine Rückkehr beenden Sie die neuere Kopie und öffnen die frühere SRT-to-Sound-App. SRT-to-Sound-Versionen 3.5.x verwenden denselben Datenordner `~/Library/Application Support/SRTtoSound`; eine Rückkehr stellt frühere Einstellungen nicht automatisch wieder her. Löschen Sie diesen Ordner und die getrennten Logs-/Caches-Ordner nicht beim App-Update. Beim Löschen des App-Bundles werden die Datenordner nicht entfernt.

Diese App ist ad-hoc-signiert und nicht von Apple notarisiert. macOS kann warnen, dass der Entwickler nicht verifiziert werden kann oder die App nicht auf Schadsoftware geprüft wurde. Apple empfiehlt Vorsicht, weil nicht notarisiertes Programm nicht geprüft wurde. Am sichersten ist es, Software, deren Herkunft Sie nicht überprüfen können, nicht zu öffnen. Wenn Sie dennoch fortfahren möchten, prüfen Sie zuerst die Archiv-Prüfsumme des offiziellen Releases genau und verwenden Sie dann Apples dokumentierten **„Open Anyway“**-Ablauf für diese eine App unter „Datenschutz & Sicherheit“—ändern Sie nicht die globalen Sicherheitseinstellungen. Siehe [Apples Sicherheitshinweise](https://support.apple.com/en-us/102445). Bei abweichender Prüfsumme öffnen Sie die App nicht.

Der Installationsstatus muss für jedes konkrete Release in den Release-Hinweisen stehen. Diese Anleitung allein belegt keine Kompatibilität; eine saubere Python-3.12-ARM64-Umgebung muss eine echte Synthese erfolgreich ausführen.
