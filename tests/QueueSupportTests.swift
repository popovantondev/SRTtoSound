import Foundation

@main
struct QueueSupportTests {
    static func main() throws {
        let defaultsName = "SRTtoSound.LocalizationTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: defaultsName)!
        precondition(AppLanguage.load(from: defaults) == nil)
        for language in AppLanguage.allCases {
            precondition(Localization.missingKeys(for: language).isEmpty)
            for key in AppText.allCases {
                precondition(!Localization.text(key, language: language).isEmpty, "Empty localization: \(language.rawValue)/\(key.rawValue)")
                let placeholderCount = Localization.text(key, language: language).components(separatedBy: "%@").count - 1
                let referenceCount = Localization.text(key, language: .english).components(separatedBy: "%@").count - 1
                precondition(placeholderCount == referenceCount, "Placeholder mismatch: \(language.rawValue)/\(key.rawValue)")
            }
            language.save(to: defaults)
            precondition(AppLanguage.load(from: defaults) == language)
        }
        precondition(Voice.all.map(\.speaker) == ["kseniya", "xenia", "baya", "aidar", "eugene"])
        precondition(Voice.all.allSatisfy { $0.engine == "silero" })
        for (index, voice) in Voice.all.enumerated() {
            precondition(Voice.index(forTag: voice.tag) == index, "Saved Silero voice changed: \(voice.tag)")
        }
        precondition(Voice.index(forTag: "legacy-siri") == 0)
        precondition(Localization.text(.startQueue, language: .english) == "Start queue")
        precondition(Localization.text(.removeSelected, language: .german).count > Localization.text(.removeSelected, language: .english).count)
        precondition(Localization.text(.notify, language: .german).count > 24)
        precondition(Localization.text(.openSelectedReport, language: .russian) == "Открыть отчёт")
        precondition(Localization.text(.openSelectedReport, language: .german) == "Bericht öffnen")
        precondition(Localization.text(.openSelectedReport, language: .english) == "Open report")
        precondition(Localization.format(.technicalDetails, language: .russian, "RAW ENGINE ERROR").contains("Технические подробности: RAW ENGINE ERROR"))
        precondition(Localization.format(.technicalDetails, language: .german, "RAW ENGINE ERROR").contains("Technische Details: RAW ENGINE ERROR"))
        precondition(Localization.format(.technicalDetails, language: .english, "RAW ENGINE ERROR").contains("Technical details: RAW ENGINE ERROR"))
        for language in AppLanguage.allCases {
            precondition(Localization.text(.preflightFailed, language: language).count <= 31,
                "Queue failure status should remain scannable: \(language.rawValue)")
        }
        for language in AppLanguage.allCases {
            precondition(!Localization.preflightIssueLabel("unsupported_symbol", language: language).contains("unsupported_symbol"))
            precondition(!Localization.preflightIssueLabel("speech_preparation_error", language: language).contains("speech_preparation_error"))
            precondition(!Localization.preflightIssueLabel("future_unknown_code", language: language).contains("future_unknown_code"))
            precondition(!Localization.preflightIssueAction("unsupported_symbol", language: language).isEmpty)
            precondition(!Localization.preflightIssueAction("speech_preparation_error", language: language).isEmpty)
            precondition(!Localization.preflightIssueAction("future_unknown_code", language: language).isEmpty)
        }
        precondition(Localization.preflightIssueLabel("unsupported_symbol", language: .russian).contains("символ"))
        precondition(Localization.preflightIssueLabel("unsupported_symbol", language: .german).contains("Schriftzeichen"))
        precondition(Localization.preflightIssueLabel("unsupported_symbol", language: .english).contains("character"))
        precondition(Localization.preflightIssueAction("unsupported_symbol", language: .russian).contains("Замените"))
        precondition(Localization.preflightIssueAction("unsupported_symbol", language: .german).contains("Ersetzen"))
        precondition(Localization.preflightIssueAction("unsupported_symbol", language: .english).contains("Replace"))
        let reportsDirectory = URL(fileURLWithPath: "/tmp/reports", isDirectory: true)
        let selectedReport = URL(fileURLWithPath: "/tmp/reports/file-1.txt")
        precondition(QueueReportNavigation.target(selectedReport: selectedReport, reportsDirectory: reportsDirectory,
            exists: { $0 == selectedReport || $0 == reportsDirectory }) == .report(selectedReport))
        precondition(QueueReportNavigation.target(selectedReport: selectedReport, reportsDirectory: reportsDirectory,
            exists: { $0 == reportsDirectory }) == .directory(reportsDirectory))
        precondition(QueueReportNavigation.target(selectedReport: nil, reportsDirectory: reportsDirectory,
            exists: { _ in false }) == .unavailable)
        precondition(Localization.format(.queueCompleteNoFiles, language: .german, "2", "/tmp/reports").contains("/tmp/reports"))
        precondition(Localization.format(.conflictMessage, language: .english, "/tmp/audio.m4a").contains("/tmp/audio.m4a"))
        let jobID = UUID()
        let validEvent = try JSONSerialization.data(withJSONObject: [
            "protocol_version": 1, "job_id": jobID.uuidString, "type": "progress"
        ])
        precondition(WorkerEventProtocol.decode(validEvent, expectedJobID: jobID)?["type"] as? String == "progress")
        precondition(WorkerEventProtocol.decode(validEvent, expectedJobID: UUID()) == nil)
        let wrongVersion = try JSONSerialization.data(withJSONObject: [
            "protocol_version": 2, "job_id": jobID.uuidString, "type": "progress"
        ])
        precondition(WorkerEventProtocol.decode(wrongVersion, expectedJobID: jobID) == nil)
        precondition(WorkerEventProtocol.decode(Data("not-json".utf8), expectedJobID: jobID) == nil)
        for appearance in AppAppearance.allCases {
            appearance.save(to: defaults)
            precondition(AppAppearance.load(from: defaults) == appearance)
        }
        precondition(AppAppearance.load(from: UserDefaults(suiteName: defaultsName + ".empty")!) == .system)
        let fakeExecutables: Set<String> = ["/fake/bin/ffmpeg", "/fake/data/.venv-silero-py312/bin/python"]
        let successfulProbe: DependencyReadiness.Probe = { path, arguments in
            if path.hasSuffix("ffmpeg") {
                if arguments.contains("-version") { return (0, "ffmpeg version 7.1") }
                if arguments.contains("-filters") { return (0, " ... atempo ...") }
                if arguments.contains("-encoders") { return (0, " A.... aac AAC") }
            }
            if path.hasSuffix("/bin/python") { return (0, "3.12|arm64\n") }
            return (1, "unexpected probe")
        }
        let allReady = DependencyReadiness.inspect(
            directoryHasModel: { $0 == "/fake/data/models/v5_5_ru.pt" },
            executable: { fakeExecutables.contains($0) },
            searchPaths: ["/fake/bin"],
            sileroPython: "/fake/data/.venv-silero-py312/bin/python",
            modelDirectories: ["/fake/data/models/v5_5_ru.pt"], probe: successfulProbe)
        precondition(allReady.map(\.state) == [.verified, .verified, .found])
        precondition(allReady[0].detail.contains("/fake/bin/ffmpeg"))
        let incompatible = DependencyReadiness.inspect(
            directoryHasModel: { _ in true }, executable: { fakeExecutables.contains($0) },
            searchPaths: ["/fake/bin"], sileroPython: "/fake/data/.venv-silero-py312/bin/python",
            modelDirectories: ["/fake/data/models/v5_5_ru.pt"], probe: { path, arguments in
                if path.hasSuffix("ffmpeg") { return arguments.contains("-version") ? (1, "broken FFmpeg") : (0, "") }
                return (0, "3.9|x86_64\n")
            })
        precondition(incompatible.map(\.state) == [.error, .error, .found])
        let allMissing = DependencyReadiness.inspect(
            directoryHasModel: { _ in false }, executable: { _ in false },
            searchPaths: ["/empty/bin"],
            sileroPython: "/empty/.venv-silero-py312/bin/python", modelDirectories: ["/empty/models/v5_5_ru.pt"])
        precondition(allMissing.count == 3 && allMissing.allSatisfy { $0.state == .missing && !$0.detail.isEmpty })
        precondition(allMissing[0].detail.contains("ffmpeg"))
        precondition(allMissing[1].detail == "/empty/.venv-silero-py312/bin/python")
        precondition(allMissing[2].detail == "/empty/models/v5_5_ru.pt")
        precondition(Localization.text(.readinessFound, language: .russian).contains("не полностью проверено"))
        if ProcessInfo.processInfo.environment["SRT_TO_SOUND_TEST_REAL_READINESS"] == "1" {
            let realFFmpeg = ProcessInfo.processInfo.environment["SRT_TO_SOUND_TEST_FFMPEG"]!
            let realPython = ProcessInfo.processInfo.environment["SRT_TO_SOUND_TEST_PYTHON"]!
            let realModel = ProcessInfo.processInfo.environment["SRT_TO_SOUND_TEST_MODEL"]!
            let real = DependencyReadiness.inspect(
                directoryHasModel: { path in
                    guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
                          (attributes[.type] as? FileAttributeType) == .typeRegular else { return false }
                    return ((attributes[.size] as? NSNumber)?.intValue ?? 0) > 0
                },
                executable: { FileManager.default.isExecutableFile(atPath: $0) },
                searchPaths: [URL(fileURLWithPath: realFFmpeg).deletingLastPathComponent().path],
                sileroPython: realPython,
                modelDirectories: [realModel])
            precondition(real.map(\.state) == [.verified, .verified, .found], "Real readiness probe failed: \(real.map(\.detail))")
            print("REAL_DEPENDENCY_READINESS_OK · FFmpeg capabilities, Python 3.12 arm64, local model file")
        }
        defaults.removePersistentDomain(forName: defaultsName)
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("srt-queue-tests-" + UUID().uuidString)
        try manager.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: root) }
        for name in ["01.ru.srt", "10.ru.srt", "02.RU.SRT", "01.srt", "01.part-02.ru.srt", "01.chunk03.ru.srt", "audio.m4a", ".hidden.ru.srt"] {
            try Data().write(to: root.appendingPathComponent(name))
        }
        let nested = root.appendingPathComponent("Day 2")
        let service = root.appendingPathComponent("translation-work")
        for folder in [nested, service] { try manager.createDirectory(at: folder, withIntermediateDirectories: false) }
        try Data().write(to: nested.appendingPathComponent("03.ru.srt"))
        try Data().write(to: service.appendingPathComponent("04.ru.srt"))
        try manager.createSymbolicLink(at: root.appendingPathComponent("loop"), withDestinationURL: root)
        let selection = VoiceoverFiles.collect([root, root.appendingPathComponent("01.ru.srt"), nested])
        precondition(selection.errors.isEmpty)
        precondition(selection.files.map(\.lastPathComponent) == ["01.ru.srt", "02.RU.SRT", "10.ru.srt", "03.ru.srt"])
        precondition(!VoiceoverFiles.isFinalRussian(URL(fileURLWithPath: "/01.part-01.ru.srt")))
        precondition(!VoiceoverFiles.isFinalRussian(URL(fileURLWithPath: "/Часть 2.ru.srt")))
        precondition(VoiceoverFiles.isFinalRussian(URL(fileURLWithPath: "/Отдел 2.ru.srt")))
        let first = root.appendingPathComponent("01.ru.srt")
        let second = nested.appendingPathComponent("03.ru.srt")
        let downloads = root.appendingPathComponent("Downloads")
        for input in [first, second] {
            let beside = VoiceoverFiles.output(for: input, format: "m4a", downloads: nil)
            precondition(beside.deletingLastPathComponent() == input.deletingLastPathComponent())
            precondition(beside.lastPathComponent == input.deletingPathExtension().lastPathComponent + ".m4a")
            let moved = VoiceoverFiles.output(for: input, format: "wav", downloads: downloads)
            precondition(moved.deletingLastPathComponent().path == downloads.path)
            precondition(moved.lastPathComponent == input.deletingPathExtension().lastPathComponent + ".wav")
            let unnamed = URL(fileURLWithPath: "/tmp/lecture.srt")
            precondition(VoiceoverFiles.output(for: unnamed, format: "m4a", downloads: nil).lastPathComponent == "lecture.ru.m4a")
        }
        precondition(VoiceoverFiles.remaining(65).contains("2 мин"))
        precondition(VoiceoverFiles.remaining(3601).contains("1 ч 1 мин"))
        precondition(VoiceoverFiles.remaining(.nan).contains("Оцениваю"))
        precondition(VoiceoverFiles.remaining(65, language: .german).contains("2 Min."))
        precondition(VoiceoverFiles.remaining(3601, language: .english).contains("1 hr 1 min"))
        precondition(!VoiceoverFiles.remaining(65, language: .english).contains("мин"))
        precondition(VoiceoverFiles.collect([root.appendingPathComponent("missing")]).errors.count == 1)
        let bundle = URL(fileURLWithPath: "/Applications/SRT to Sound.app", isDirectory: true)
        let resources = bundle.appendingPathComponent("Contents/Resources", isDirectory: true)
        precondition(VoiceoverInstallation.runtimeDirectory(programOverride: nil,
            resourceDirectory: resources, bundleURL: bundle).path == resources.appendingPathComponent("Runtime").path)
        precondition(VoiceoverInstallation.runtimeDirectory(programOverride: "/tmp/runtime",
            resourceDirectory: resources, bundleURL: bundle).path == "/tmp/runtime")
        precondition(VoiceoverInstallation.supportDirectory(dataOverride: nil,
            homeDirectory: "/Users/example").path == "/Users/example/Library/Application Support/SRTtoSound")
        precondition(VoiceoverInstallation.supportDirectory(dataOverride: "/tmp/data",
            homeDirectory: "/Users/example").path == "/tmp/data")
        print("QUEUE_SUPPORT_TESTS OK · folder filtering, deduplication, paths, ETA, standalone app paths")
    }
}
