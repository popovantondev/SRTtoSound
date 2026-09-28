# Änderungsprotokoll

Deutsche Fassung · [English](CHANGELOG.en.md) · [Русский](CHANGELOG.md)

## 3.5.0 — Release-Kandidat

- Separate SRT-to-Sound-Version für macOS 15+ und Apple Silicon; SRT Озвучка 2 und deren Daten bleiben getrennt.
- Ausschließlich Silero: fünf russische Stimmen, Kseniya als Standard. Siri und Systemstimmen sind nicht enthalten.
- AAC-LC/M4A als Standard, WAV als Alternative; der flüssige Sprechfluss gruppiert Sätze und passt das Tempo an, ohne eine Datei allein wegen eines Tempos über ×1,15 abzulehnen.
- Oberfläche auf RU/DE/EN; helles, dunkles und systemweites Erscheinungsbild; Prüfung der gesamten Warteschlange; strukturierte Fehler und Berichte.
- Vorbereitung und Synthese verwenden denselben geprüften Text. Lokale Pfade für Einstellungen, Modell und Umgebung sind von SRT Озвучка 2 getrennt.
- Der Kandidat ist lokal ad hoc signiert, aber nicht von Apple notariell beglaubigt. FFmpeg, Python 3.12 ARM64, festgelegte Python-Pakete und Silero-Gewichte werden separat eingerichtet.
- Synthetische Szenarien und kurze echte Sprachsynthese wurden in einem isolierten QA-Ordner auf einem Mac geprüft. Kompatibilität mit anderen Rechnern wird nicht zugesichert; beachten Sie die Hinweise des konkreten Downloads.

## 2.0.1 — 25. September 2026

- Betonungszeichen nach kyrillischen Buchstaben werden aus dem Sprachtext entfernt; eckige Klammern werden unter Erhalt ihres Inhalts in runde Klammern umgewandelt.
- Untertitelzeilen, die nur aus Satzzeichen bestehen, werden nicht an die Synthese übergeben. Absolute Zeitmarken und die Gesamtdauer der SRT-Datei bleiben erhalten; eine Datei ohne Wörter führt zu einer verständlichen Fehlermeldung.
- Die ursprüngliche SRT-Datei wird nicht verändert. Unklare Namen werden nicht automatisch geraten.

## 2.0.0 — 4. September 2026

- Ein dichter Sprachabschnitt bricht nicht mehr die ganze Vorlesung ab, nur weil sein Tempo über ×1,15 liegt. Das vollständige PCM wird mit FFmpeg `atempo` verarbeitet; Wörter werden nicht abgeschnitten und starke Beschleunigung bleibt als Warnung sichtbar.
- Bei dichter russischer Sprache werden künstliche Pausen innerhalb eines zusammenhängenden Sprachabschnitts auf 40–120 ms verkürzt, statt mit der verbleibenden Zeit verlängert zu werden. So wird das Muster „schnell — lange Pause — wieder schnell“ vermieden.
- Vor einer echten Videopause bleiben 0,3 Sekunden frei; die übrige Zeit steht zunächst der vorherigen russischen Phrase zur Verfügung. Kurze Sprache lässt die ursprüngliche Pause bestehen; längere nutzt sie, anstatt unnötig zu beschleunigen.
- Das synthetische Regressionsexemplar `sample.ru.srt` wird vollständig verarbeitet: Nach Nutzung der Pausen sank ein Abschnitt mit ×1,30 auf etwa ×1,17; der höchste verbleibende Abschnitt liegt bei etwa ×1,25. Die Testdatei dauert 120 Sekunden.
- App-Version 2.0.0, Build 11, Name „SRT Озвучка 2“ und eigene Bundle-ID. Release 1.3.0 und sein Tag bleiben unverändert.

## 1.3.0 — 3. September 2026

