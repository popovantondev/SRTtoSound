# Changelog

English version · [Deutsch](CHANGELOG.de.md) · [Русский](CHANGELOG.md)

## 3.5.0 — release candidate

- Separate SRT to Sound version for macOS 15+ and Apple silicon; SRT Озвучка 2 and its data remain separate.
- Silero only: five Russian voices, with Kseniya as the default. Siri and system voices are not included.
- AAC-LC/M4A by default, with WAV as an alternative; smooth pacing groups sentences and adjusts timing without rejecting a file solely because tempo exceeds ×1.15.
- RU/DE/EN interface; light, dark, and system themes; whole-queue preflight; structured errors and reports.
- Preparation and synthesis use the same checked text; local settings, model, and environment paths are isolated from SRT Озвучка 2.
- The candidate is ad-hoc signed, not notarized by Apple. FFmpeg, Python 3.12 ARM64, pinned Python packages, and Silero weights are installed separately.
- Synthetic scenarios and short real synthesis were checked in an isolated QA folder on one Mac. Compatibility with other computers is not claimed; consult the notes for the exact downloaded release.

## 2.0.1 — 25 September 2026

- Stress marks following Cyrillic letters are removed from speech text; square brackets become parentheses while their contents are preserved.
- Punctuation-only cues are not sent to synthesis. Absolute speech timestamps and the final SRT duration are preserved; a file with no words returns a clear error.
- Source SRT files are not rewritten. Unclear names are not guessed automatically.

## 2.0.0 — 4 September 2026

- One dense speech segment no longer cancels an entire lecture solely because its tempo exceeds ×1.15. Full PCM is processed through FFmpeg `atempo`; words are not cut, and strong acceleration remains visible as a warning.
- When Russian speech is dense, synthetic pauses inside an island are shortened to 40–120 ms instead of being expanded to fill leftover time. This avoids the pattern “fast — long pause — fast again.”
- Before a real video pause, 0.3 seconds are reserved; the remaining interval is first available to the previous Russian phrase. Short speech keeps the original pause; longer speech uses it instead of adding unnecessary acceleration.
- The regression sample with the synthetic name `sample.ru.srt` now completes: using pauses lowered one ×1.30 section to about ×1.17; the highest remaining section is about ×1.25. Test output duration is 120 seconds.
- App version 2.0.0, build 11, app name “SRT Озвучка 2,” and a separate bundle ID. Release 1.3.0 and its tag are unchanged.

## 1.3.0 — 3 September 2026

- New default **“Smooth · complete sentences”** mode groups split SRT lines into meaningful phrases and calculates one tempo for a continuous speech island. The previous mode following source timestamps exactly remains available for comparison.
- Spare time is filled with gentle slowing and normal pauses only between complete phrases; continuations have a short join. Genuine dramatic pauses are preserved.
- Added a fully local speech normalizer: numbers, years, dates, times, doses, units, percentages, fractions, ranges, medical abbreviations, and botanical Latin are converted into speakable Russian. The displayed SRT is unchanged.
- Silero now rejects remaining digits, Latin text, or unsupported scripts instead of silently dropping them.
- On an M4 Mac, Silero generates phrases with three independent CPU workers, each using one Torch thread. Finished speech is not cached. Siri remains strictly sequential because Apple Shortcuts uses a shared file.
- Ambiguous medical numbers (`5.000 mg`, `1,000 mg`) and scientific notation are no longer guessed; the program asks for the value to be written out. Doses per unit of mass/volume, international units, CoQ10, and omega-3-6-9 chains are supported.
- Smooth-mode acceleration is capped at ×1.15; the total pause between complete phrases is at most 0.8 seconds. Long cues and lectures without punctuation are split with bounded memory use.
- AAC is encoded with accelerated AudioToolbox `aac_at` when available; otherwise it automatically retries with the standard FFmpeg `aac` encoder. Full decode verification remains.
- Output names are simplified: `name.ru.srt` → `name.ru.m4a` or `name.ru.wav`, without the selected voice name. Copy/replace/skip protection remains.
- App version 1.3.0, build 10, separate bundle ID. This release does not change saved 1.2.2 and uses its persistent machine settings for Siri/Silero.

