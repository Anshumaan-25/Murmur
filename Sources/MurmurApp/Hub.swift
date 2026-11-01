import AppKit
import AVFoundation
import Speech
import CoreAudio
import ServiceManagement
import UniformTypeIdentifiers
import MurmurCore

final class ActionButton: NSButton {
    var perform: (() -> Void)?
    convenience init(_ title: String, _ action: @escaping () -> Void) {
        self.init(title: title, target: nil, action: nil); perform = action; target = self; self.action = #selector(invoke)
        bezelStyle = .rounded
    }
    override func draw(_ dirtyRect: NSRect) {
        let background = isHighlighted ? NSColor.controlAccentColor.withAlphaComponent(0.35) : NSColor.controlAccentColor.withAlphaComponent(0.15)
        background.setFill(); NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 7, yRadius: 7).fill()
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.labelColor]
        let text = title as NSString; let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2), withAttributes: attributes)
    }
    @objc func invoke() { perform?() }
}
final class FlippedStack: NSStackView { override var isFlipped: Bool { true } }
final class NavigationControl: NSSegmentedControl {
    override func draw(_ dirtyRect: NSRect) {
        let width = bounds.width / CGFloat(max(1, segmentCount))
        for segment in 0..<segmentCount {
            let rectangle = NSRect(x: CGFloat(segment) * width, y: 0, width: width, height: bounds.height).insetBy(dx: 2, dy: 1)
            (segment == selectedSegment ? NSColor.controlAccentColor.withAlphaComponent(0.2) : NSColor.controlBackgroundColor).setFill()
            NSBezierPath(roundedRect: rectangle, xRadius: 7, yRadius: 7).fill()
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: segment == selectedSegment ? .semibold : .regular), .foregroundColor: NSColor.labelColor]
            let text = (label(forSegment: segment) ?? "") as NSString; let size = text.size(withAttributes: attributes)
            text.draw(at: NSPoint(x: rectangle.midX - size.width / 2, y: rectangle.midY - size.height / 2), withAttributes: attributes)
        }
    }
}
@MainActor final class Hub: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    let controller: DictationController
    let content = NSView()
    let pages = NSStackView()
    var page = 0
    var previousApp: NSRunningApplication?
    let navigation = NavigationControl(labels: ["History", "Vocabulary", "Snippets", "Styles", "Settings"], trackingMode: .selectOne, target: nil, action: nil)
    let statsLabel = NSTextField(labelWithString: "")
    let statusLabel = NSTextField(labelWithString: "Ready · Control Option Space")
    var table = NSTableView()
    var details = NSTextView()
    var search = NSSearchField()
    var rows: [Utterance] = []
    var words = NSTextView()
    var snippetRows: [(NSTextField, NSTextView)] = []
    var snippetStack: NSStackView?
    var styleRows: [(NSTextField, NSPopUpButton)] = []
    var styleStack: NSStackView?
    var micPicker = NSPopUpButton()
    var micIDs: [AudioDeviceID] = [0]
    var languagePicker = NSPopUpButton()
    var retentionPicker = NSPopUpButton()
    var hotkeyPicker = NSPopUpButton()
    var holdPicker = NSPopUpButton()
    var enginePicker = NSPopUpButton()
    var checks: [String: NSButton] = [:]
    var fields: [String: NSTextField] = [:]
    init(controller: DictationController) {
        self.controller = controller
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 940, height: 710), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Murmur"; window.minSize = NSSize(width: 790, height: 600); window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true; window.contentView = content
        super.init(window: window)
        buildShell(); window.center(); render()
    }
    required init?(coder: NSCoder) { fatalError("Unsupported initializer") }
    func label(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text); field.font = .systemFont(ofSize: size, weight: weight); return field
    }
    func column(_ spacing: CGFloat = 14) -> NSStackView { let stack = FlippedStack(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = spacing; return stack }
    func row(_ views: [NSView]) -> NSStackView { let stack = NSStackView(views: views); stack.orientation = .horizontal; stack.spacing = 12; return stack }
    func buildShell() {
        statusLabel.stringValue = "Ready · " + controller.shortcutTitle
        let title = label("Murmur", size: 30, weight: .bold)
        let subtitle = label("A little less typing. Everything stays here.", size: 14)
        subtitle.textColor = .secondaryLabelColor
        let header = row([title, label("  ON DEVICE", size: 10, weight: .semibold)])
        let top = column(8); top.addArrangedSubview(header); top.addArrangedSubview(subtitle)
        navigation.selectedSegment = 0; navigation.target = self; navigation.action = #selector(navigate)
        pages.orientation = .vertical; pages.alignment = .leading; pages.spacing = 16
        let footer = row([statusLabel, ActionButton("Start / stop") { [weak self] in self?.dictateFromHub() }, ActionButton("Cancel") { [weak self] in self?.controller.cancel() }])
        statusLabel.textColor = .secondaryLabelColor; statusLabel.lineBreakMode = .byTruncatingTail
        for view in [top, navigation, pages, footer] { view.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(view) }
        NSLayoutConstraint.activate([
            top.topAnchor.constraint(equalTo: content.topAnchor, constant: 28), top.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 30), top.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -30), top.heightAnchor.constraint(equalToConstant: 68),
            navigation.topAnchor.constraint(equalTo: top.bottomAnchor, constant: 24), navigation.leadingAnchor.constraint(equalTo: top.leadingAnchor), navigation.heightAnchor.constraint(equalToConstant: 32), navigation.widthAnchor.constraint(equalToConstant: 540),
            pages.topAnchor.constraint(equalTo: navigation.bottomAnchor, constant: 24), pages.leadingAnchor.constraint(equalTo: top.leadingAnchor), pages.trailingAnchor.constraint(equalTo: top.trailingAnchor), pages.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -18),
            footer.leadingAnchor.constraint(equalTo: top.leadingAnchor), footer.trailingAnchor.constraint(equalTo: top.trailingAnchor), footer.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20)
        ])
        controller.status = { [weak self] message in self?.statusLabel.stringValue = message }
        controller.received = { [weak self] text in self?.details.string = text }
        controller.changed = { [weak self] in self?.reloadHistory() }
        controller.validationChanged = { [weak self] in if self?.page == 4 { self?.render() } }
    }
    func dictateFromHub() {
        window?.orderOut(nil)
        previousApp?.activate(options: [.activateAllWindows])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.controller.toggle() }
    }
    func show() { if let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp = app }; NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil); if page == 0 { reloadHistory() } }
    @objc func navigate() { page = navigation.selectedSegment; render() }
    func render() {
        for view in pages.arrangedSubviews { pages.removeArrangedSubview(view); view.removeFromSuperview() }
        switch page { case 0: historyPage(); case 1: dictionaryPage(); case 2: snippetsPage(); case 3: stylesPage(); default: settingsPage() }
    }
    func fillWidth(_ view: NSView) { view.translatesAutoresizingMaskIntoConstraints = false; pages.addArrangedSubview(view); view.widthAnchor.constraint(equalTo: pages.widthAnchor).isActive = true }
    func scroll(_ document: NSView, height: CGFloat? = nil) -> NSScrollView {
        let scroller = NSScrollView(); scroller.hasVerticalScroller = true; scroller.drawsBackground = true; scroller.borderType = .bezelBorder; scroller.documentView = document
        if let height { scroller.heightAnchor.constraint(equalToConstant: height).isActive = true }; return scroller
    }
    func editor(_ text: String, height: CGFloat = 180) -> (NSTextView, NSScrollView) {
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 700, height: height)); view.string = text; view.isRichText = false; view.font = .systemFont(ofSize: 14); view.textContainerInset = NSSize(width: 12, height: 10)
        view.isVerticallyResizable = true; view.autoresizingMask = [.width]; view.textContainer?.widthTracksTextView = true
        return (view, scroll(view, height: height))
    }
    func historyPage() {
        rows = (try? controller.history?.records()) ?? []
        let stats = UsageStatistics(rows)
        statsLabel.stringValue = "\(stats.words) words  ·  \(Int(stats.wordsPerMinute)) words/min  ·  \(stats.streak)-day streak"
        statsLabel.font = .systemFont(ofSize: 16, weight: .medium); fillWidth(statsLabel)
        search = NSSearchField(); search.placeholderString = "Search your dictations"; search.delegate = self; fillWidth(search)
        table = NSTableView(); table.usesAlternatingRowBackgroundColors = true; table.rowHeight = 32; table.headerView = NSTableHeaderView()
        for (key, title, width) in [("when", "When", 140.0), ("app", "Application", 180.0), ("text", "Text", 490.0)] { let c = NSTableColumn(identifier: .init(key)); c.title = title; c.width = width; table.addTableColumn(c) }
        table.dataSource = self; table.delegate = self
        let tableScroll = scroll(table, height: 160); fillWidth(tableScroll)
        let (detail, detailScroll) = editor("Your dictations will appear here. Start from the menu bar or use \(controller.shortcutTitle).", height: 130); details = detail; details.isEditable = false; fillWidth(detailScroll)
        fillWidth(row([ActionButton("Copy selected") { [weak self] in self?.copySelected() }, ActionButton("Delete selected") { [weak self] in self?.deleteSelected() }, ActionButton("Export history…") { [weak self] in self?.exportHistory() }]))
    }
    func reloadHistory() {
        guard page == 0 else { return }
        rows = (try? controller.history?.records(search: search.stringValue)) ?? []; table.reloadData()
        let stats = UsageStatistics((try? controller.history?.records()) ?? [])
        statsLabel.stringValue = "\(stats.words) words  ·  \(Int(stats.wordsPerMinute)) words/min  ·  \(stats.streak)-day streak"
    }
    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
    func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
        guard rows.indices.contains(row) else { return nil }; let record = rows[row]
        let value: String
        switch column?.identifier.rawValue { case "when": value = record.timestamp.formatted(date: .abbreviated, time: .shortened); case "app": value = record.application.isEmpty ? "Unknown" : record.application; default: value = record.cleaned }
        let cell = NSTextField(labelWithString: value); cell.lineBreakMode = .byTruncatingTail; cell.font = .systemFont(ofSize: 12); return cell
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard rows.indices.contains(table.selectedRow) else { return }; let r = rows[table.selectedRow]
        details.string = "RECOGNIZED\n\(r.raw)\n\nCLEANED\n\(r.cleaned)\n\nDELIVERED · \(r.outcome)\n\(r.inserted)\n\nReady in \(String(format: "%.2f", r.latency)) s"
    }
    func controlTextDidChange(_ notification: Notification) { if notification.object as? NSSearchField === search { reloadHistory() } }
    func copySelected() { guard rows.indices.contains(table.selectedRow) else { return }; NSPasteboard.general.clearContents(); NSPasteboard.general.setString(rows[table.selectedRow].cleaned, forType: .string); statusLabel.stringValue = "Copied" }
    func deleteSelected() { guard rows.indices.contains(table.selectedRow) else { return }; do { let id = rows[table.selectedRow].id
            try controller.history?.delete(id)
            let audio = Preferences.directory.appendingPathComponent("Recordings").appendingPathComponent(id.uuidString + ".wav")
            if FileManager.default.fileExists(atPath: audio.path) { try FileManager.default.removeItem(at: audio) }
            reloadHistory(); details.string = "Deleted locally." } catch { statusLabel.stringValue = error.localizedDescription } }
    func exportHistory() {
        let save = NSSavePanel(); save.allowedContentTypes = [.json]; save.nameFieldStringValue = "Murmur-history.json"
        if save.runModal() == .OK, let url = save.url { do { let records = try controller.history?.records() ?? []; let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601; try encoder.encode(records).write(to: url, options: .atomic); statusLabel.stringValue = "History exported" } catch { statusLabel.stringValue = error.localizedDescription } }
    }
    func dictionaryPage() {
        fillWidth(label("Names worth getting right", size: 22, weight: .semibold))
        fillWidth(label("Add a name or term on each line. Murmur uses these as recognition hints and keeps their capitalization."))
        let terms = (try? controller.history?.dictionary()) ?? []
        let (view, scroller) = editor(terms.joined(separator: "\n"), height: 260); words = view; fillWidth(scroller)
        fillWidth(ActionButton("Save vocabulary") { [weak self] in guard let self else { return }; do { try self.controller.history?.setDictionary(self.words.string.components(separatedBy: .newlines)); self.statusLabel.stringValue = "Vocabulary saved" } catch { self.statusLabel.stringValue = error.localizedDescription } })
    }
    func snippetsPage() {
        snippetRows = []; fillWidth(label("A few words, a longer message", size: 22, weight: .semibold))
        fillWidth(label("Say a trigger by itself to insert its full text. Expansions preserve your line breaks."))
        let stack = column(16); snippetStack = stack
        let values = (try? controller.history?.values(table: "expansions")) ?? [:]
        for key in values.keys.sorted() { addSnippet(key, value: values[key] ?? "") }
        if values.isEmpty { addSnippet("", value: "") }
        let scroller = scroll(stack, height: 280); fillWidth(scroller)
        fillWidth(row([ActionButton("Add expansion") { [weak self] in self?.addSnippet("", value: "") }, ActionButton("Save expansions") { [weak self] in self?.saveSnippets() }]))
    }
    func addSnippet(_ trigger: String, value: String) {
        guard let stack = snippetStack else { return }
        let field = NSTextField(string: trigger); field.placeholderString = "Spoken trigger"; field.widthAnchor.constraint(equalToConstant: 200).isActive = true
        let (text, scroller) = editor(value, height: 76); scroller.widthAnchor.constraint(equalToConstant: 535).isActive = true
        let container = row([field, scroller]); stack.addArrangedSubview(container); snippetRows.append((field, text))
        stack.layoutSubtreeIfNeeded(); stack.frame.size = NSSize(width: 790, height: CGFloat(snippetRows.count) * 100)
    }
    func saveSnippets() {
        var values: [String: String] = [:]
        for (field, text) in snippetRows { let trigger = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines); if !trigger.isEmpty { if values[trigger.lowercased()] != nil { statusLabel.stringValue = "Each spoken trigger must be unique."; return }; values[trigger.lowercased()] = text.string } }
        do { try controller.history?.setValues(values, table: "expansions"); statusLabel.stringValue = "Expansions saved. Clear a trigger to remove its entry." } catch { statusLabel.stringValue = error.localizedDescription }
    }
    func stylesPage() {
        styleRows = []; fillWidth(label("A voice for each app", size: 22, weight: .semibold))
        fillWidth(label("Choose neutral, formal, or casual wording for an application. Neutral keeps your own phrasing."))
        let stack = column(); styleStack = stack
        let styles = (try? controller.history?.values(table: "app_styles")) ?? [:]
        for key in styles.keys.sorted() { addStyle(key, style: styles[key] ?? "neutral") }
        if styles.isEmpty { addStyle("", style: "neutral") }
        fillWidth(scroll(stack, height: 230))
        fillWidth(row([ActionButton("Add app") { [weak self] in self?.addStyle("", style: "neutral") }, ActionButton("Choose application…") { [weak self] in self?.chooseApp() }, ActionButton("Save styles") { [weak self] in self?.saveStyles() }]))
        fillWidth(label("Enable local text context in Settings to include selected and nearby words as spelling hints. Protected fields are excluded."))
    }
    func addStyle(_ app: String, style: String) {
        guard let stack = styleStack else { return }
        let field = NSTextField(string: app); field.placeholderString = "Application identifier"; field.widthAnchor.constraint(equalToConstant: 500).isActive = true
        let picker = NSPopUpButton(); picker.addItems(withTitles: WritingStyle.allCases.map(\.rawValue)); picker.selectItem(withTitle: style)
        stack.addArrangedSubview(row([field, picker])); styleRows.append((field, picker)); stack.frame.size = NSSize(width: 790, height: CGFloat(styleRows.count) * 42)
    }
    func chooseApp() { let picker = NSOpenPanel(); picker.allowedContentTypes = [.applicationBundle]; picker.directoryURL = URL(fileURLWithPath: "/Applications"); if picker.runModal() == .OK, let url = picker.url, let id = Bundle(url: url)?.bundleIdentifier { addStyle(id, style: "neutral") } }
    func saveStyles() { var values: [String: String] = [:]; for (field, picker) in styleRows where !field.stringValue.isEmpty { values[field.stringValue] = picker.titleOfSelectedItem ?? "neutral" }; do { try controller.history?.setValues(values, table: "app_styles"); statusLabel.stringValue = "App styles saved" } catch { statusLabel.stringValue = error.localizedDescription } }
    func settingsPage() {
        fillWidth(label("Make room for your voice", size: 22, weight: .semibold))
        let body = column(14); checks = [:]; fields = [:]
        let prefs = controller.preferences
        let feedback = SessionMeasurements.median(controller.measurements.feedbackMilliseconds).map { String(format: "%.0f ms", $0) } ?? "not measured"
        let insertion = SessionMeasurements.median(controller.measurements.insertionMilliseconds).map { String(format: "%.0f ms", $0) } ?? "not measured"
        body.addArrangedSubview(label("This launch · shortcut feedback: \(feedback) · dictation completion: \(insertion)."))
        let permissionText = "Microphone \(AVCaptureDevice.authorizationStatus(for: .audio) == .authorized ? "✓" : "needs access") · Accessibility \(AXIsProcessTrusted() ? "✓" : "needs access") · Input Monitoring \(CGPreflightListenEventAccess() ? "✓" : "optional")"
        body.addArrangedSubview(label(permissionText))
        body.addArrangedSubview(row([ActionButton("Enable microphone") { AVCaptureDevice.requestAccess(for: .audio) { _ in } }, ActionButton("Accessibility…") { Self.privacy("Privacy_Accessibility") }, ActionButton("Input Monitoring…") { Self.privacy("Privacy_ListenEvent") }]))
        micPicker = NSPopUpButton(); micPicker.addItem(withTitle: "System default microphone"); micIDs = [0]
        for device in Self.microphones() { micPicker.addItem(withTitle: device.1); micIDs.append(device.0) }
        micPicker.selectItem(at: micIDs.firstIndex(of: prefs.microphone) ?? 0)
        languagePicker = NSPopUpButton(); languagePicker.addItems(withTitles: ["English (US)", "English (India)", "English (UK)"]); languagePicker.selectItem(at: ["en-US", "en-IN", "en-GB"].firstIndex(of: prefs.language) ?? 0)
        body.addArrangedSubview(row([label("Microphone"), micPicker, label("Language"), languagePicker]))
        body.addArrangedSubview(label("The bundled speech model recognizes English. Other languages require a compatible local model."))
        retentionPicker = NSPopUpButton(); retentionPicker.addItems(withTitles: ["Keep history", "Delete after a day", "Never save history"]); retentionPicker.selectItem(at: Retention.allCases.firstIndex(of: prefs.retention) ?? 0)
        body.addArrangedSubview(row([label("History"), retentionPicker]))
        hotkeyPicker = NSPopUpButton(); hotkeyPicker.addItems(withTitles: ["Control Option Space", "Control Option D"]); hotkeyPicker.selectItem(at: prefs.toggleKey == 2 ? 1 : 0)
        body.addArrangedSubview(row([label("Toggle shortcut"), hotkeyPicker]))
        holdPicker = NSPopUpButton(); holdPicker.addItems(withTitles: HoldKey.allCases.map(\.title)); holdPicker.selectItem(at: HoldKey.allCases.firstIndex(of: prefs.holdKey) ?? 0)
        body.addArrangedSubview(row([label("Hold-to-talk key"), holdPicker]))
        enginePicker = NSPopUpButton(); enginePicker.addItems(withTitles: SpeechEngine.allCases.map(\.title)); enginePicker.selectItem(at: SpeechEngine.allCases.firstIndex(of: prefs.speechEngine) ?? 0)
        body.addArrangedSubview(row([label("Speech engine"), enginePicker]))
        for (key, title, value) in [("hold", "Enable the selected hold-to-talk key", prefs.holdEnabled), ("code", "Preserve exact syntax in code editors and terminals", prefs.preserveCode), ("hands", "Hands-free: finish after silence", prefs.handsFree), ("context", "Use selected and nearby text as local spelling context", prefs.contextEnabled), ("return", "Allow spoken ‘press enter’ at the end", prefs.spokenReturn), ("audio", "Keep recordings on this Mac (off by default)", prefs.keepAudio)] {
            let check = NSButton(checkboxWithTitle: title, target: nil, action: nil); check.state = value ? .on : .off; checks[key] = check; body.addArrangedSubview(check)
        }
        let holdHelp = prefs.holdKey == .globe ? "Set Keyboard → Press globe key → Do Nothing to avoid the emoji picker." : "Your chosen hold key is passed through to the app you are using."
        body.addArrangedSubview(label(holdHelp + " Editing: Control Option R. Paste previous: Control Option V."))
        for (key, title, value) in [("silence", "Silence before hands-free finishes (seconds)", prefs.silenceSeconds), ("maximum", "Maximum recording (seconds)", prefs.maximumSeconds), ("clipboard", "Clipboard recovery delay (seconds)", prefs.clipboardDelay)] {
            let input = NSTextField(string: String(value)); input.widthAnchor.constraint(equalToConstant: 80).isActive = true; fields[key] = input; body.addArrangedSubview(row([label(title), input]))
        }
        let modelCleanup = NSButton(checkboxWithTitle: "Use validated on-device punctuation cleanup", target: nil, action: nil)
        modelCleanup.state = prefs.useModel && controller.modelPassValidated ? .on : .off
        modelCleanup.isEnabled = controller.modelPassValidated; checks["model"] = modelCleanup; body.addArrangedSubview(modelCleanup)
        let qualification = CleanupQualification.load()
        let summary = qualification.map { "Cleanup checks: \($0.passed)/\($0.cases); 95th percentile \(String(format: "%.2f", $0.p95Seconds)) s." } ?? "Validate the installed on-device model before enabling cleanup. Slow or changed content falls back to rules."
        body.addArrangedSubview(label(summary))
        body.addArrangedSubview(ActionButton(controller.validationTask == nil ? "Validate local cleanup" : "Validation in progress…") { [weak self] in self?.controller.validateCleanup() })
        body.addArrangedSubview(ActionButton("Refresh permission status") { [weak self] in self?.render() })
        if prefs.speechEngine == .systemLegacy { body.addArrangedSubview(ActionButton("Enable system Speech Recognition") { SFSpeechRecognizer.requestAuthorization { _ in } }) }
        body.addArrangedSubview(row([ActionButton("Start at login: \(SMAppService.mainApp.status == .enabled ? "on" : "off")") { [weak self] in self?.toggleStartup() }, ActionButton("Choose speech model…") { [weak self] in self?.chooseSpeechModel() }, ActionButton("Choose decoder…") { [weak self] in self?.chooseDecoder() }]))
        let scroller = scroll(body); fillWidth(scroller); scroller.heightAnchor.constraint(greaterThanOrEqualToConstant: 300).isActive = true
        body.frame.size = NSSize(width: 820, height: 1140)
        scroller.contentView.scroll(to: .zero); scroller.reflectScrolledClipView(scroller.contentView)
        fillWidth(ActionButton("Save settings") { [weak self] in self?.saveSettings() })
    }
    static func privacy(_ category: String) { if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?" + category) { NSWorkspace.shared.open(url) } }
    func toggleStartup() { do { if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }; render() } catch { statusLabel.stringValue = error.localizedDescription } }
    func chooseSpeechModel() { let panel = NSOpenPanel(); if panel.runModal() == .OK, let path = panel.url?.path { controller.preferences.customSpeechModel = path; controller.applyPreferences(); statusLabel.stringValue = "Local speech model selected" } }
    func chooseDecoder() { let panel = NSOpenPanel(); if panel.runModal() == .OK, let path = panel.url?.path { controller.preferences.customSpeechExecutable = path; controller.applyPreferences(); statusLabel.stringValue = "Local decoder selected" } }
    func saveSettings() {
        var p = controller.preferences
        p.microphone = micIDs[max(0, micPicker.indexOfSelectedItem)]; p.language = ["en-US", "en-IN", "en-GB"][max(0, languagePicker.indexOfSelectedItem)]
        p.retention = Retention.allCases[max(0, retentionPicker.indexOfSelectedItem)]; p.toggleKey = hotkeyPicker.indexOfSelectedItem == 1 ? 2 : 49
        p.useModel = checks["model"]?.state == .on && controller.modelPassValidated; p.holdEnabled = checks["hold"]?.state == .on; p.holdKey = HoldKey.allCases[max(0, holdPicker.indexOfSelectedItem)]; p.speechEngine = SpeechEngine.allCases[max(0, enginePicker.indexOfSelectedItem)]; p.preserveCode = checks["code"]?.state == .on; p.handsFree = checks["hands"]?.state == .on; p.contextEnabled = checks["context"]?.state == .on; p.spokenReturn = checks["return"]?.state == .on; p.keepAudio = checks["audio"]?.state == .on
        p.silenceSeconds = max(0.5, min(10, fields["silence"]?.doubleValue ?? 1.5)); p.maximumSeconds = max(5, min(600, fields["maximum"]?.doubleValue ?? 120)); p.clipboardDelay = max(0.1, min(2, fields["clipboard"]?.doubleValue ?? 0.35))
        controller.preferences = p; controller.applyPreferences(); render(); statusLabel.stringValue = "Settings saved"
    }
    static func microphones() -> [(AudioDeviceID, String)] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var bytes: UInt32 = 0; guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &bytes) == noErr else { return [] }
        var devices = [AudioDeviceID](repeating: 0, count: Int(bytes) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &bytes, &devices) == noErr else { return [] }
        return devices.compactMap { device in
            var input = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain); var size: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(device, &input, 0, nil, &size) == noErr, size > 0 else { return nil }
            var nameAddress = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var name: Unmanaged<CFString>?; var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            guard AudioObjectGetPropertyData(device, &nameAddress, 0, nil, &nameSize, &name) == noErr else { return nil }; guard let name else { return nil }; return (device, name.takeRetainedValue() as String)
        }
    }
}
