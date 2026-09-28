import Foundation

struct Voice {
    let title: String
    let engine: String
    let speaker: String
    let tag: String
    static let all: [Voice] = [
        Voice(title: "Silero · Kseniya", engine: "silero", speaker: "kseniya", tag: "silero-kseniya"),
        Voice(title: "Silero · Xenia", engine: "silero", speaker: "xenia", tag: "silero-xenia"),
        Voice(title: "Silero · Baya", engine: "silero", speaker: "baya", tag: "silero-baya"),
        Voice(title: "Silero · Aidar", engine: "silero", speaker: "aidar", tag: "silero-aidar"),
        Voice(title: "Silero · Eugene", engine: "silero", speaker: "eugene", tag: "silero-eugene")
    ]
    static func index(forTag tag: String?) -> Int {
        guard let tag, let index = all.firstIndex(where: { $0.tag == tag }) else { return 0 }
        return index
    }
}

enum ReportOpenTarget: Equatable {
    case report(URL)
    case directory(URL)
    case unavailable
}

enum QueueReportNavigation {
    static func target(selectedReport: URL?, reportsDirectory: URL,
                       exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> ReportOpenTarget {
        if let selectedReport, exists(selectedReport) { return .report(selectedReport) }
        if exists(reportsDirectory) { return .directory(reportsDirectory) }
        return .unavailable
    }
}

enum AppLanguage: String, CaseIterable {
    case russian = "ru", german = "de", english = "en"
    var displayName: String { switch self { case .russian: "Русский"; case .german: "Deutsch"; case .english: "English" } }
    static let preferenceKey = "interfaceLanguage"
    static func load(from defaults: UserDefaults = .standard) -> AppLanguage? {
        guard let value = defaults.string(forKey: preferenceKey) else { return nil }
        return AppLanguage(rawValue: value)
    }
    func save(to defaults: UserDefaults = .standard) { defaults.set(rawValue, forKey: Self.preferenceKey) }
}

enum AppAppearance: String, CaseIterable {
    case system, light, dark
    static let preferenceKey = "interfaceAppearance"
    static func load(from defaults: UserDefaults = .standard) -> AppAppearance {
        defaults.string(forKey: preferenceKey).flatMap(AppAppearance.init(rawValue:)) ?? .system
    }
    func save(to defaults: UserDefaults = .standard) { defaults.set(rawValue, forKey: Self.preferenceKey) }
}

enum AppText: String, CaseIterable {
    case firstRunTitle, firstRunMessage, appMenu, quit, appearance, language, systemTheme, lightTheme, darkTheme
    case windowTitle, heading, subtitle, addFiles, addFolder, removeSelected, clearList
    case fileColumn, stateColumn, voice, previewVoice, format, rhythm, saveTo
    case besideSRT, downloads, notify, help, startQueue, stop, showResult, reports, openSelectedReport
    case chooseFilesTitle, chooseFilesMessage, chooseFolderTitle, chooseFolderMessage
    case errorTitle, errorMessage, exitTitle, exitMessage, continueWork, stopAndQuit
    case voiceSilero, voiceSileroHint
    case formatAAC, formatWAV, rhythmSmooth, rhythmStrict, idleStatus, queuedCount, emptySelection
    case wrongSubtitleWarning, clearStatus, reportsNotReady, reportsCleanupError, activityReason
    case preflightStatus, queueStatus, progressSynthesis, progressAssembly, progressEncode, progressVerify, progressSpeech
    case resultDone, resultSkipped, resultStopped, resultFailed, resultSaved, resultQueueSummary, resultWarnings
    case testPlaying, testPlayingWarnings, testPlaybackFailed, testCreateFailed, conflictTitle, conflictMessage
    case conflictCopy, conflictReplace, conflictSkip, conflictStop, conflictWait, conflictContinue
    case notificationDenied, notificationError, notificationTitle, stopStatus, stopEta, errorStatus
    case editMenu, copy, paste, cut, selectAll, queued, preparing, preflightFailed, preflightMissing
    case queueCompleteNoFiles, fileProgress, testVoiceProgress, etaInitial, etaSynthesis, etaAssembly, etaFile, preflightWholeFailed, resultSummary
    case preflightChoiceTitle, preflightChoiceMessage, preflightRunReady, preflightReview
    case readinessFFmpeg, readinessPython, readinessModel, readinessFound, readinessMissing
    case readinessVerified, readinessError
    case readinessNote, readinessNoFFmpeg, readinessNoPython, readinessNoModel
    case sampleOriginal, samplePrepared, sampleWarnings, sampleNoWarnings
    case statusPreparingVoice, statusLoadingModel, statusSynthesisStarted, statusSavingAAC
    case statusAACFallback, statusVerifyingAAC, statusSynthesisProgress
    case warningTempoFit, warningSilentCues, technicalDetails, voiceoverFailure, unknownChildEvent
    case preflightIssue, preflightFixHint, preflightCancelledReport
    case preflightUnsupportedSymbol, preflightSpeechPreparation, preflightGenericIssue
    case preflightActionUnsupportedSymbol, preflightActionSpeechPreparation, preflightActionGeneric
    case supportDirectoryError, queuePreflightLog, queueStartedLog, cleanupDiagnostic
    case preflightPassedFile, savedOutput, savedOutputWithWarnings, fileNotReady, exitCode
    case resolveChoiceError, notificationDisplayError
    case jobStartedLog, formatWAVHint, unknownFileName, missingRuntimeError
    case etaEstimating, etaUnderMinute, etaMinutes, etaHoursMinutes
}

enum Localization {
    static let catalog: [AppLanguage: [AppText: String]] = [
        .russian: [
            .firstRunTitle:"Выберите язык интерфейса", .firstRunMessage:"Выбор можно изменить в настройках приложения.", .appMenu:"SRT to Sound", .quit:"Закрыть SRT to Sound", .appearance:"Оформление", .language:"Язык", .systemTheme:"Системная", .lightTheme:"Светлая", .darkTheme:"Тёмная", .windowTitle:"SRT to Sound 3.5", .heading:"Озвучка лекций", .subtitle:"Русские SRT → отдельные звуковые дорожки с исходными таймкодами", .addFiles:"Добавить SRT…", .addFolder:"Добавить папку…", .removeSelected:"Убрать выбранные", .clearList:"Очистить список", .fileColumn:"Файл · можно перетащить сюда несколько .ru.srt", .stateColumn:"Состояние", .voice:"Голос:", .previewVoice:"Прослушать голос", .format:"Формат:", .rhythm:"Ритм:", .saveTo:"Сохранять:", .besideSRT:"Рядом с каждым SRT", .downloads:"В Загрузки", .notify:"Уведомить о завершении", .help:"При совпадении имени выберите копию, замену или пропуск. Очередь обрабатывается по одному файлу.", .startQueue:"Начать очередь", .stop:"Остановить", .showResult:"Показать результат", .reports:"Отчёты", .openSelectedReport:"Открыть отчёт", .chooseFilesTitle:"Выберите русские субтитры", .chooseFilesMessage:"Можно выбрать несколько .ru.srt, удерживая ⌘, или диапазон с Shift.", .chooseFolderTitle:"Добавить папку лекций", .chooseFolderMessage:"Добавятся итоговые .ru.srt, включая вложенные папки. Немецкие SRT и промежуточные части будут пропущены.", .errorTitle:"Не удалось выполнить действие", .errorMessage:"Подробности в журнале.", .exitTitle:"Остановить озвучку и выйти?", .exitMessage:"Готовые дорожки останутся. Текущий файл потребуется озвучить заново.", .continueWork:"Продолжить работу", .stopAndQuit:"Остановить и выйти",
            .voiceSilero:"Silero · %@", .voiceSileroHint:"Silero работает локально: 3 CPU-процесса, без кэша готового голоса. Числа и латинские термины проверяются до модели.", .formatAAC:"AAC · для MP4 (.m4a)", .formatWAV:"WAV · без сжатия (.wav)", .rhythmSmooth:"Плавно · цельные предложения", .rhythmStrict:"Точно · исходные метки", .idleStatus:"Добавьте русские субтитры, чтобы начать.", .queuedCount:"В списке: %@. Выберите голос и начните очередь.", .emptySelection:"В выбранном месте не найдены подходящие SRT.", .wrongSubtitleWarning:"Внимание: есть имена без .ru.srt. Убедитесь, что выбраны русские, а не немецкие субтитры.", .clearStatus:"Список очищен. Файлы на диске не удалялись.", .reportsNotReady:"Отчёты появятся после первой готовой дорожки: %@", .reportsCleanupError:"Не удалось проверить старые отчёты: %@", .activityReason:"Озвучка субтитров", .preflightStatus:"Не удалось предварительно проверить очередь: %@", .queueStatus:"Очередь: %@ файлов. Голос: %@. Формат: %@. Ритм: %@.", .progressSynthesis:"Фразы Silero, процесс %@.", .progressAssembly:"Сборка плавной дорожки.", .progressEncode:"Фразы готовы. Сохраняю AAC…", .progressVerify:"Проверяю готовую дорожку…", .progressSpeech:"Фраза %@/%@", .resultDone:"Готово", .resultSkipped:"Пропущено · старый файл сохранён", .resultStopped:"Остановлено", .resultFailed:"Ошибка · см. журнал", .resultSaved:"Сохранено: %@", .resultQueueSummary:"Готово: %@. Пропущено: %@. Ошибок: %@.", .resultWarnings:" ⚠️ Предупреждений: %@ — см. журнал.", .testPlaying:"Тест воспроизводится. Выберите другой голос для сравнения.", .testPlayingWarnings:"Тест воспроизводится · ⚠️ проверьте предупреждения в журнале.", .testPlaybackFailed:"Тест сохранён, но не удалось воспроизвести: %@", .testCreateFailed:"Не удалось создать тест голоса. См. журнал.", .conflictTitle:"Аудиофайл уже существует", .conflictMessage:"%@\n\nКопия получит новое имя. При замене старый файл останется целым, пока новая дорожка не будет готова и проверена.", .conflictCopy:"Сохранить копию", .conflictReplace:"Заменить", .conflictSkip:"Пропустить", .conflictStop:"Остановить очередь", .conflictWait:"Жду ваш выбор. Существующий файл пока не изменён.", .conflictContinue:"Продолжаю…", .notificationDenied:"Уведомления не разрешены в macOS. Итог останется в окне программы.", .notificationError:"Уведомления: %@", .notificationTitle:"SRT to Sound · очередь завершена", .stopStatus:"Останавливаю текущую озвучку…", .stopEta:"Незавершённый файл при новом запуске начнётся заново.", .errorStatus:"Не удалось выполнить действие. Подробности в журнале.", .editMenu:"Правка", .copy:"Копировать", .paste:"Вставить", .cut:"Вырезать", .selectAll:"Выбрать всё", .queued:"В очереди", .preparing:"Подготовка…", .preflightFailed:"Ошибка предварительной проверки · отчёт сохранён", .preflightMissing:"Предварительная проверка не вернула отчёт: %@", .queueCompleteNoFiles:"Готово: 0. Пропущено: 0. Ошибок: %@. Отчёты сохранены в %@.", .fileProgress:"Файл %@ из %@: %@", .testVoiceProgress:"Проверяю голос: %@…", .etaInitial:"Оцениваю скорость этого файла после первых фраз…", .etaSynthesis:"Генерирую фразы Silero тремя процессами…", .etaAssembly:"Собираю плавную дорожку…", .etaFile:"Ожидаемое время для файла; затем сохранение и проверка.", .preflightWholeFailed:"Не удалось проверить всю очередь. См. журнал.", .resultSummary:"Готово: %@. Пропущено: %@. Ошибок: %@.",
        ],
        .german: [
            .firstRunTitle:"Sprache der Oberfläche wählen", .firstRunMessage:"Sie können diese Auswahl später in den Einstellungen ändern.", .appMenu:"SRT to Sound", .quit:"SRT to Sound beenden", .appearance:"Darstellung", .language:"Sprache", .systemTheme:"System", .lightTheme:"Hell", .darkTheme:"Dunkel", .windowTitle:"SRT to Sound 3.5", .heading:"Vorlesungen vertonen", .subtitle:"Russische SRT → separate Audiospuren mit ursprünglichen Zeitstempeln", .addFiles:"SRT hinzufügen…", .addFolder:"Ordner hinzufügen…", .removeSelected:"Auswahl entfernen", .clearList:"Liste leeren", .fileColumn:"Datei · mehrere .ru.srt hierher ziehen", .stateColumn:"Status", .voice:"Stimme:", .previewVoice:"Stimme anhören", .format:"Format:", .rhythm:"Sprechfluss:", .saveTo:"Speichern:", .besideSRT:"Neben jeder SRT", .downloads:"In Downloads", .notify:"Bei Abschluss benachrichtigen", .help:"Bei gleichem Namen können Sie eine Kopie speichern, ersetzen oder überspringen. Die Warteschlange verarbeitet eine Datei nach der anderen.", .startQueue:"Warteschlange starten", .stop:"Anhalten", .showResult:"Ergebnis anzeigen", .reports:"Berichte", .openSelectedReport:"Bericht öffnen", .chooseFilesTitle:"Russische Untertitel auswählen", .chooseFilesMessage:"Mit ⌘ mehrere .ru.srt oder mit Shift einen Bereich auswählen.", .chooseFolderTitle:"Vorlesungsordner hinzufügen", .chooseFolderMessage:"Endgültige .ru.srt-Dateien einschließlich Unterordnern werden hinzugefügt. Deutsche SRT und Zwischenteile werden übersprungen.", .errorTitle:"Aktion fehlgeschlagen", .errorMessage:"Weitere Details stehen im Protokoll.", .exitTitle:"Vertonung anhalten und beenden?", .exitMessage:"Fertige Audiospuren bleiben erhalten. Die aktuelle Datei muss erneut vertont werden.", .continueWork:"Weiterarbeiten", .stopAndQuit:"Anhalten und beenden",
            .voiceSilero:"Silero · %@", .voiceSileroHint:"Silero arbeitet lokal: 3 CPU-Prozesse, kein Cache für fertige Stimmen. Zahlen und lateinische Begriffe werden vor dem Modell geprüft.", .formatAAC:"AAC · für MP4 (.m4a)", .formatWAV:"WAV · unkomprimiert (.wav)", .rhythmSmooth:"Flüssig · ganze Sätze", .rhythmStrict:"Genau · Originalmarken", .idleStatus:"Fügen Sie russische Untertitel hinzu, um zu beginnen.", .queuedCount:"In der Liste: %@. Wählen Sie eine Stimme und starten Sie die Warteschlange.", .emptySelection:"Am ausgewählten Ort wurden keine passenden SRT-Dateien gefunden.", .wrongSubtitleWarning:"Achtung: Einige Namen enden nicht auf .ru.srt. Prüfen Sie, ob russische statt deutscher Untertitel ausgewählt sind.", .clearStatus:"Liste geleert. Dateien auf dem Datenträger wurden nicht gelöscht.", .reportsNotReady:"Berichte erscheinen nach der ersten fertigen Audiospur: %@", .reportsCleanupError:"Alte Berichte konnten nicht geprüft werden: %@", .activityReason:"Untertitel vertonen", .preflightStatus:"Warteschlangenprüfung fehlgeschlagen: %@", .queueStatus:"Warteschlange: %@ Dateien. Stimme: %@. Format: %@. Sprechfluss: %@.", .progressSynthesis:"Silero-Sätze, Prozess %@.", .progressAssembly:"Flüssige Audiospur wird zusammengestellt.", .progressEncode:"Sätze fertig. AAC wird gespeichert…", .progressVerify:"Fertige Audiospur wird geprüft…", .progressSpeech:"Satz %@/%@", .resultDone:"Fertig", .resultSkipped:"Übersprungen · alte Datei erhalten", .resultStopped:"Angehalten", .resultFailed:"Fehler · siehe Protokoll", .resultSaved:"Gespeichert: %@", .resultQueueSummary:"Fertig: %@. Übersprungen: %@. Fehler: %@.", .resultWarnings:" ⚠️ Warnungen: %@ — siehe Protokoll.", .testPlaying:"Test wird abgespielt. Wählen Sie zum Vergleichen eine andere Stimme.", .testPlayingWarnings:"Test läuft · ⚠️ Warnungen stehen im Protokoll.", .testPlaybackFailed:"Test gespeichert, konnte aber nicht abgespielt werden: %@", .testCreateFailed:"Stimmtest konnte nicht erstellt werden. Siehe Protokoll.", .conflictTitle:"Audiodatei ist bereits vorhanden", .conflictMessage:"%@\n\nEine Kopie erhält einen neuen Namen. Beim Ersetzen bleibt die alte Datei erhalten, bis die neue Audiospur fertig und geprüft ist.", .conflictCopy:"Kopie speichern", .conflictReplace:"Ersetzen", .conflictSkip:"Überspringen", .conflictStop:"Warteschlange anhalten", .conflictWait:"Ihre Auswahl wird erwartet. Die vorhandene Datei ist noch unverändert.", .conflictContinue:"Wird fortgesetzt…", .notificationDenied:"Mitteilungen sind in macOS nicht erlaubt. Das Ergebnis bleibt im Programmfenster sichtbar.", .notificationError:"Mitteilungen: %@", .notificationTitle:"SRT to Sound · Warteschlange abgeschlossen", .stopStatus:"Aktuelle Vertonung wird angehalten…", .stopEta:"Die nicht fertige Datei beginnt beim nächsten Start von vorn.", .errorStatus:"Aktion fehlgeschlagen. Weitere Details stehen im Protokoll.", .editMenu:"Bearbeiten", .copy:"Kopieren", .paste:"Einsetzen", .cut:"Ausschneiden", .selectAll:"Alles auswählen", .queued:"In der Warteschlange", .preparing:"Vorbereitung…", .preflightFailed:"Prüfung fehlgeschlagen · Bericht gespeichert", .preflightMissing:"Die Vorabprüfung lieferte keinen Bericht: %@", .queueCompleteNoFiles:"Fertig: 0. Übersprungen: 0. Fehler: %@. Berichte gespeichert in %@.", .fileProgress:"Datei %@ von %@: %@", .testVoiceProgress:"Stimme wird geprüft: %@…", .etaInitial:"Geschwindigkeit wird nach den ersten Sätzen geschätzt…", .etaSynthesis:"Silero-Sätze werden mit drei Prozessen erzeugt…", .etaAssembly:"Flüssige Audiospur wird zusammengestellt…", .etaFile:"Geschätzte Zeit für diese Datei; danach Speicherung und Prüfung.", .preflightWholeFailed:"Die gesamte Warteschlange konnte nicht geprüft werden. Siehe Protokoll.", .resultSummary:"Fertig: %@. Übersprungen: %@. Fehler: %@.",
        ],
        .english: [
            .firstRunTitle:"Choose interface language", .firstRunMessage:"You can change this choice later in the app settings.", .appMenu:"SRT to Sound", .quit:"Quit SRT to Sound", .appearance:"Appearance", .language:"Language", .systemTheme:"System", .lightTheme:"Light", .darkTheme:"Dark", .windowTitle:"SRT to Sound 3.5", .heading:"Voiceover for lectures", .subtitle:"Russian SRT → separate audio tracks with original timestamps", .addFiles:"Add SRT…", .addFolder:"Add folder…", .removeSelected:"Remove selected", .clearList:"Clear list", .fileColumn:"File · drag multiple .ru.srt files here", .stateColumn:"Status", .voice:"Voice:", .previewVoice:"Preview voice", .format:"Format:", .rhythm:"Pacing:", .saveTo:"Save:", .besideSRT:"Next to each SRT", .downloads:"In Downloads", .notify:"Notify when finished", .help:"If a name already exists, choose copy, replace, or skip. The queue processes one file at a time.", .startQueue:"Start queue", .stop:"Stop", .showResult:"Show result", .reports:"Reports", .openSelectedReport:"Open report", .chooseFilesTitle:"Choose Russian subtitles", .chooseFilesMessage:"Choose multiple .ru.srt files with ⌘, or a range with Shift.", .chooseFolderTitle:"Add lecture folders", .chooseFolderMessage:"Final .ru.srt files, including nested folders, will be added. German SRT files and intermediate parts are skipped.", .errorTitle:"The action could not be completed", .errorMessage:"See the log for details.", .exitTitle:"Stop voiceover and quit?", .exitMessage:"Completed tracks will remain. The current file will need to be processed again.", .continueWork:"Continue working", .stopAndQuit:"Stop and quit",
            .voiceSilero:"Silero · %@", .voiceSileroHint:"Silero runs locally: 3 CPU processes, with no cache of finished voice clips. Numbers and Latin terms are checked before synthesis.", .formatAAC:"AAC · for MP4 (.m4a)", .formatWAV:"WAV · uncompressed (.wav)", .rhythmSmooth:"Smooth · complete sentences", .rhythmStrict:"Exact · original timestamps", .idleStatus:"Add Russian subtitles to get started.", .queuedCount:"In list: %@. Choose a voice and start the queue.", .emptySelection:"No matching SRT files were found at the selected location.", .wrongSubtitleWarning:"Warning: some names do not end in .ru.srt. Check that you selected Russian, not German subtitles.", .clearStatus:"List cleared. Files on disk were not deleted.", .reportsNotReady:"Reports will appear after the first completed track: %@", .reportsCleanupError:"Could not check old reports: %@", .activityReason:"Processing subtitles", .preflightStatus:"Could not check the queue before starting: %@", .queueStatus:"Queue: %@ files. Voice: %@. Format: %@. Pacing: %@.", .progressSynthesis:"Silero phrases, process %@.", .progressAssembly:"Assembling smooth audio track.", .progressEncode:"Phrases ready. Saving AAC…", .progressVerify:"Checking completed audio track…", .progressSpeech:"Cue %@/%@", .resultDone:"Done", .resultSkipped:"Skipped · previous file kept", .resultStopped:"Stopped", .resultFailed:"Error · see log", .resultSaved:"Saved: %@", .resultQueueSummary:"Done: %@. Skipped: %@. Errors: %@.", .resultWarnings:" ⚠️ Warnings: %@ — see log.", .testPlaying:"Playing test. Choose another voice to compare.", .testPlayingWarnings:"Playing test · ⚠️ check warnings in the log.", .testPlaybackFailed:"Test saved, but could not be played: %@", .testCreateFailed:"Could not create voice test. See log.", .conflictTitle:"Audio file already exists", .conflictMessage:"%@\n\nThe copy gets a new name. When replacing, the old file stays intact until the new track is ready and verified.", .conflictCopy:"Save a copy", .conflictReplace:"Replace", .conflictSkip:"Skip", .conflictStop:"Stop queue", .conflictWait:"Waiting for your choice. The existing file is unchanged.", .conflictContinue:"Continuing…", .notificationDenied:"Notifications are not allowed in macOS. The result will remain in the app window.", .notificationError:"Notifications: %@", .notificationTitle:"SRT to Sound · queue completed", .stopStatus:"Stopping current voiceover…", .stopEta:"The unfinished file will start over the next time you run it.", .errorStatus:"The action could not be completed. See the log for details.", .editMenu:"Edit", .copy:"Copy", .paste:"Paste", .cut:"Cut", .selectAll:"Select All", .queued:"Queued", .preparing:"Preparing…", .preflightFailed:"Preflight failed · report saved", .preflightMissing:"Preflight returned no report: %@", .queueCompleteNoFiles:"Done: 0. Skipped: 0. Errors: %@. Reports saved to %@.", .fileProgress:"File %@ of %@: %@", .testVoiceProgress:"Testing voice: %@…", .etaInitial:"Estimating speed after the first few phrases…", .etaSynthesis:"Generating Silero phrases with three processes…", .etaAssembly:"Assembling smooth audio track…", .etaFile:"Estimated time for this file, then saving and verification.", .preflightWholeFailed:"Could not check the entire queue. See log.", .resultSummary:"Done: %@. Skipped: %@. Errors: %@.",
        ]
    ]
    static let additionalCatalog: [AppLanguage: [AppText: String]] = [
        .russian: [
            .preflightFailed: "Ошибка проверки · есть отчёт",
            .preflightChoiceTitle: "В очереди есть файлы с проблемами",
            .preflightChoiceMessage: "Не удалось проверить %1$@ файлов. Продолжить только с %2$@ готовыми файлами?",
            .preflightRunReady: "Озвучить готовые", .preflightReview: "Вернуться к исправлению",
            .readinessFFmpeg: "FFmpeg", .readinessPython: "Среда Python для Silero", .readinessModel: "Модель Silero v5.5",
            .readinessFound: "найдено · не полностью проверено", .readinessMissing: "не найдено",
            .readinessVerified: "проверено", .readinessError: "найдено · проверка не пройдена",
            .readinessNote: "FFmpeg и версию Python проверяем запуском. Модель проверяется на наличие; загрузка и установка не выполняются. Чтобы проверить загрузку модели и речь, нажмите «Прослушать голос».",
            .readinessNoFFmpeg: "FFmpeg не найден. Он нужен для AAC и подгонки ритма. Установите его по инструкции. Проверенные расположения: %@",
            .readinessNoPython: "Отдельная среда Python не найдена. Программа не создаёт и не изменяет её автоматически. Выполните установку Silero по инструкции. Ожидаемый путь: %@",
            .readinessNoModel: "Локальная модель v5_5_ru.pt отсутствует или пуста. Программа не скачивает модель автоматически. Ожидаемый путь: %@",
            .sampleOriginal: "Исходный текст:\n%@\n\nТекст, который получит Silero:\n%@",
            .samplePrepared: "Текст для Silero:\n%@",
            .sampleWarnings: "\n\nПроверка произношения:\n%@",
            .sampleNoWarnings: "\n\nДополнительных предупреждений о произношении нет.",
            .statusPreparingVoice: "Подготавливаю озвучку…",
            .statusLoadingModel: "Загружаю локальную модель Silero…",
            .statusSynthesisStarted: "Текст подготовлен: %@ реплик, %@ речевых фраз.",
            .statusSavingAAC: "Сохраняю AAC для MP4…",
            .statusAACFallback: "Аппаратный AAC недоступен. Сохраняю обычным FFmpeg AAC…",
            .statusVerifyingAAC: "Проверяю готовую дорожку…",
            .statusSynthesisProgress: "Фразы Silero: %@ из %@",
            .warningTempoFit: "Фрагмент реплик %@–%@ ускорен до ×%@; слова сохранены, паузы сокращены.",
            .warningSilentCues: "В репликах %@ не было слов; временные метки дорожки сохранены.",
            .technicalDetails: "Технические подробности: %@",
            .voiceoverFailure: "Не удалось создать дорожку. Исходный результат не заменён.",
            .unknownChildEvent: "Получено неизвестное событие от рабочего процесса.",
            .preflightIssue: "❌ %@ · реплики %@ · %@ · проблема %@%@",
            .preflightFixHint: "Исправьте указанный текст или таймкоды, затем проверьте очередь снова.",
            .preflightUnsupportedSymbol: "неподдерживаемый или смешанный символ",
            .preflightSpeechPreparation: "не удалось подготовить текст для озвучки",
            .preflightGenericIssue: "не удалось проверить текст субтитров",
            .preflightActionUnsupportedSymbol: "Замените неподдерживаемый знак словами или стандартной пунктуацией.",
            .preflightActionSpeechPreparation: "Исправьте текст этой фразы или добавьте точное произношение в словарь.",
            .preflightActionGeneric: "Проверьте целостность SRT и временные метки.",
            .preflightCancelledReport: "Отменено до синтеза: %@ · отчёт %@",
            .supportDirectoryError: "Не удалось подготовить рабочую папку: %@",
            .queuePreflightLog: "Проверяю всю очередь до загрузки модели Silero…",
            .queueStartedLog: "Очередь запущена: %@ файлов · голос %@ · формат %@ · ритм %@.",
            .cleanupDiagnostic: "Диагностика очистки отчётов: %@",
            .preflightPassedFile: "Проверено до загрузки голоса: %@",
            .savedOutput: "Сохранено: %@",
            .savedOutputWithWarnings: "Готово · предупреждений: %@",
            .fileNotReady: "Файл не готов: %@. Перехожу к следующему.",
            .exitCode: "код завершения %@",
            .resolveChoiceError: "Не удалось передать выбранное действие: %@",
            .notificationDisplayError: "Не удалось показать уведомление: %@",
            .jobStartedLog: "Озвучиваю файл: %@",
            .formatWAVHint: "PCM · 16 бит · 24 кГц · моно",
            .unknownFileName: "неизвестный файл",
            .missingRuntimeError: "Установка повреждена: в приложении отсутствует компонент озвучки.",
            .etaEstimating: "Оцениваю скорость…",
            .etaUnderMinute: "Меньше минуты на оставшиеся фразы",
            .etaMinutes: "Оставшиеся фразы: ≈ %@ мин",
            .etaHoursMinutes: "Оставшиеся фразы: ≈ %@ ч %@ мин"
        ],
        .german: [
            .preflightFailed: "Prüffehler · Bericht vorhanden",
            .preflightChoiceTitle: "Probleme in der Warteschlange",
            .preflightChoiceMessage: "%1$@ Dateien konnten nicht geprüft werden. Nur die %2$@ geprüften Dateien verarbeiten?",
            .preflightRunReady: "Geprüfte Dateien vertonen", .preflightReview: "Zurück zum Korrigieren",
            .readinessFFmpeg: "FFmpeg", .readinessPython: "Silero-Python-Umgebung", .readinessModel: "Silero-Modell v5.5",
            .readinessFound: "gefunden · nicht vollständig geprüft", .readinessMissing: "fehlt",
            .readinessVerified: "geprüft", .readinessError: "gefunden · Prüfung fehlgeschlagen",
            .readinessNote: "FFmpeg und die Python-Version werden tatsächlich gestartet und geprüft. Beim Modell wird nur die Datei geprüft; es wird nichts installiert oder heruntergeladen. Zum Test des Modellladens „Stimme anhören“ wählen.",
            .readinessNoFFmpeg: "FFmpeg wurde nicht gefunden. Es wird für AAC und die Zeitanpassung benötigt. Installieren Sie es gemäß Anleitung. Durchsuchte Pfade: %@",
            .readinessNoPython: "Die separate Python-Umgebung fehlt. Die App erstellt oder ändert sie nicht automatisch. Folgen Sie der Silero-Installationsanleitung. Erwarteter Pfad: %@",
            .readinessNoModel: "Das lokale Modell v5_5_ru.pt fehlt oder ist leer. Das Modell wird nie automatisch heruntergeladen. Erwarteter Pfad: %@",
            .sampleOriginal: "Ausgangstext:\n%@\n\nText für Silero:\n%@",
            .samplePrepared: "Text für Silero:\n%@",
            .sampleWarnings: "\n\nAussprachehinweise:\n%@",
            .sampleNoWarnings: "\n\nKeine zusätzlichen Aussprachehinweise.",
            .statusPreparingVoice: "Sprachausgabe wird vorbereitet…",
            .statusLoadingModel: "Lokales Silero-Modell wird geladen…",
            .statusSynthesisStarted: "Text vorbereitet: %@ Untertitel, %@ Sprachabschnitte.",
            .statusSavingAAC: "AAC für MP4 wird gespeichert…",
            .statusAACFallback: "Apple-AAC ist nicht verfügbar. FFmpeg-AAC wird verwendet…",
            .statusVerifyingAAC: "Fertige Audiospur wird geprüft…",
            .statusSynthesisProgress: "Silero-Abschnitte: %@ von %@",
            .warningTempoFit: "Untertitel %@–%@ wurden auf ×%@ beschleunigt; Wörter bleiben erhalten, Pausen werden gekürzt.",
            .warningSilentCues: "Untertitel %@ enthielten keine Wörter; die Zeitachse der Spur bleibt erhalten.",
            .technicalDetails: "Technische Details: %@",
            .voiceoverFailure: "Audiospur konnte nicht erstellt werden. Das vorhandene Ergebnis bleibt erhalten.",
            .unknownChildEvent: "Unbekanntes Ereignis vom Arbeitsprozess erhalten.",
            .preflightIssue: "❌ %@ · Untertitel %@ · %@ · Problem %@%@",
            .preflightFixHint: "Korrigieren Sie den Text oder die Zeitstempel und prüfen Sie die Warteschlange erneut.",
            .preflightUnsupportedSymbol: "nicht unterstütztes oder gemischtes Schriftzeichen",
            .preflightSpeechPreparation: "Sprechtext konnte nicht vorbereitet werden",
            .preflightGenericIssue: "Untertiteltext konnte nicht geprüft werden",
            .preflightActionUnsupportedSymbol: "Ersetzen Sie das nicht unterstützte Zeichen durch Wörter oder übliche Satzzeichen.",
            .preflightActionSpeechPreparation: "Korrigieren Sie den Satz oder ergänzen Sie eine eindeutige Aussprache im Wörterbuch.",
            .preflightActionGeneric: "Prüfen Sie die SRT-Datei und ihre Zeitstempel.",
            .preflightCancelledReport: "Vor der Synthese abgebrochen: %@ · Bericht %@",
            .supportDirectoryError: "Arbeitsordner konnte nicht vorbereitet werden: %@",
            .queuePreflightLog: "Die gesamte Warteschlange wird vor dem Laden des Silero-Modells geprüft…",
            .queueStartedLog: "Warteschlange gestartet: %@ Dateien · Stimme %@ · Format %@ · Sprechfluss %@.",
            .cleanupDiagnostic: "Diagnose der Berichtsbereinigung: %@",
            .preflightPassedFile: "Vor dem Laden der Stimme geprüft: %@",
            .savedOutput: "Gespeichert: %@",
            .savedOutputWithWarnings: "Fertig · Warnungen: %@",
            .fileNotReady: "Datei nicht fertig: %@. Die nächste Datei wird verarbeitet.",
            .exitCode: "Beendigungscode %@",
            .resolveChoiceError: "Die gewählte Aktion konnte nicht übermittelt werden: %@",
            .notificationDisplayError: "Mitteilung konnte nicht angezeigt werden: %@",
            .jobStartedLog: "Datei wird vertont: %@",
            .formatWAVHint: "PCM · 16 Bit · 24 kHz · mono",
            .unknownFileName: "unbekannte Datei",
            .missingRuntimeError: "Die Installation ist beschädigt: Eine Komponente zur Sprachausgabe fehlt in der App.",
            .etaEstimating: "Geschwindigkeit wird geschätzt…",
            .etaUnderMinute: "Weniger als eine Minute verbleibend",
            .etaMinutes: "Verbleibende Zeit: ca. %@ Min.",
            .etaHoursMinutes: "Verbleibende Zeit: ca. %@ Std. %@ Min."
        ],
        .english: [
            .preflightFailed: "Check failed · report saved",
            .preflightChoiceTitle: "Some queue files have problems",
            .preflightChoiceMessage: "Could not validate %1$@ files. Continue with only the %2$@ ready files?",
            .preflightRunReady: "Process ready files", .preflightReview: "Return to fix them",
            .readinessFFmpeg: "FFmpeg", .readinessPython: "Silero Python environment", .readinessModel: "Silero model v5.5",
            .readinessFound: "found · not fully verified", .readinessMissing: "missing",
            .readinessVerified: "checked", .readinessError: "found · check failed",
            .readinessNote: "FFmpeg and the Python version are launched and checked. The model check confirms only that the file exists; nothing is installed or downloaded. Use Preview voice to test model loading and speech.",
            .readinessNoFFmpeg: "FFmpeg was not found. AAC export and timing adjustment require it. Install it using the setup guide. Expected search included: %@",
            .readinessNoPython: "The dedicated Python environment was not found. The app will not create or change it. Follow the Silero setup guide. Expected path: %@",
            .readinessNoModel: "The local v5_5_ru.pt model is missing or empty. Synthesis never downloads it automatically. Expected path: %@",
            .sampleOriginal: "Source text:\n%@\n\nText that will be sent to Silero:\n%@",
            .samplePrepared: "Text for Silero:\n%@",
            .sampleWarnings: "\n\nPronunciation notes:\n%@",
            .sampleNoWarnings: "\n\nNo additional pronunciation warnings.",
            .statusPreparingVoice: "Preparing voiceover…",
            .statusLoadingModel: "Loading the local Silero model…",
            .statusSynthesisStarted: "Text prepared: %@ subtitles, %@ speech phrases.",
            .statusSavingAAC: "Saving AAC for MP4…",
            .statusAACFallback: "Apple AAC is unavailable. Falling back to FFmpeg AAC…",
            .statusVerifyingAAC: "Verifying the finished audio track…",
            .statusSynthesisProgress: "Silero phrases: %@ of %@",
            .warningTempoFit: "Subtitle cues %@–%@ were sped up to ×%@; words are kept and pauses shortened.",
            .warningSilentCues: "Subtitle cues %@ contained no words; the audio timeline is preserved.",
            .technicalDetails: "Technical details: %@",
            .voiceoverFailure: "The audio track could not be created. The previous result was not replaced.",
            .unknownChildEvent: "Received an unknown event from the worker process.",
            .preflightIssue: "❌ %@ · cues %@ · %@ · issue %@%@",
            .preflightFixHint: "Fix the text or timestamps, then check the queue again.",
            .preflightUnsupportedSymbol: "unsupported or mixed-script character",
            .preflightSpeechPreparation: "could not prepare speech text",
            .preflightGenericIssue: "could not validate subtitle text",
            .preflightActionUnsupportedSymbol: "Replace the unsupported character with words or standard punctuation.",
            .preflightActionSpeechPreparation: "Correct this phrase or add an exact pronunciation to the dictionary.",
            .preflightActionGeneric: "Check the SRT file and its timestamps.",
            .preflightCancelledReport: "Cancelled before synthesis: %@ · report %@",
            .supportDirectoryError: "Could not prepare the working folder: %@",
            .queuePreflightLog: "Checking the entire queue before loading the Silero model…",
            .queueStartedLog: "Queue started: %@ files · voice %@ · format %@ · pacing %@.",
            .cleanupDiagnostic: "Report-cleanup diagnostic: %@",
            .preflightPassedFile: "Checked before loading the voice: %@",
            .savedOutput: "Saved: %@",
            .savedOutputWithWarnings: "Done · warnings: %@",
            .fileNotReady: "File not ready: %@. Moving to the next file.",
            .exitCode: "exit code %@",
            .resolveChoiceError: "Could not apply the selected action: %@",
            .notificationDisplayError: "Could not display notification: %@",
            .jobStartedLog: "Processing file: %@",
            .formatWAVHint: "PCM · 16-bit · 24 kHz · mono",
            .unknownFileName: "unknown file",
            .missingRuntimeError: "The installation is damaged: a voiceover component is missing from the app.",
            .etaEstimating: "Estimating speed…",
            .etaUnderMinute: "Less than a minute of phrases remaining",
            .etaMinutes: "Phrases remaining: about %@ min",
            .etaHoursMinutes: "Phrases remaining: about %@ hr %@ min"
        ]
    ]
    static func text(_ key: AppText, language: AppLanguage) -> String {
        additionalCatalog[language]?[key] ?? catalog[language]?[key] ?? catalog[.english]?[key] ?? key.rawValue
    }
    static func preflightIssueLabel(_ code: String, language: AppLanguage) -> String {
        let key: AppText
        switch code {
        case "unsupported_symbol": key = .preflightUnsupportedSymbol
        case "speech_preparation_error": key = .preflightSpeechPreparation
        default: key = .preflightGenericIssue
        }
        return text(key, language: language)
    }
    static func preflightIssueAction(_ code: String, language: AppLanguage) -> String {
        let key: AppText
        switch code {
        case "unsupported_symbol": key = .preflightActionUnsupportedSymbol
        case "speech_preparation_error": key = .preflightActionSpeechPreparation
        default: key = .preflightActionGeneric
        }
        return text(key, language: language)
    }
    static func missingKeys(for language: AppLanguage) -> [AppText] {
        AppText.allCases.filter { additionalCatalog[language]?[$0] == nil && catalog[language]?[$0] == nil }
    }
    static func format(_ key: AppText, language: AppLanguage, _ values: CVarArg...) -> String {
        String(format: text(key, language: language), locale: Locale(identifier: language.rawValue), arguments: values)
    }
}

enum ReadinessState: Equatable {
    case missing, found, verified, error
}

struct ReadinessItem {
    let name: String
    let state: ReadinessState
    let detail: String
}

enum WorkerEventProtocol {
    static func decode(_ data: Data, expectedJobID: UUID) -> [String: Any]? {
        guard let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              event["protocol_version"] as? Int == 1,
              let jobID = event["job_id"] as? String,
              let parsedID = UUID(uuidString: jobID),
              parsedID == expectedJobID,
              let type = event["type"] as? String,
              !type.isEmpty else { return nil }
        return event
    }
}

enum DependencyReadiness {
    /// Read-only checks. The probe closure is injectable so tests never launch
    /// host dependencies or mutate the user's installation.
    typealias Probe = (String, [String]) -> (Int32, String)