## 1.2.2 — 3 September 2026

- Fixed installation under `/Applications`: the app no longer looks for `srt_gui_job.rb` beside the `.app`.
- Ruby/Python engine, dictionary, and service files are signed inside the app at `Contents/Resources/Runtime`.
- The mutable Siri file, user pronunciation dictionary, and Silero environment were moved to `~/Library/Application Support/SRTVoiceover`; app updates no longer overwrite them.
- The “Siri file” button points to the permanent file. One manual Apple Shortcuts re-selection is required after upgrading from 1.2.1; later patch updates can keep the same path.
- A 1.2.1 queue launched from `/Applications` stopped before synthesis and publication; source SRT and existing audio were preserved.
- Added standalone-path and bundle-content regression checks. 55 Ruby tests / 266 assertions and Swift tests passed.
- AAC/M4A scenarios and Silero environment consistency (`pip check`) were verified after packaging.

## 1.2.1 — 3 September 2026

- Fixed speech timing drift: overlapping timestamps and excessively short windows are detected before synthesis; WAV duration is checked against SRT.
- Milena uses pitch-preserving `atempo` for extra acceleration; simple resampling was removed.
- Strong acceleration is shown in the log, queue row, and final warning count.
- Siri text handoff checks two different texts before each file to avoid voicing a whole lecture from a stale phrase. The voice number is not represented as automatically detected.
- A process silent for 180 seconds is stopped; existing audio files are preserved.
- Separate app, bundle ID, and build 8. Added a shared “Open app.command” launcher.
- Documentation refreshed; old instructions marked as archived. The main branch moves to current code while preserving the old working bundle and previous ZIPs.
- 51 Ruby tests / 235 assertions and Swift tests passed. Verification of the installed copy is recorded separately in `docs/VERIFICATION.md`.

## 1.2.0 — 3 September 2026

- Separate “SRT Озвучка 1.2” app with its own settings; 1.1.0 is not replaced.
- Remembered destination choice: next to each SRT or Downloads.
- Add folders including subfolders; select final `.ru.srt` files and exclude intermediate parts, service folders, and duplicates.
- Name-conflict dialog offers copy, replace, skip, or stop queue. Check before synthesis and again before saving.
- Old audio remains intact until the new track is ready; a changed file requires renewed confirmation. The service engine also refuses to overwrite an existing result.
- Reports moved to Library/Logs/SRTVoiceover. On launch, only completed app-owned reports older than 72 hours are cleaned; deletion is non-recursive and does not follow links.
- Check destination access and free space before synthesis.
- Estimate remaining phrase time for the current file and show a system notification with the queue total.
- “Siri file” button points to the current version's working text. Apple Shortcuts must still be linked manually.
- AAC-LC/M4A by default, WAV optional; source timestamps and the selected blue icon retained.

Verified: 37 Ruby tests, 190 assertions, no failures or skips; Swift queue tests; six real-GUI scenarios and eight short Milena tracks; build, signature, and interface. Siri/Silero were not retested. The system notification banner requires user permission and was not separately confirmed. Details: `docs/VERIFICATION.md`.

## 1.1.0 — working version, frozen 3 September 2026

- AAC-LC in M4A by default; WAV remains available.
- Remembered format selection; AAC encoding runs once after the timeline is assembled.
- Duration and decode checks before publication.
- Overwrite protection in the GUI and main `.command` launcher.
- Queue, voice test, Siri/Milena/Silero, transparent blue icon.
- Source and documentation organized in a separate project folder.

Checks: 21 tests / 116 assertions, no failures or skips; Swift GUI compiles.

### Version organization — 3 September 2026

- Created local Git and committed the working source.
- Version pinned with tag `v1.1.0`.
- Created a checked ZIP with the ready-to-run app and source; SHA-256 saved.
- Added ongoing development rules and a changelog.
- No functional code or app changed at this checkpoint; version was not bumped artificially.