- Der neue Standardmodus **„Flüssig · ganze Sätze“** fasst getrennte SRT-Zeilen zu sinnvollen Phrasen zusammen und berechnet ein gemeinsames Tempo für einen zusammenhängenden Sprachabschnitt. Der frühere Modus mit exakter Orientierung an den Quellmarken bleibt zum Vergleich erhalten.
- Freie Zeit wird durch sanftes Verlangsamen und normale Pausen nur zwischen vollständigen Sätzen genutzt; Fortsetzungen erhalten einen kurzen Übergang. Echte dramatische Pausen bleiben erhalten.
- Ein vollständig lokaler Sprachtext-Normalisierer wurde ergänzt: Zahlen, Jahre, Daten, Uhrzeiten, Dosierungen, Einheiten, Prozente, Brüche, Bereiche, medizinische Abkürzungen und botanisches Latein werden in sprechbares Russisch umgewandelt. Die angezeigte SRT-Datei bleibt unverändert.
- Silero lehnt nun verbliebene Ziffern, lateinischen Text und nicht unterstützte Schriftsysteme ab, statt sie stillschweigend auszulassen.
- Auf einem Mac M4 erzeugt Silero Phrasen mit drei unabhängigen CPU-Prozessen, jeweils mit einem Torch-Thread. Fertige Sprache wird nicht zwischengespeichert. Siri bleibt wegen der gemeinsamen Datei von Apple Kurzbefehle streng sequenziell.
- Mehrdeutige medizinische Zahlen (`5.000 mg`, `1,000 mg`) und wissenschaftliche Schreibweise werden nicht geraten; das Programm fordert eine ausgeschriebene Angabe an. Dosen pro Masse/Volumen, internationale Einheiten, CoQ10 und Folgen wie Omega-3-6-9 werden unterstützt.
- Die Beschleunigung im flüssigen Modus ist auf ×1,15 begrenzt; die gesamte Pause zwischen vollständigen Phrasen auf höchstens 0,8 Sekunden. Lange Zeilen und Vorlesungen ohne Satzzeichen werden mit begrenztem Speicherbedarf aufgeteilt.
- AAC wird nach Möglichkeit mit dem beschleunigten AudioToolbox-Encoder `aac_at` erstellt; andernfalls wird automatisch der Standardencoder FFmpeg `aac` verwendet. Die vollständige Dekodierprüfung bleibt erhalten.
- Vereinfachte Dateinamen: `name.ru.srt` → `name.ru.m4a` oder `name.ru.wav`, ohne den Namen der Stimme. Schutzoptionen für Kopieren, Ersetzen und Überspringen bleiben bestehen.
- App-Version 1.3.0, Build 10 und eigene Bundle-ID. Release 1.2.2 und dessen dauerhafte Geräteeinstellungen für Siri/Silero bleiben unverändert.

## 1.2.2 — 3. September 2026

- Installation unter `/Applications` korrigiert: Die App sucht `srt_gui_job.rb` nicht mehr neben der `.app`.
- Ruby-/Python-Engine, Wörterbuch und Hilfsdateien werden innerhalb der App unter `Contents/Resources/Runtime` signiert.
- Die veränderbare Siri-Datei, das persönliche Aussprachewörterbuch und die Silero-Umgebung liegen nun unter `~/Library/Application Support/SRTVoiceover`; App-Updates überschreiben sie nicht mehr.
- Die Schaltfläche „Siri-Datei“ verweist auf die dauerhafte Datei. Nach dem Wechsel von 1.2.1 ist eine einmalige manuelle Neuauswahl in Apple Kurzbefehle nötig; spätere Patch-Updates können denselben Pfad beibehalten.
- Eine unter `/Applications` gestartete Warteschlange aus 1.2.1 endete vor Synthese und Veröffentlichung; SRT-Quelldateien und vorhandenes Audio blieben unverändert.
- Regressionstests für unabhängige Pfade und Bundle-Inhalte ergänzt. 55 Ruby-Tests / 266 Assertions sowie Swift-Tests bestanden.
- AAC/M4A-Szenarien und die Konsistenz der Silero-Umgebung (`pip check`) wurden nach dem Paketieren geprüft.

## 1.2.1 — 3. September 2026