    static func run(_ executable: String, _ arguments: [String]) -> (Int32, String) {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = output
        do {
            try process.run()
            output.fileHandleForWriting.closeFile()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus, String(decoding: data, as: UTF8.self))
        } catch {
            return (-1, error.localizedDescription)
        }
    }

    static func ffmpegPath(searchPaths: [String], executable: (String) -> Bool) -> String? {
        for directory in searchPaths {
            let candidate = URL(fileURLWithPath: directory, isDirectory: true)
                .appendingPathComponent("ffmpeg").path
            if executable(candidate) { return candidate }
        }
        return nil
    }

    static func inspect(
        directoryHasModel: (String) -> Bool,
        executable: (String) -> Bool,
        searchPaths: [String],
        sileroPython: String,
        modelDirectories: [String],
        probe: Probe = DependencyReadiness.run
    ) -> [ReadinessItem] {
        let ffmpeg = ffmpegPath(searchPaths: searchPaths, executable: executable)
        let ffmpegResult: ReadinessItem
        if let ffmpeg {
            let version = probe(ffmpeg, ["-hide_banner", "-version"])
            let filters = probe(ffmpeg, ["-hide_banner", "-filters"])
            let encoders = probe(ffmpeg, ["-hide_banner", "-encoders"])
            let hasTempo = filters.1.contains("atempo")
            let hasAAC = encoders.1.range(of: #"\s+aac\s"#, options: .regularExpression) != nil
            if version.0 == 0 && filters.0 == 0 && encoders.0 == 0 && hasTempo && hasAAC {
                let versionLine = version.1.components(separatedBy: .newlines).first ?? "FFmpeg"
                ffmpegResult = ReadinessItem(name: "FFmpeg", state: .verified, detail: "\(ffmpeg)\n\(versionLine)")
            } else {
                let failedProbe = [version, filters, encoders].first(where: { $0.0 != 0 })
                let reason: String = failedProbe.map { $0.1 } ??
                    "Required capabilities are missing (atempo filter / AAC encoder)."
                ffmpegResult = ReadinessItem(name: "FFmpeg", state: .error, detail: "\(ffmpeg)\n\(reason)")
            }
        } else {
            ffmpegResult = ReadinessItem(name: "FFmpeg", state: .missing,
                detail: searchPaths.map { URL(fileURLWithPath: $0).appendingPathComponent("ffmpeg").path }.joined(separator: "\n"))
        }

        let pythonResult: ReadinessItem
        if executable(sileroPython) {
            let python = probe(sileroPython, ["-c", "import platform,sys; print(f'{sys.version_info.major}.{sys.version_info.minor}|{platform.machine()}')"])
            if python.0 == 0 && python.1.trimmingCharacters(in: .whitespacesAndNewlines) == "3.12|arm64" {
                pythonResult = ReadinessItem(name: "Silero environment", state: .verified,
                    detail: "\(sileroPython)\nPython 3.12 · arm64")
            } else {
                pythonResult = ReadinessItem(name: "Silero environment", state: .error,
                    detail: "\(sileroPython)\n\(python.1.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
        } else {
            pythonResult = ReadinessItem(name: "Silero environment", state: .missing, detail: sileroPython)
        }

        let modelPath = modelDirectories.first(where: directoryHasModel)
        let modelResult = ReadinessItem(name: "Silero model files", state: modelPath == nil ? .missing : .found,
            detail: modelPath ?? modelDirectories.first ?? "")
        return [ffmpegResult, pythonResult, modelResult]
    }
}

enum VoiceoverInstallation {
    static func runtimeDirectory(programOverride: String?, resourceDirectory: URL?, bundleURL: URL) -> URL {
        if let path = programOverride, !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        if let resources = resourceDirectory {
            return resources.appendingPathComponent("Runtime", isDirectory: true)
        }
        return bundleURL.deletingLastPathComponent()
    }

    static func supportDirectory(dataOverride: String?, homeDirectory: String) -> URL {
        if let path = dataOverride, !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return URL(fileURLWithPath: homeDirectory, isDirectory: true)
            .appendingPathComponent("Library/Application Support/SRTtoSound", isDirectory: true)
    }
}

struct VoiceoverSelection {
    var files: [URL] = []
    var errors: [String] = []
}

enum VoiceoverFiles {
    static func isFinalRussian(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        return name.hasSuffix(".ru.srt") &&
            name.range(of: #"(?:^|[._ -])(?:part|chunk|segment|часть)[._ -]*\d+"#, options: .regularExpression) == nil
    }

    static func collect(_ urls: [URL]) -> VoiceoverSelection {
        let manager = FileManager.default
        var result = VoiceoverSelection()
        var found = Set<URL>()
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
        for url in urls {
            do {
                let values = try url.resourceValues(forKeys: Set(keys))
                if values.isDirectory == true {
                    guard values.isSymbolicLink != true else { continue }
                    let iterator = manager.enumerator(at: url, includingPropertiesForKeys: keys,
                        options: [.skipsHiddenFiles, .skipsPackageDescendants]) { path, error in
                            result.errors.append("\(path.path): \(error.localizedDescription)")
                            return true
                        }
                    while let file = iterator?.nextObject() as? URL {
                        let info = try file.resourceValues(forKeys: Set(keys))
                        if info.isSymbolicLink == true || ["translation-work", "releases"].contains(file.lastPathComponent.lowercased()) {
                            iterator?.skipDescendants()
                            continue
                        }
                        if info.isRegularFile == true && isFinalRussian(file) {
                            found.insert(file.resolvingSymlinksInPath().standardizedFileURL)
                        }
                    }
                } else if values.isRegularFile == true && url.pathExtension.lowercased() == "srt" {
                    found.insert(url.resolvingSymlinksInPath().standardizedFileURL)
                }
            } catch { result.errors.append("\(url.path): \(error.localizedDescription)") }
        }
        result.files = found.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        return result
    }

    static func output(for input: URL, format: String, downloads: URL?) -> URL {
        let stem = input.deletingPathExtension().lastPathComponent
        let russianStem = stem.lowercased().hasSuffix(".ru") ? stem : stem + ".ru"
        let name = russianStem + ".\(format)"
        return (downloads ?? input.deletingLastPathComponent()).appendingPathComponent(name)
    }

    static func remaining(_ seconds: Double, language: AppLanguage = .russian) -> String {
        guard seconds.isFinite && seconds >= 0 else { return Localization.text(.etaEstimating, language: language) }
        let minutes = Int(ceil(min(seconds, 31_536_000) / 60))
        if minutes < 1 { return Localization.text(.etaUnderMinute, language: language) }
        if minutes < 60 { return Localization.format(.etaMinutes, language: language, String(minutes)) }
        return Localization.format(.etaHoursMinutes, language: language, String(minutes / 60), String(minutes % 60))
    }
}
