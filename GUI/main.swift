import AppKit
import AVFoundation
import UniformTypeIdentifiers
import UserNotifications

enum AudioFormat: String, CaseIterable {
    case m4a, wav
    func title(_ language: AppLanguage) -> String { Localization.text(self == .m4a ? .formatAAC : .formatWAV, language: language) }
}

enum SpeechRhythm: String, CaseIterable {
    case smooth, strict
    func title(_ language: AppLanguage) -> String { Localization.text(self == .smooth ? .rhythmSmooth : .rhythmStrict, language: language) }
}

enum JobState { case waiting, running, done, failed, stopped, skipped }
struct Job {
    let input: URL
    var state: JobState = .waiting
    var progress: Double = 0
    var detail = ""
    var output: URL?
    var report: URL?
    var warnings = 0
}

struct NormalizedVoiceSample {
    let sourceSRT: String
    let sourceText: String
    let preparedText: String
    let warnings: [String]
    let fingerprint: String
}

func argument(_ name: String) -> String? {
    guard let i = CommandLine.arguments.firstIndex(of: name), i + 1 < CommandLine.arguments.count else { return nil }
    return CommandLine.arguments[i + 1]
}

final class WindowBackground: NSView {
    override var isOpaque: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
    }
}

final class VoiceoverWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), let chars = event.charactersIgnoringModifiers?.lowercased() {
            let action: Selector? = ["c": #selector(NSText.copy(_:)), "v": #selector(NSText.paste(_:)),
                                     "x": #selector(NSText.cut(_:)), "a": #selector(NSText.selectAll(_:))][chars]
            if let action, NSApp.sendAction(action, to: nil, from: self) { return true }
        }
        return super.performKeyEquivalent(with: event)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, UNUserNotificationCenterDelegate, AVAudioPlayerDelegate {
    var language = AppLanguage.load() ?? .russian
    var appearance = AppAppearance.load()
    func t(_ key: AppText) -> String { Localization.text(key, language: language) }
    var window: NSWindow!
    let table = NSTableView()
    let voices = NSPopUpButton()
    let formats = NSPopUpButton()
    let rhythms = NSPopUpButton()
    let destinations = NSPopUpButton()
    let notifyOnFinish = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    let eta = NSTextField(labelWithString: "")
    let formatHint = NSTextField(labelWithString: "")
    let voiceHint = NSTextField(wrappingLabelWithString: "")
    let status = NSTextField(labelWithString: "")
    let progress = NSProgressIndicator()
    let log = NSTextView()
    var addButton: NSButton!
    var folderButton: NSButton!
    var removeButton: NSButton!
    var clearButton: NSButton!
    var startButton: NSButton!
    var stopButton: NSButton!
    var testButton: NSButton!
    var readinessButton: NSButton!
    var revealButton: NSButton!
    var reportsButton: NSButton!
    var jobs: [Job] = []
    var runIndices: [Int] = []
    var queueInputDigests: [String: String] = [:]
    var queuePreparationFingerprints: [String: String] = [:]
    var preflightFailedCount = 0
    var runPosition = 0
    var activeProcess: Process?
    var preflightProcess: Process?
    var activeID: UUID?
    var activeRow: Int?
    var activeOutput: URL?
    var activeError: String?
    var activeSkipped = false
    var activeWarnings = 0
    var activeInputPipe: Pipe?
    var conflictAlert: NSAlert?
    var isBusy = false
    var isTest = false
    var stopRequested = false
    var quitting = false
    var lastReportOpenSucceeded = false
    var lastReportOpenTarget: URL?
    var activity: NSObjectProtocol?
    var sessionVoice = Voice.all[0]
    var sessionFormat = AudioFormat.m4a
    var sessionRhythm = SpeechRhythm.smooth
    var sessionDownloads: URL?
    var player: AVAudioPlayer?
    var voiceTestDirectory: URL?
    var lastOutput: URL?
    var automatedTest: Bool {
        argument("--integration-test") != nil || argument("--ui-smoke-test") != nil ||
            argument("--readiness-smoke-test") != nil || argument("--interactive-review") != nil ||
            argument("--error-sheet-smoke-test") != nil
    }
    var reportsDirectory: URL {
        if let path = argument("--reports-dir") { return URL(fileURLWithPath: path, isDirectory: true) }
        if automatedTest { return supportDirectory.appendingPathComponent("Reports", isDirectory: true) }
        return URL(fileURLWithPath: NSHomeDirectory() + "/Library/Logs/SRTtoSound", isDirectory: true)
    }
    var runtimeDirectory: URL {
        VoiceoverInstallation.runtimeDirectory(programOverride: argument("--program-dir"),
            resourceDirectory: Bundle.main.resourceURL, bundleURL: Bundle.main.bundleURL)
    }
    var supportDirectory: URL {
        VoiceoverInstallation.supportDirectory(dataOverride: argument("--data-dir"), homeDirectory: NSHomeDirectory())
    }
    var sileroEnvironment: URL { supportDirectory.appendingPathComponent(".venv-silero-py312", isDirectory: true) }
    var sileroModel: URL { supportDirectory.appendingPathComponent("models/v5_5_ru.pt") }

    func prepareSupportDirectory() throws {
        let manager = FileManager.default
        try manager.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        try manager.createDirectory(at: supportDirectory.appendingPathComponent("models", isDirectory: true), withIntermediateDirectories: true)
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: supportDirectory.path)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let selected = argument("--test-language"), let testLanguage = AppLanguage(rawValue: selected), automatedTest { language = testLanguage }
        if let selected = argument("--test-theme"), let testAppearance = AppAppearance(rawValue: selected), automatedTest { appearance = testAppearance }
        selectFirstRunLanguageIfNeeded()
        makeMenu()
        makeWindow()
        do { try prepareSupportDirectory() }
        catch { appendLog(Localization.format(.supportDirectoryError, language: language, error.localizedDescription)) }
        cleanupReports()
        if !automatedTest { UNUserNotificationCenter.current().delegate = self }
        if let snapshot = argument("--ui-smoke-test") {
            let examples: [String]
            switch language {
            case .russian: examples = ["/Пример/01_Лекция.ru.srt", "/Пример/02_Лекция.ru.srt"]
            case .german: examples = ["/Beispiele/01_Vorlesung.ru.srt", "/Beispiele/02_Vorlesung.ru.srt"]
            case .english: examples = ["/Examples/01_Lecture.ru.srt", "/Examples/02_Lecture.ru.srt"]
            }
            jobs = examples.map { Job(input: URL(fileURLWithPath: $0)) }
            for index in jobs.indices { jobs[index].detail = t(.queued) }
            if let reportPath = argument("--test-selected-report"),
               FileManager.default.fileExists(atPath: reportPath), !jobs.isEmpty {
                jobs[0].report = URL(fileURLWithPath: reportPath)
            }
            status.stringValue = Localization.format(.queuedCount, language: language, String(jobs.count))
            refresh()
            if argument("--test-selected-report") != nil, !jobs.isEmpty {
                table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
                refreshButtons()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if argument("--test-activate-selected-report") != nil {
                    self.capture(to: snapshot, exitAfter: false)
                    guard self.table.selectedRow >= 0,
                          self.jobs.indices.contains(self.table.selectedRow),
                          self.jobs[self.table.selectedRow].report != nil else { exit(5) }
                    self.reportsButton.performClick(nil)
                    let expectedPath = argument("--test-selected-report")
                    let openedExpectedReport = self.lastReportOpenSucceeded &&
                        self.lastReportOpenTarget?.path == expectedPath
                    if let receiptPath = argument("--test-open-result") {
                        let targetPath = self.lastReportOpenTarget?.path ?? "none"
                        let receipt = "opened=\(openedExpectedReport)\ntarget=\(targetPath)\n"
                        do { try receipt.write(toFile: receiptPath, atomically: true, encoding: .utf8) }
                        catch { exit(7) }
                    }
                    exit(openedExpectedReport ? 0 : 6)
                }
                self.capture(to: snapshot, exitAfter: argument("--interactive-review") == nil)
            }
        } else if let directory = argument("--integration-test") {
            voices.selectItem(at: Voice.all.firstIndex { $0.tag == argument("--test-voice") } ?? 0)
            voiceChanged(nil)
            formats.selectItem(at: AudioFormat.allCases.firstIndex { $0.rawValue == argument("--test-format") } ?? 0)
            formatChanged(nil)
            rhythms.selectItem(at: SpeechRhythm.allCases.firstIndex { $0.rawValue == argument("--test-rhythm") } ?? 0)
            rhythmChanged(nil)
            destinations.selectItem(at: argument("--test-downloads") == nil ? 0 : 1)
            add([URL(fileURLWithPath: directory, isDirectory: true)])
            guard !jobs.isEmpty else { fputs("No integration fixtures\n", stderr); exit(1) }
            startQueue(nil)
        } else if argument("--readiness-smoke-test") != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.showReadiness(nil) }
        } else if let snapshot = argument("--error-sheet-smoke-test"), automatedTest {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.showError("Synthetic QA diagnostic: this deliberately long message checks wrapping and VoiceOver context without reading any user file. Technical detail: SAMPLE_ENGINE_ERROR_42.")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    guard let sheet = self.window.attachedSheet else { exit(2) }
                    self.capture(to: snapshot, view: sheet.contentView,
                        exitAfter: argument("--interactive-review") == nil)
                }
            }
        }
    }

    func selectFirstRunLanguageIfNeeded() {
        guard AppLanguage.load() == nil, !automatedTest else { return }
        let preferred = Locale.preferredLanguages.first.flatMap { AppLanguage(rawValue: String($0.prefix(2))) } ?? .english
        let alert = NSAlert()
        alert.messageText = Localization.text(.firstRunTitle, language: preferred)
        alert.informativeText = Localization.text(.firstRunMessage, language: preferred)
        AppLanguage.allCases.forEach { alert.addButton(withTitle: $0.displayName) }
        alert.buttons[AppLanguage.allCases.firstIndex(of: preferred) ?? 2].keyEquivalent = "\r"
        let choice = alert.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        language = AppLanguage.allCases.indices.contains(choice) ? AppLanguage.allCases[choice] : .english
        language.save()
    }

    func makeMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: t(.quit), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)
        let appearanceItem = NSMenuItem(title: t(.appearance), action: nil, keyEquivalent: "")
        let appearanceMenu = NSMenu(title: t(.appearance))
        let themeMenu = NSMenu(title: t(.appearance))
        for (index, theme) in AppAppearance.allCases.enumerated() {
            let keys: [AppText] = [.systemTheme, .lightTheme, .darkTheme]
            let item = NSMenuItem(title: t(keys[index]), action: #selector(appearanceChanged(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.state = appearance == theme ? .on : .off
            themeMenu.addItem(item)
        }
        let themeItem = NSMenuItem(title: t(.appearance), action: nil, keyEquivalent: "")
        themeItem.submenu = themeMenu
        appearanceMenu.addItem(themeItem)
        let languageMenu = NSMenu(title: t(.language))
        for (index, value) in AppLanguage.allCases.enumerated() {
            let item = NSMenuItem(title: value.displayName, action: #selector(languageChanged(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.state = language == value ? .on : .off
            languageMenu.addItem(item)
        }
        let languageItem = NSMenuItem(title: t(.language), action: nil, keyEquivalent: "")
        languageItem.submenu = languageMenu
        appearanceMenu.addItem(languageItem)
        appearanceItem.submenu = appearanceMenu
        menu.addItem(appearanceItem)
        NSApp.mainMenu = menu
    }

    @objc func appearanceChanged(_ sender: NSMenuItem) {
        guard AppAppearance.allCases.indices.contains(sender.tag) else { return }
        appearance = AppAppearance.allCases[sender.tag]
        appearance.save()
        NSApp.appearance = appearance == .system ? nil : NSAppearance(named: appearance == .light ? .aqua : .darkAqua)
        makeMenu()
    }

    @objc func languageChanged(_ sender: NSMenuItem) {
        guard AppLanguage.allCases.indices.contains(sender.tag) else { return }
        language = AppLanguage.allCases[sender.tag]
        language.save()
        let oldWindow = window
        makeMenu()
        makeWindow()
        oldWindow?.close()
    }

    func label(_ text: String, size: CGFloat = 13, color: NSColor = .labelColor) -> NSTextField {
        let view = NSTextField(labelWithString: text)
        view.font = .systemFont(ofSize: size)
        view.textColor = color
        return view
    }

    func button(_ text: String, _ action: Selector) -> NSButton {
        let view = NSButton(title: text, target: self, action: action)
        view.bezelStyle = .rounded
        return view
    }

    func row(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10
        return stack
    }

    func makeWindow() {
        window = VoiceoverWindow(contentRect: NSRect(x: 0, y: 0, width: 940, height: 840),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = t(.windowTitle)
        window.minSize = NSSize(width: 980, height: 810)
        window.delegate = self
        NSApp.appearance = appearance == .system ? nil : NSAppearance(named: appearance == .light ? .aqua : .darkAqua)
        window.isReleasedWhenClosed = false
        let root = WindowBackground()
        window.contentView = root
        let heading = label(t(.heading), size: 28)
        heading.font = .systemFont(ofSize: 28, weight: .semibold)
        let subtitle = label(t(.subtitle), color: .secondaryLabelColor)
        addButton = button(t(.addFiles), #selector(chooseFiles(_:)))
        folderButton = button(t(.addFolder), #selector(chooseFolder(_:)))
        removeButton = button(t(.removeSelected), #selector(removeSelected(_:)))
        clearButton = button(t(.clearList), #selector(clearQueue(_:)))
        let toolbar = row([addButton, folderButton, removeButton, clearButton])

        let fileColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("file"))
        fileColumn.title = t(.fileColumn)
        fileColumn.width = 590
        fileColumn.minWidth = 350
        let stateColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("state"))
        stateColumn.title = t(.stateColumn)
        stateColumn.width = 215
        stateColumn.minWidth = 170
        table.addTableColumn(fileColumn)
        table.addTableColumn(stateColumn)
        table.delegate = self
        table.dataSource = self
        table.rowHeight = 38
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = true
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.registerForDraggedTypes([.fileURL])
        let list = NSScrollView()
        list.documentView = table
        list.hasVerticalScroller = true
        list.borderType = .bezelBorder
        list.heightAnchor.constraint(greaterThanOrEqualToConstant: 170).isActive = true
        list.setContentHuggingPriority(.defaultLow, for: .vertical)

        voices.addItems(withTitles: Voice.all.map { voice in
            return Localization.format(.voiceSilero, language: language, String(voice.title.split(separator: "·").last ?? "").trimmingCharacters(in: .whitespaces))
        })
        let savedVoice = UserDefaults.standard.string(forKey: "voiceTag")
        voices.selectItem(at: Voice.index(forTag: savedVoice))
        voices.target = self
        voices.action = #selector(voiceChanged(_:))
        voices.widthAnchor.constraint(equalToConstant: 265).isActive = true
        testButton = button(t(.previewVoice), #selector(testVoice(_:)))
        let sampleButton = button(normalizedSampleTitle, #selector(showNormalizedVoiceSample(_:)))
        let voiceRow = row([label(t(.voice)), voices, testButton, sampleButton])
        formats.addItems(withTitles: AudioFormat.allCases.map { $0.title(language) })
        let savedFormat = UserDefaults.standard.string(forKey: "outputAudioFormat")
        let format = argument("--test-format") ?? savedFormat
        formats.selectItem(at: AudioFormat.allCases.firstIndex { $0.rawValue == format } ?? 0)
        formats.target = self
        formats.action = #selector(formatChanged(_:))
        formats.widthAnchor.constraint(equalToConstant: 265).isActive = true
        formatHint.font = .systemFont(ofSize: 12)
        formatHint.textColor = .secondaryLabelColor
        let formatRow = row([label(t(.format)), formats, formatHint])
        rhythms.addItems(withTitles: SpeechRhythm.allCases.map { $0.title(language) })
        let savedRhythm = UserDefaults.standard.string(forKey: "rhythm")
        rhythms.selectItem(at: SpeechRhythm.allCases.firstIndex { $0.rawValue == savedRhythm } ?? 0)
        rhythms.target = self
        rhythms.action = #selector(rhythmChanged(_:))
        rhythms.widthAnchor.constraint(equalToConstant: 265).isActive = true
        let rhythmRow = row([label(t(.rhythm)), rhythms])
        destinations.addItems(withTitles: [t(.besideSRT), t(.downloads)])
        destinations.selectItem(at: UserDefaults.standard.string(forKey: "outputLocation") == "downloads" ? 1 : 0)
        destinations.target = self
        destinations.action = #selector(destinationChanged(_:))
        destinations.widthAnchor.constraint(equalToConstant: 265).isActive = true
        notifyOnFinish.state = UserDefaults.standard.object(forKey: "notifyOnFinish") as? Bool == false ? .off : .on
        notifyOnFinish.target = self
        notifyOnFinish.action = #selector(destinationChanged(_:))
        notifyOnFinish.title = t(.notify)
        let destinationRow = row([label(t(.saveTo)), destinations, notifyOnFinish])
        voiceHint.font = .systemFont(ofSize: 12)
        voiceHint.textColor = .secondaryLabelColor
        voiceHint.maximumNumberOfLines = 2

        let help = NSTextField(wrappingLabelWithString: t(.help))
        help.font = .systemFont(ofSize: 12)
        help.textColor = .secondaryLabelColor
        status.font = .systemFont(ofSize: 13, weight: .medium)
        status.maximumNumberOfLines = 2
        status.lineBreakMode = .byWordWrapping
        eta.font = .systemFont(ofSize: 12)
        eta.textColor = .secondaryLabelColor
        progress.isIndeterminate = false
        progress.minValue = 0
        progress.maxValue = 100
        progress.style = .bar
        startButton = button(t(.startQueue), #selector(startQueue(_:)))
        startButton.keyEquivalent = "\r"
        stopButton = button(t(.stop), #selector(stop(_:)))
        revealButton = button(t(.showResult), #selector(reveal(_:)))
        reportsButton = button(t(.reports), #selector(revealReports(_:)))
        readinessButton = button(readinessTitle, #selector(showReadiness(_:)))
        let controls = row([startButton, stopButton, revealButton, reportsButton, readinessButton])

        log.isEditable = false
        log.isSelectable = true
        log.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        log.textContainerInset = NSSize(width: 8, height: 8)
        log.autoresizingMask = [.width]
        log.textContainer?.widthTracksTextView = true
        let logScroll = NSScrollView()
        logScroll.documentView = log
        logScroll.hasVerticalScroller = true
        logScroll.borderType = .bezelBorder
        logScroll.heightAnchor.constraint(equalToConstant: 110).isActive = true
        let stack = NSStackView(views: [heading, subtitle, toolbar, list, voiceRow, voiceHint, formatRow, rhythmRow, destinationRow, help, status, eta, progress, controls, logScroll])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 22),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -22)
        ])
        for view in [list, voiceHint, help, status, progress, logScroll] {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        voiceChanged(nil)
        formatChanged(nil)
        rhythmChanged(nil)
        refresh()
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(root)
        status.stringValue = t(.idleStatus)
        NSApp.activate(ignoringOtherApps: true)
    }

    var readinessTitle: String {
        switch language { case .russian: "Проверка установки"; case .german: "Installation prüfen"; case .english: "Check setup" }
    }

    var ffmpegSearchPaths: [String] {
        let path = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:" +
            (ProcessInfo.processInfo.environment["PATH"] ?? "")
        var ordered: [String] = []
        for directory in path.split(separator: ":").map(String.init) where !ordered.contains(directory) {
            ordered.append(directory)
        }
        ordered += [
            "/Applications/Subtitle Edit.app/Contents/MacOS",
            "/Applications/Wondershare UniConverter 15.app/Contents/MacOS",
            "/Applications/Ultimate Vocal Remover.app/Contents/Frameworks"
        ]
        return ordered
    }

    var selectedFFmpegPath: String? {
        if automatedTest, let path = argument("--test-ffmpeg") { return path }
        return DependencyReadiness.ffmpegPath(searchPaths: ffmpegSearchPaths,
            executable: { FileManager.default.isExecutableFile(atPath: $0) })
    }

    @objc func showReadiness(_ sender: Any?) {
        let modelPath = sileroModel.path
        let items = DependencyReadiness.inspect(
            directoryHasModel: { path in
                guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
                      (attributes[.type] as? FileAttributeType) == .typeRegular else { return false }
                return ((attributes[.size] as? NSNumber)?.intValue ?? 0) > 0
            },
            executable: { FileManager.default.isExecutableFile(atPath: $0) },
            searchPaths: ffmpegSearchPaths,
            sileroPython: sileroEnvironment.appendingPathComponent("bin/python").path,
            modelDirectories: [modelPath])
        let header: [AppLanguage: String] = [.russian: "Компонент · состояние", .german: "Komponente · Status", .english: "Component · status"]
        let lines = items.map { item in
            let titleKey: AppText = switch item.name {
            case "FFmpeg": .readinessFFmpeg
            case "Silero environment": .readinessPython
            default: .readinessModel
            }
            let detailKey: AppText = switch item.name {
            case "FFmpeg": .readinessNoFFmpeg
            case "Silero environment": .readinessNoPython
            default: .readinessNoModel
            }
            let stateKey: AppText = switch item.state {
            case .missing: .readinessMissing
            case .found: .readinessFound
            case .verified: .readinessVerified
            case .error: .readinessError
            }
            let state = t(stateKey)
            let detail = item.state == .missing
                ? Localization.format(detailKey, language: language, item.detail)
                : item.detail
            return "\(t(titleKey)): \(state)\n  \(detail)"
        }.joined(separator: "\n\n")
        let alert = NSAlert()
        alert.messageText = readinessTitle
        alert.informativeText = "\(header[language] ?? "Component · status")\n\n\(lines)\n\n\(t(.readinessNote))"
        alert.alertStyle = .informational
        alert.addButton(withTitle: language == .russian ? "Закрыть" : (language == .german ? "Schließen" : "Close"))
        if let snapshot = argument("--readiness-smoke-test"), automatedTest {
            alert.beginSheetModal(for: window) { _ in }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.capture(to: snapshot, view: alert.window.contentView)
            }
        } else {
            alert.runModal()
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { jobs.count }
    func queueFileTitle(for input: URL) -> String {
        let name = input.lastPathComponent
        let duplicates = jobs.filter { $0.input.lastPathComponent == name }
        guard duplicates.count > 1 else { return name }
        return "\(input.deletingLastPathComponent().lastPathComponent) / \(name)"
    }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard jobs.indices.contains(row) else { return nil }
        let job = jobs[row]
        let view = label(tableColumn?.identifier.rawValue == "file" ? queueFileTitle(for: job.input) : job.detail)
        view.lineBreakMode = .byTruncatingMiddle
        view.toolTip = [job.input.path, job.detail, job.report.map { "\(t(.openSelectedReport)): \($0.path)" }]
            .compactMap { $0 }.joined(separator: "\n")
        if tableColumn?.identifier.rawValue == "state" {
            view.textColor = job.state == .failed ? .systemRed :
                (job.state == .done ? (job.warnings > 0 ? .systemOrange : .systemGreen) : .secondaryLabelColor)
        }
        return view
    }
    func tableViewSelectionDidChange(_ notification: Notification) { refreshButtons() }
    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation operation: NSTableView.DropOperation) -> NSDragOperation {
        if isBusy { return [] }
        tableView.setDropRow(-1, dropOperation: .on)
        return .copy
    }
    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation operation: NSTableView.DropOperation) -> Bool {
        guard !isBusy, let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] else { return false }
        add(urls)
        return true
    }

    @objc func chooseFiles(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.title = t(.chooseFilesTitle)
        panel.message = t(.chooseFilesMessage)
        panel.allowedContentTypes = [UTType(filenameExtension: "srt") ?? .plainText]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.beginSheetModal(for: window) { response in
            if response == .OK { self.add(panel.urls) }
        }
    }

    @objc func chooseFolder(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.title = t(.chooseFolderTitle)
        panel.message = t(.chooseFolderMessage)
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.beginSheetModal(for: window) { response in
            if response == .OK { self.add(panel.urls) }
        }
    }

    func add(_ urls: [URL]) {
        guard !isBusy else { return }
        let selection = VoiceoverFiles.collect(urls)
        let sorted = selection.files
        for error in selection.errors { appendLog(error) }
        for url in sorted where !jobs.contains(where: { $0.input == url }) { jobs.append(Job(input: url)) }
        status.stringValue = Localization.format(.queuedCount, language: language, String(jobs.count))
        if sorted.isEmpty { appendLog(t(.emptySelection)) }
        if sorted.contains(where: { !$0.lastPathComponent.lowercased().hasSuffix(".ru.srt") }) {
            appendLog(t(.wrongSubtitleWarning))
        }
        refresh()
    }
    @objc func removeSelected(_ sender: Any?) {
        guard !isBusy else { return }
        for index in table.selectedRowIndexes.reversed() { jobs.remove(at: index) }
        table.deselectAll(nil)
        refresh()
    }
    @objc func clearQueue(_ sender: Any?) {
        guard !isBusy else { return }
        jobs.removeAll()
        status.stringValue = t(.clearStatus)
        progress.doubleValue = 0
        refresh()
    }
    @objc func voiceChanged(_ sender: Any?) {
        let voice = Voice.all[max(0, voices.indexOfSelectedItem)]
        if !automatedTest {
            UserDefaults.standard.set(voice.tag, forKey: "voiceTag")
        }
        voiceHint.stringValue = t(.voiceSileroHint)
    }

    @objc func destinationChanged(_ sender: Any?) {
        guard !automatedTest else { return }
        UserDefaults.standard.set(destinations.indexOfSelectedItem == 1 ? "downloads" : "source", forKey: "outputLocation")
        UserDefaults.standard.set(notifyOnFinish.state == .on, forKey: "notifyOnFinish")
    }

    @objc func rhythmChanged(_ sender: Any?) {
        guard !automatedTest else { return }
        let rhythm = SpeechRhythm.allCases[max(0, rhythms.indexOfSelectedItem)]
        UserDefaults.standard.set(rhythm.rawValue, forKey: "rhythm")
    }

    var normalizedSampleTitle: String {
        switch language {
        case .russian: return "Тестовый текст"
        case .german: return "Testtext"
        case .english: return "Test text"
        }
    }

    @objc func showNormalizedVoiceSample(_ sender: Any?) {
        do {
            let sample = try loadNormalizedVoiceSample()
            let alert = NSAlert()
            alert.messageText = normalizedSampleTitle
            let text = Localization.format(.sampleOriginal, language: language, sample.sourceText, sample.preparedText)
            let notes = sample.warnings.isEmpty
                ? t(.sampleNoWarnings)
                : Localization.format(.sampleWarnings, language: language, sample.warnings.joined(separator: "\n"))
            alert.informativeText = text + notes
            alert.addButton(withTitle: t(.continueWork))
            alert.runModal()
        } catch { showError(error.localizedDescription) }
    }

    func loadNormalizedVoiceSample() throws -> NormalizedVoiceSample {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ruby")
        process.arguments = [runtimeDirectory.appendingPathComponent("srt_gui_job.rb").path,
            "--voice-test-sample", rhythms.indexOfSelectedItem == 1 ? "strict" : "smooth", sessionVoice.speaker]
        var environment = ProcessInfo.processInfo.environment
        environment["SRT_VOICEOVER_DATA_DIR"] = supportDirectory.path
        process.environment = environment
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        pipe.fileHandleForWriting.closeFile()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let result = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sourceSRT = result["source_srt"] as? String,
              let sourceText = result["source_text"] as? String,
              let preparedText = result["text"] as? String,
              let fingerprint = result["preparation_fingerprint"] as? String else {
            throw NSError(domain: "SRTVoiceover", code: 3,
                userInfo: [NSLocalizedDescriptionKey: String(decoding: data, as: UTF8.self)])
        }
        return NormalizedVoiceSample(sourceSRT: sourceSRT, sourceText: sourceText,
            preparedText: preparedText, warnings: result["warnings"] as? [String] ?? [], fingerprint: fingerprint)
    }

    @objc func revealReports(_ sender: Any?) {
        let selected = table.selectedRow
        let report = jobs.indices.contains(selected) ? jobs[selected].report : nil
        switch QueueReportNavigation.target(selectedReport: report, reportsDirectory: reportsDirectory) {
        case .report(let report):
            lastReportOpenTarget = report
            lastReportOpenSucceeded = NSWorkspace.shared.open(report)
        case .directory(let directory):
            lastReportOpenTarget = directory
            lastReportOpenSucceeded = NSWorkspace.shared.open(directory)
        case .unavailable:
            lastReportOpenTarget = nil
            lastReportOpenSucceeded = false
            appendLog(Localization.format(.reportsNotReady, language: language, reportsDirectory.path))
        }
    }

    func cleanupReports() {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ruby")
        process.arguments = [runtimeDirectory.appendingPathComponent("srt_gui_job.rb").path,
                             "--cleanup-reports", "--reports-dir", reportsDirectory.path]
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run(); pipe.fileHandleForWriting.closeFile() }
        catch { appendLog(Localization.format(.reportsCleanupError, language: language, error.localizedDescription)); return }
        DispatchQueue.global(qos: .utility).async {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            pipe.fileHandleForReading.closeFile()
            process.waitUntilExit()
            DispatchQueue.main.async {
                if process.terminationStatus != 0 {
                    self.appendLog(Localization.format(.cleanupDiagnostic, language: self.language,
                        String(decoding: data, as: UTF8.self)))
                }
            }
        }
    }

    @objc func formatChanged(_ sender: Any?) {
        let format = AudioFormat.allCases[max(0, formats.indexOfSelectedItem)]
        formatHint.stringValue = format == .m4a ? aacFormatHint : t(.formatWAVHint)
        if !automatedTest {
            UserDefaults.standard.set(format.rawValue, forKey: "outputAudioFormat")
        }
    }

    var aacFormatHint: String {
        switch language {
        case .russian: return "AAC-LC · MP4 без перекодирования · 128 кбит/с · 48 кГц"
        case .german: return "AAC-LC · MP4 ohne Neukodierung · 128 kbit/s · 48 kHz"
        case .english: return "AAC-LC · MP4 without re-encoding · 128 kb/s · 48 kHz"
        }
    }

    func beginWork(test: Bool) {
        cleanupVoiceTest()
        isBusy = true
        isTest = test
        stopRequested = false
        sessionVoice = Voice.all[max(0, voices.indexOfSelectedItem)]
        sessionFormat = AudioFormat.allCases[max(0, formats.indexOfSelectedItem)]
        sessionRhythm = SpeechRhythm.allCases[max(0, rhythms.indexOfSelectedItem)]
        sessionDownloads = destinations.indexOfSelectedItem == 1 ?
            URL(fileURLWithPath: argument("--test-downloads") ?? NSHomeDirectory() + "/Downloads", isDirectory: true) : nil
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], reason: t(.activityReason))
        progress.doubleValue = 0
        refresh()
    }

    @objc func startQueue(_ sender: Any?) {
        guard !isBusy else { return }
        runIndices = jobs.indices.filter { jobs[$0].state != .done && jobs[$0].state != .skipped }
        guard !runIndices.isEmpty else { return }
        sessionRhythm = SpeechRhythm.allCases[max(0, rhythms.indexOfSelectedItem)]
        sessionFormat = AudioFormat.allCases[max(0, formats.indexOfSelectedItem)]
        beginWork(test: false)
        status.stringValue = t(.preparing)
        appendLog(t(.queuePreflightLog))
        preflightQueue(runIndices) { [weak self] succeeded in
            guard let self else { return }
            self.preflightProcess = nil
            guard !self.stopRequested else {
                self.recordPreflightCancellation(self.runIndices) { self.endWork() }
                return
            }
            guard succeeded else { self.endWork(); return }
            self.preflightFailedCount = self.runIndices.filter { self.jobs[$0].state == .failed }.count
            let readyCount = self.runIndices.count - self.preflightFailedCount
            let continueQueue = { [weak self] accepted in
                guard let self else { return }
                guard !self.stopRequested else {
                    self.recordPreflightCancellation(self.runIndices) { self.endWork() }
                    return
                }
                guard accepted else {
                    self.preflightFailedCount = 0
                    self.endWork()
                    return
                }
                self.runIndices = self.runIndices.filter { self.jobs[$0].state != .failed }
                guard !self.runIndices.isEmpty else {
                    let failed = self.preflightFailedCount
                    self.status.stringValue = Localization.format(.queueCompleteNoFiles, language: self.language, String(failed), self.reportsDirectory.path)
                    self.endWork()
                    return
                }
                for i in self.runIndices { self.jobs[i].state = .waiting; self.jobs[i].detail = self.t(.queued); self.jobs[i].progress = 0; self.jobs[i].warnings = 0 }
                self.requestNotifications()
                self.appendLog(Localization.format(.queueStartedLog, language: self.language,
                    String(self.runIndices.count), self.voices.titleOfSelectedItem ?? "",
                    self.sessionFormat.title(self.language), self.sessionRhythm.title(self.language)))
                self.runPosition = 0
                self.nextJob()
            }
            if self.preflightFailedCount > 0 && readyCount > 0 {
                self.confirmReadyFiles(failed: self.preflightFailedCount, ready: readyCount, completion: continueQueue)
            } else {
                continueQueue(true)
            }
        }
    }

    func confirmReadyFiles(failed: Int, ready: Int, completion: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = t(.preflightChoiceTitle)
        alert.informativeText = Localization.format(.preflightChoiceMessage, language: language,
            String(failed), String(ready))
        alert.alertStyle = .warning
        alert.addButton(withTitle: t(.preflightRunReady))
        alert.addButton(withTitle: t(.preflightReview))
        alert.beginSheetModal(for: window) { response in
            completion(response == .alertFirstButtonReturn)
        }
        if automatedTest, let choice = argument("--test-preflight-choice"),
           ["run-ready", "review"].contains(choice) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                if let path = argument("--preflight-choice-snapshot") {
                    self.capture(to: path, view: alert.window.contentView, exitAfter: false)
                }
                let index = choice == "run-ready" ? 0 : 1
                self.window.endSheet(alert.window,
                    returnCode: NSApplication.ModalResponse(rawValue: 1000 + index))
            }
        }
    }

    func preflightQueue(_ indices: [Int], completion: @escaping (Bool) -> Void) {
        queueInputDigests.removeAll()
        queuePreparationFingerprints.removeAll()
        let process = Process()
        let pipe = Pipe()
        let requestID = UUID().uuidString.lowercased()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ruby")
        process.arguments = [runtimeDirectory.appendingPathComponent("srt_gui_job.rb").path,
            "--preflight", "--reports-dir", reportsDirectory.path, "--format", sessionFormat.rawValue,
            sessionRhythm.rawValue, "--speaker", sessionVoice.speaker, "--request-id", requestID] + indices.map { jobs[$0].input.path }
        process.currentDirectoryURL = runtimeDirectory
        var environment = ProcessInfo.processInfo.environment
        environment["SRT_VOICEOVER_DATA_DIR"] = supportDirectory.path
        environment["SRT_VOICEOVER_SILERO_DIR"] = sileroEnvironment.path
        environment["SRT_VOICEOVER_MODEL_PATH"] = sileroModel.path
        if let ffmpeg = selectedFFmpegPath { environment["SRT_VOICEOVER_FFMPEG"] = ffmpeg }
        process.environment = environment
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            pipe.fileHandleForWriting.closeFile()
            preflightProcess = process
            if argument("--test-cancel-during-preflight") != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    guard self.preflightProcess != nil else { return }
                    self.stop(nil)
                }
            }
        }
        catch {
            appendLog(t(.preflightWholeFailed))
            appendLog(Localization.format(.technicalDetails, language: language, error.localizedDescription))
            completion(false)
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            DispatchQueue.main.async {
                self?.finishPreflight(indices, requestID: requestID, data: data,
                    exitCode: process.terminationStatus, completion: completion)
            }
        }
    }

    func recordPreflightCancellation(_ indices: [Int], completion: @escaping () -> Void) {
        guard !indices.isEmpty else { completion(); return }
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ruby")
        process.arguments = [runtimeDirectory.appendingPathComponent("srt_gui_job.rb").path,
            "--preflight-cancelled-reports", "--reports-dir", reportsDirectory.path]
        for index in indices where jobs.indices.contains(index) {
            let input = jobs[index].input
            let output = VoiceoverFiles.output(for: input, format: sessionFormat.rawValue, downloads: sessionDownloads)
            process.arguments?.append(contentsOf: ["--item", input.path, "--output", output.path])
            jobs[index].state = .stopped
            jobs[index].detail = t(.resultStopped)
        }
        process.standardOutput = pipe
        process.standardError = pipe
        refresh()
        do {
            try process.run()
            pipe.fileHandleForWriting.closeFile()
        } catch {
            appendLog(Localization.format(.technicalDetails, language: language, error.localizedDescription))
            completion()
            return
        }
        DispatchQueue.global(qos: .utility).async {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            pipe.fileHandleForReading.closeFile()
            process.waitUntilExit()
            DispatchQueue.main.async {
                guard process.terminationStatus == 0,
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      object["protocol_version"] as? Int == 1,
                      object["type"] as? String == "preflight_cancellation_reports",
                      let files = object["files"] as? [[String: Any]], files.count == indices.count else {
                    self.appendLog(self.t(.preflightWholeFailed))
                    self.appendLog(Localization.format(.technicalDetails, language: self.language,
                        String(decoding: data, as: UTF8.self)))
                    completion()
                    return
                }
                for file in files {
                    guard let input = file["file"] as? String,
                          let report = file["report"] as? String,
                          file["status"] as? String == "cancelled" else { continue }
                    if let index = indices.first(where: { self.jobs[$0].input.path == input }) {
                        self.jobs[index].report = URL(fileURLWithPath: report)
                    }
                    self.appendLog(Localization.format(.preflightCancelledReport, language: self.language,
                        URL(fileURLWithPath: input).lastPathComponent, report))
                }
                self.refresh()
                completion()
            }
        }
    }

    func finishPreflight(_ indices: [Int], requestID: String, data: Data, exitCode: Int32,
                         completion: @escaping (Bool) -> Void) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["protocol_version"] as? Int == 1,
              object["type"] as? String == "preflight",
              object["request_id"] as? String == requestID,
              let files = object["files"] as? [[String: Any]] else {
            appendLog(t(.preflightWholeFailed))
            appendLog(Localization.format(.technicalDetails, language: language,
                String(decoding: data, as: UTF8.self)))
            completion(false)
            return
        }
        var failed = false
        for file in files {
            let path = file["file"] as? String ?? t(.unknownFileName)
            if let digest = file["sha256"] as? String { queueInputDigests[path] = digest }
            if let fingerprint = file["preparation_fingerprint"] as? String { queuePreparationFingerprints[path] = fingerprint }
            if let issues = file["issues"] as? [[String: Any]], !issues.isEmpty {
                failed = true
                if let index = indices.first(where: { jobs[$0].input.path == path }) {
                    jobs[index].state = .failed
                    jobs[index].detail = t(.preflightFailed)
                    if let report = file["report"] as? String { jobs[index].report = URL(fileURLWithPath: report) }
                }
                for issue in issues {
                    let codepoint = (issue["codepoint"] as? String).map { " · \($0)" } ?? ""
                    appendLog(Localization.format(.preflightIssue, language: language,
                        URL(fileURLWithPath: path).lastPathComponent,
                        issue["cue"] as? String ?? "?",
                        issue["timestamps"] as? String ?? "—",
                        Localization.preflightIssueLabel(issue["code"] as? String ?? "preflight_error", language: language), codepoint))
                    appendLog(Localization.preflightIssueAction(
                        issue["code"] as? String ?? "preflight_error", language: language))
                    if let explanation = issue["explanation"] as? String, !explanation.isEmpty {
                        appendLog(Localization.format(.technicalDetails, language: language, explanation))
                    }
                }
            } else { appendLog(Localization.format(.preflightPassedFile, language: language, path)) }
        }
        if exitCode != 0 && !failed {
            status.stringValue = t(.preflightWholeFailed)
            completion(false)
            return
        }
        completion(true)
    }

    func nextJob() {
        guard !stopRequested && runPosition < runIndices.count else { endWork(); return }
        let index = runIndices[runPosition]
        jobs[index].state = .running
        jobs[index].detail = t(.preparing)
        activeRow = index
        let input = jobs[index].input
        let output = VoiceoverFiles.output(for: input, format: sessionFormat.rawValue, downloads: sessionDownloads)
        eta.stringValue = t(.etaInitial)
        status.stringValue = Localization.format(.fileProgress, language: language, String(runPosition + 1), String(runIndices.count), input.lastPathComponent)
        refresh()
        launch(input: input, output: output)
    }

    @objc func testVoice(_ sender: Any?) {
        guard !isBusy else { return }
        do {
            // Every preview is generated from scratch.  Reusing a cached audio
            // file could play a previous voice after the user changes it.
            let temporary = FileManager.default.temporaryDirectory
                .appendingPathComponent("SRTVoiceover-VoiceTest-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
            let sample = try loadNormalizedVoiceSample()
            let input = temporary.appendingPathComponent("Проверка голоса.ru.srt")
            try sample.sourceSRT.write(to: input, atomically: true, encoding: .utf8)
            queuePreparationFingerprints[input.path] = sample.fingerprint
            beginWork(test: true)
            voiceTestDirectory = temporary
            activeRow = nil
            status.stringValue = Localization.format(.testVoiceProgress, language: language, voices.titleOfSelectedItem ?? "")
            launch(input: input, output: temporary.appendingPathComponent("Проверка.\(sessionFormat.rawValue)"))
        } catch { showError(error.localizedDescription) }
    }

    func launch(input: URL, output: URL) {
        activeOutput = nil
        activeError = nil
        activeSkipped = false
        activeWarnings = 0
        let id = UUID()
        activeID = id
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ruby")
        var arguments = [runtimeDirectory.appendingPathComponent("srt_gui_job.rb").path,
                             "--voice", sessionVoice.engine, "--speaker", sessionVoice.speaker,
                             "--format", sessionFormat.rawValue,
                             "--rhythm", sessionRhythm.rawValue,
                             "--conflict", isTest ? "copy" : "ask",
                             "--reports-dir", reportsDirectory.path,
                             "--output", output.path,
                             "--job-id", id.uuidString.lowercased()]
        if automatedTest, let engine = argument("--test-engine") { arguments += ["--engine", engine] }
        if let digest = queueInputDigests[input.path] { arguments += ["--expected-sha256", digest] }
        if let fingerprint = queuePreparationFingerprints[input.path] { arguments += ["--expected-preparation-fingerprint", fingerprint] }
        arguments.append(input.path)
        process.arguments = arguments
        process.currentDirectoryURL = runtimeDirectory
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:" + (environment["PATH"] ?? "")
        environment["LANG"] = "en_US.UTF-8"
        environment["SRT_VOICEOVER_DATA_DIR"] = supportDirectory.path
        environment["SRT_VOICEOVER_SILERO_DIR"] = sileroEnvironment.path
        environment["SRT_VOICEOVER_MODEL_PATH"] = sileroModel.path
        if let ffmpeg = selectedFFmpegPath { environment["SRT_VOICEOVER_FFMPEG"] = ffmpeg }
        process.environment = environment
        process.standardOutput = pipe
        process.standardError = pipe
        let inputPipe = Pipe()
        process.standardInput = inputPipe
        activeInputPipe = inputPipe
        activeProcess = process
        appendLog(Localization.format(.jobStartedLog, language: language, input.path))
        do {
            guard FileManager.default.fileExists(atPath: runtimeDirectory.appendingPathComponent("srt_gui_job.rb").path) else {
                throw NSError(domain: "SRTVoiceover", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: t(.missingRuntimeError)])
            }
            try process.run()
            inputPipe.fileHandleForReading.closeFile()
            pipe.fileHandleForWriting.closeFile()
        } catch {
            activeError = error.localizedDescription
            DispatchQueue.main.async { self.finished(id: id, exitCode: 1) }
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            var pending = Data()
            while true {
                let data = pipe.fileHandleForReading.availableData
                if data.isEmpty { break }
                pending.append(data)
                while let newline = pending.firstIndex(of: 10) {
                    let line = Data(pending[..<newline])
                    pending.removeSubrange(...newline)
                    DispatchQueue.main.async { self.consume(line, id: id) }
                }
            }
            if !pending.isEmpty {
                let remainder = pending
                DispatchQueue.main.async { self.consume(remainder, id: id) }
            }
            pipe.fileHandleForReading.closeFile()
            process.waitUntilExit()
            let code = process.terminationStatus
            DispatchQueue.main.async { self.finished(id: id, exitCode: code) }
        }
    }

    func consume(_ data: Data, id: UUID) {
        guard id == activeID else { return }
        guard let event = WorkerEventProtocol.decode(data, expectedJobID: id),
              let type = event["type"] as? String else {
            appendLog(t(.unknownChildEvent))
            appendLog(Localization.format(.technicalDetails, language: language,
                String(decoding: data, as: UTF8.self)))
            return
        }
        switch type {
        case "conflict":
            presentConflict(event, id: id)
        case "skipped":
            activeSkipped = true
            appendLog(t(.resultSkipped))
        case "progress":
            let percent = (event["percent"] as? Double) ?? 0
            let current = event["current"] as? Int ?? 0
            let total = event["total"] as? Int ?? 0
            let stage = event["stage"] as? String ?? "speech"
            if automatedTest, argument("--test-cancel-at-stage") == stage, !stopRequested {
                print("GUI_TEST_CANCEL_STAGE \(stage)")
                fflush(stdout)
                stop(nil)
            }
            let seconds = event["eta_seconds"] as? Double
            switch stage {
            case "synthesis":
                eta.stringValue = seconds.map { VoiceoverFiles.remaining($0, language: language) + " " + t(.etaSynthesis) } ?? t(.etaSynthesis)
            case "assembly":
                eta.stringValue = seconds.map { VoiceoverFiles.remaining($0, language: language) + " " + t(.etaAssembly) } ?? t(.etaAssembly)
            case "encode": eta.stringValue = t(.progressEncode)
            case "verify": eta.stringValue = t(.progressVerify)
            default:
                if let seconds { eta.stringValue = VoiceoverFiles.remaining(seconds, language: language) + " " + t(.etaFile) }
            }
            let detail: String
            switch stage {
            case "synthesis": detail = Localization.format(.progressSynthesis, language: language, String(current), String(total)) + " · \(Int(percent))%"
            case "assembly": detail = Localization.format(.progressAssembly, language: language, String(current), String(total)) + " · \(Int(percent))%"
            case "encode": detail = t(.progressEncode) + " · \(Int(percent))%"
            case "verify": detail = t(.progressVerify) + " · \(Int(percent))%"
            default: detail = Localization.format(.progressSpeech, language: language, String(current), String(total)) + " · \(Int(percent))%"
            }
            if let i = activeRow {
                jobs[i].progress = percent
                jobs[i].detail = detail
                progress.doubleValue = (Double(runPosition) * 100 + percent) / Double(max(1, runIndices.count))
                table.reloadData(forRowIndexes: IndexSet(integer: i), columnIndexes: IndexSet(integer: 1))
            } else { progress.doubleValue = percent }
        case "done":
            if let path = event["output"] as? String { activeOutput = URL(fileURLWithPath: path) }
            if let report = event["report"] as? String, let i = activeRow {
                jobs[i].report = URL(fileURLWithPath: report)
            }
            activeWarnings = event["warnings"] as? Int ?? activeWarnings
        case "warning":
            activeWarnings += 1
            switch event["code"] as? String {
            case "tempo_fit":
                let first = String(event["first_cue"] as? Int ?? 0)
                let last = String(event["last_cue"] as? Int ?? 0)
                let factor = String(format: "%.2f", event["factor"] as? Double ?? 1.0)
                appendLog("⚠️ " + Localization.format(.warningTempoFit, language: language, first, last, factor))
            case "silent_cues":
                let cues = (event["cues"] as? [Int] ?? []).map { String($0) }.joined(separator: ", ")
                appendLog("⚠️ " + Localization.format(.warningSilentCues, language: language, cues))
            default:
                appendLog(t(.unknownChildEvent))
            }
        case "error":
            activeError = t(.voiceoverFailure)
            appendLog(activeError!)
            if let diagnostic = event["diagnostic"] as? String, !diagnostic.isEmpty {
                appendLog(Localization.format(.technicalDetails, language: language, diagnostic))
            }
        case "status":
            let code = event["code"] as? String ?? ""
            switch code {
            case "preparing_voice": status.stringValue = t(.statusPreparingVoice)
            case "loading_model": status.stringValue = t(.statusLoadingModel)
            case "synthesis_started":
                status.stringValue = Localization.format(.statusSynthesisStarted, language: language,
                    String(event["cue_count"] as? Int ?? 0), String(event["phrase_count"] as? Int ?? 0))
            case "saving_aac": status.stringValue = t(.statusSavingAAC)
            case "aac_hardware_fallback": status.stringValue = t(.statusAACFallback)
            case "verifying_aac": status.stringValue = t(.statusVerifyingAAC)
            case "synthesis_finished": break
            default: appendLog(t(.unknownChildEvent))
            }
        case "diagnostic":
            if let detail = event["diagnostic"] as? String {
                appendLog(Localization.format(.technicalDetails, language: language, detail))
            }
        case "cancelled": appendLog(t(.resultStopped))
        case "report":
            if let report = event["report"] as? String, let i = activeRow {
                jobs[i].report = URL(fileURLWithPath: report)
                table.reloadData(forRowIndexes: IndexSet(integer: i), columnIndexes: IndexSet(integersIn: 0..<table.numberOfColumns))
                refreshButtons()
            }
        default:
            appendLog(t(.unknownChildEvent))
        }
    }

    func finished(id: UUID, exitCode: Int32) {
        guard id == activeID else { return }
        activeProcess = nil
        activeID = nil
        activeInputPipe?.fileHandleForWriting.closeFile()
        activeInputPipe = nil
        if let alert = conflictAlert { window.endSheet(alert.window, returnCode: .abort); conflictAlert = nil }
        if let output = activeOutput, exitCode == 0 {
            lastOutput = output
            if let i = activeRow {
                jobs[i].state = .done
                jobs[i].progress = 100
                jobs[i].detail = t(.resultDone) + " · \(sessionFormat == .m4a ? "AAC" : "WAV") · \(voices.titleOfSelectedItem ?? "")"
                jobs[i].output = output
                jobs[i].warnings = activeWarnings
                if activeWarnings > 0 {
                    jobs[i].detail = Localization.format(.savedOutputWithWarnings, language: language, String(activeWarnings))
                }
            }
            appendLog(Localization.format(.savedOutput, language: language, output.path))
        } else if let i = activeRow, activeSkipped && exitCode == 0 {
            jobs[i].state = .skipped
            jobs[i].detail = t(.resultSkipped)
        } else if let i = activeRow {
            jobs[i].state = stopRequested ? .stopped : .failed
            jobs[i].detail = stopRequested ? t(.resultStopped) : t(.resultFailed)
            if !stopRequested {
                let reason = activeError ?? Localization.format(.exitCode, language: language, String(exitCode))
                appendLog(Localization.format(.fileNotReady, language: language, reason))
            }
        }
        if isTest {
            let testOutput = activeOutput
            let error = activeError
            let stopped = stopRequested
            endWork()
            if exitCode == 0, let output = testOutput, !stopped {
                do {
                    player = try AVAudioPlayer(contentsOf: output)
                    player?.delegate = self
                    player?.play()
                    status.stringValue = activeWarnings > 0 ? t(.testPlayingWarnings) : t(.testPlaying)
                } catch {
                    cleanupVoiceTest()
                    showError(Localization.format(.testPlaybackFailed, language: language, error.localizedDescription))
                }
            } else if !stopped {
                cleanupVoiceTest()
                showError(error ?? t(.testCreateFailed))
            }
        } else {
            runPosition += 1
            refresh()
            nextJob()
        }
    }

    func presentConflict(_ event: [String: Any], id: UUID) {
        guard !stopRequested, let path = event["path"] as? String,
              let requestID = event["request_id"] as? String else { return }
        let canReplace = event["can_replace"] as? Bool ?? false
        eta.stringValue = t(.conflictWait)
        let alert = NSAlert()
        alert.messageText = t(.conflictTitle)
        alert.informativeText = Localization.format(.conflictMessage, language: language, path)
        alert.addButton(withTitle: t(.conflictCopy))
        var actions = ["copy"]
        if canReplace { alert.addButton(withTitle: t(.conflictReplace)); actions.append("replace") }
        alert.addButton(withTitle: t(.conflictSkip)); actions.append("skip")
        alert.addButton(withTitle: t(.conflictStop)); actions.append("stop")
        alert.buttons.last?.keyEquivalent = "\u{1b}"
        conflictAlert = alert
        alert.beginSheetModal(for: window) { response in
            self.conflictAlert = nil
            guard self.activeID == id, !self.stopRequested else { return }
            let index = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
            guard actions.indices.contains(index), actions[index] != "stop" else { self.stop(nil); return }
            do {
                let data = try JSONSerialization.data(withJSONObject: ["request_id": requestID, "action": actions[index]])
                try self.activeInputPipe?.fileHandleForWriting.write(contentsOf: data + Data([10]))
                self.eta.stringValue = self.t(.conflictContinue)
            } catch {
                self.appendLog(Localization.format(.resolveChoiceError, language: self.language, error.localizedDescription))
                self.stop(nil)
            }
        }
        // Test-only automation exercises the same actual sheet and IPC path.
        if automatedTest, let choice = argument("--test-conflict"), let index = actions.firstIndex(of: choice) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                if let path = argument("--conflict-snapshot") {
                    self.capture(to: path, view: alert.window.contentView, exitAfter: false)
                }
                self.window.endSheet(alert.window, returnCode: NSApplication.ModalResponse(rawValue: 1000 + index))
            }
        }
    }

    func requestNotifications() {
        guard !automatedTest, notifyOnFinish.state == .on else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            DispatchQueue.main.async {
                if let error { self.appendLog(Localization.format(.notificationError, language: self.language, error.localizedDescription)) }
                else if !granted { self.appendLog(self.t(.notificationDenied)) }
            }
        }
    }

    func sendCompletionNotification(_ summary: String) {
        guard !automatedTest, notifyOnFinish.state == .on else { return }
        let content = UNMutableNotificationContent()
        content.title = t(.notificationTitle)
        content.body = summary
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { DispatchQueue.main.async {
                self.appendLog(Localization.format(.notificationDisplayError, language: self.language, error.localizedDescription))
            } }
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                           withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func endWork() {
        let wasTest = isTest
        isBusy = false
        activeRow = nil
        if let token = activity { ProcessInfo.processInfo.endActivity(token) }
        activity = nil
        eta.stringValue = stopRequested ? t(.stopEta) : ""
        if stopRequested {
            status.stringValue = t(.resultStopped)
        } else if !wasTest {
            let completed = runIndices.filter { jobs[$0].state == .done }.count
            let failed = preflightFailedCount + runIndices.filter { jobs[$0].state == .failed }.count
            let skipped = runIndices.filter { jobs[$0].state == .skipped }.count
            let warnings = runIndices.reduce(0) { $0 + jobs[$1].warnings }
            progress.doubleValue = 100
            status.stringValue = Localization.format(.resultSummary, language: language, String(completed), String(skipped), String(failed)) + (warnings > 0 ? Localization.format(.resultWarnings, language: language, String(warnings)) : "")
            sendCompletionNotification(status.stringValue)
        }
        refresh()
        if quitting { NSApp.reply(toApplicationShouldTerminate: true) }
        if argument("--integration-test") != nil && !wasTest {
            let ok = !runIndices.isEmpty && runIndices.allSatisfy { jobs[$0].state == .done || jobs[$0].state == .skipped }
            print("GUI_QUEUE_TEST \(ok ? "OK" : "FAILED") jobs=\(runIndices.count)")
            fflush(stdout)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                if let path = argument("--result-snapshot") { self.capture(to: path, exitCode: ok ? 0 : 1) }
                exit(ok ? 0 : 1)
            }
        }
    }
    @objc func stop(_ sender: Any?) {
        guard isBusy && !stopRequested else { return }
        stopRequested = true
        status.stringValue = t(.stopStatus)
        preflightProcess?.terminate()
        activeProcess?.terminate()
        if let alert = conflictAlert { window.endSheet(alert.window, returnCode: .abort); conflictAlert = nil }
        refreshButtons()
    }
    @objc func reveal(_ sender: Any?) {
        let index = table.selectedRow
        let output = jobs.indices.contains(index) ? (jobs[index].output ?? lastOutput) : lastOutput
        if let output { NSWorkspace.shared.activateFileViewerSelecting([output]) }
    }
    func refresh() { table.reloadData(); refreshButtons() }
    func refreshButtons() {
        addButton.isEnabled = !isBusy
        folderButton.isEnabled = !isBusy
        clearButton.isEnabled = !isBusy && !jobs.isEmpty
        removeButton.isEnabled = !isBusy && table.numberOfSelectedRows > 0
        voices.isEnabled = !isBusy
        formats.isEnabled = !isBusy
        rhythms.isEnabled = !isBusy
        destinations.isEnabled = !isBusy
        notifyOnFinish.isEnabled = !isBusy
        testButton.isEnabled = !isBusy
        startButton.isEnabled = !isBusy && jobs.contains { $0.state != .done && $0.state != .skipped }
        stopButton.isEnabled = isBusy && !stopRequested
        revealButton.isEnabled = lastOutput != nil
        let selectedReport = jobs.indices.contains(table.selectedRow) ? jobs[table.selectedRow].report : nil
        let reportTarget = QueueReportNavigation.target(selectedReport: selectedReport, reportsDirectory: reportsDirectory)
        if case .report = reportTarget {
            reportsButton.title = t(.openSelectedReport)
        } else {
            reportsButton.title = t(.reports)
        }
        reportsButton.isEnabled = reportTarget != .unavailable
    }
    func appendLog(_ text: String) {
        let combined = log.string + text + "\n"
        log.string = String(combined.suffix(30000))
        log.scrollToEndOfDocument(nil)
    }
    func showError(_ text: String) {
        status.stringValue = t(.errorStatus)
        appendLog(text)
        let alert = NSAlert()
        alert.messageText = t(.errorTitle)
        let technicalDetails = Localization.format(.technicalDetails, language: language, text)
        alert.informativeText = t(.errorMessage) + "\n\n" + technicalDetails
        alert.beginSheetModal(for: window)
    }
    func cleanupVoiceTest() {
        player?.stop()
        player = nil
        if let directory = voiceTestDirectory {
            try? FileManager.default.removeItem(at: directory)
            voiceTestDirectory = nil
        }
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.cleanupVoiceTest() }
    }
    func applicationWillTerminate(_ notification: Notification) { cleanupVoiceTest() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if isBusy { NSApp.terminate(nil); return false }
        return true
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard isBusy else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = t(.exitTitle)
        alert.informativeText = t(.exitMessage)
        alert.addButton(withTitle: t(.continueWork))
        alert.addButton(withTitle: t(.stopAndQuit))
        guard alert.runModal() == .alertSecondButtonReturn else { return .terminateCancel }
        quitting = true
        stop(nil)
        return .terminateLater
    }
    func capture(to path: String, exitCode: Int32 = 0, view snapshotView: NSView? = nil, exitAfter: Bool = true) {
        guard let view = snapshotView ?? window.contentView else { exit(1) }
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(1) }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        do {
            guard let data = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
            try data.write(to: URL(fileURLWithPath: path))
            print("UI_SNAPSHOT_OK \(path)")
            if exitAfter { exit(exitCode) }
        } catch { print(error); exit(1) }
    }
}

MainActor.assumeIsolated {
    signal(SIGPIPE, SIG_IGN)
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.setActivationPolicy(.regular)
    app.delegate = delegate
    app.run()
}