- Zeitversatz der Sprache behoben: überlappende Zeitmarken und zu kurze Fenster werden vor der Synthese erkannt; die WAV-Dauer wird mit der SRT abgeglichen.
- Milena verwendet bei zusätzlicher Beschleunigung tonhöhenerhaltendes `atempo`; einfaches Resampling wurde entfernt.
- Starke Beschleunigung wird im Protokoll, in der Warteschlangen-Zeile und in der abschließenden Warnungszahl angezeigt.
- Vor jeder Siri-Datei prüft die Übergabe zwei verschiedene Texte, damit keine ganze Vorlesung aus einer alten Phrase gesprochen wird. Die Stimmenummer wird nicht fälschlich als automatisch erkannt dargestellt.
- Ein 180 Sekunden lang stiller Prozess wird beendet; vorhandene Audiodateien bleiben erhalten.
- Separate App, Bundle-ID und Build 8. Gemeinsamen Starter „Open app.command“ ergänzt.
- Dokumentation aktualisiert und alte Anleitungen als Archiv markiert. Der Hauptzweig wird auf den aktuellen Code umgestellt; altes Arbeitsprogramm und frühere ZIP-Dateien bleiben erhalten.
- 51 Ruby-Tests / 235 Assertions und Swift-Tests bestanden. Die Prüfung der installierten Kopie wird separat in `docs/VERIFICATION.md` dokumentiert.

## 1.2.0 — 3. September 2026

- Separate App „SRT Озвучка 1.2“ mit eigenen Einstellungen; 1.1.0 wird nicht ersetzt.
- Speicherortwahl neben jeder SRT oder im Downloads-Ordner wird gespeichert.
- Ordner samt Unterordnern hinzufügen; endgültige `.ru.srt` auswählen und Zwischenteile, Serviceordner und Duplikate ausschließen.
- Bei Namenskonflikten: Kopie, Ersetzen, Überspringen oder Warteschlange stoppen. Prüfung vor Synthese und erneut vor dem Speichern.
- Vorhandenes Audio bleibt bis zur fertigen neuen Spur unverändert; bei geänderter Datei ist eine neue Bestätigung erforderlich. Auch der Dienst-Engine überschreibt bestehende Ergebnisse nicht.
- Berichte in Library/Logs/SRTVoiceover verschoben. Beim Start werden nur abgeschlossene, eigene Berichte älter als 72 Stunden bereinigt; ohne rekursives Löschen oder Folgen von Links.
- Zielordnerzugriff und freier Speicherplatz werden vor der Synthese geprüft.
- Verbleibende Phrasenzeit der aktuellen Datei wird geschätzt; eine Systemmeldung zeigt die Summe der Warteschlange.
- Die Schaltfläche „Siri-Datei“ zeigt den Arbeitstext der aktuellen Version. Apple Kurzbefehle muss weiterhin manuell verknüpft werden.
- AAC-LC/M4A als Standard, WAV optional; Quellzeitmarken und blaues Symbol bleiben erhalten.

Geprüft: 37 Ruby-Tests, 190 Assertions, keine Fehler oder ausgelassenen Tests; Swift-Warteschlangentests; sechs Szenarien über die echte GUI und acht kurze Milena-Spuren; Build, Signatur und Oberfläche. Siri/Silero wurden nicht erneut geprüft. Das Benachrichtigungsbanner benötigt eine Benutzerfreigabe und wurde nicht gesondert bestätigt. Details: `docs/VERIFICATION.md`.

## 1.1.0 — Arbeitsversion, am 3. September 2026 eingefroren

- AAC-LC in M4A als Standard; WAV bleibt verfügbar.
- Formatwahl wird gespeichert; AAC wird nach dem Aufbau der Zeitmarken einmal kodiert.
- Dauer- und Dekodierprüfung vor Veröffentlichung.
- Überschreibschutz in GUI und zentralem `.command`-Starter.
- Warteschlange, Stimmtest, Siri/Milena/Silero, transparentes blaues Symbol.
- Quellcode und Dokumentation in einem separaten Projektordner organisiert.

Prüfungen: 21 Tests / 116 Assertions, keine Fehler oder ausgelassenen Tests; Swift-GUI kompiliert.

### Versionsverwaltung — 3. September 2026

- Lokales Git erstellt und Arbeitsquellcode committed.
- Version mit Tag `v1.1.0` festgehalten.
- Geprüftes ZIP mit fertiger App und Quellcode erstellt; SHA-256 gespeichert.
- Regeln für die weitere Entwicklung und Änderungsprotokoll ergänzt.
- Bei diesem Stand wurden weder Funktionscode noch fertige App geändert; die Versionsnummer wurde nicht künstlich erhöht.
