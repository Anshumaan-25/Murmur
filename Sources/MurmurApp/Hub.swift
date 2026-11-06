import AppKit
import AVFoundation
import Speech
import CoreAudio
import ApplicationServices
import ServiceManagement
import UniformTypeIdentifiers
import MurmurCore

final class ActionButton: NSButton {
    var perform: (() -> Void)?
    var primary = false { didSet { needsDisplay = true } }
    private var hovered = false
    private var tracking: NSTrackingArea?
    convenience init(_ title: String, primary: Bool = false, _ action: @escaping () -> Void) {
        self.init(title: title, target: nil, action: nil); perform = action; self.primary = primary
        target = self; self.action = #selector(invoke); bezelStyle = .rounded; isBordered = false
        font = .systemFont(ofSize: 12, weight: .semibold)
    }
    override var intrinsicContentSize: NSSize { NSSize(width: max(80, (title as NSString).size(withAttributes: [.font:font ?? NSFont.systemFont(ofSize: 12)]).width + 30), height: 36) }
    override func updateTrackingAreas() { super.updateTrackingAreas(); if let tracking { removeTrackingArea(tracking) }; tracking = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self); addTrackingArea(tracking!) }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        let frame = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: frame, xRadius: 9, yRadius: 9)
        let color = primary ? Palette.violet : Palette.raised
        color.withAlphaComponent(isHighlighted ? 0.65 : 1).setFill(); path.fill()
        (hovered ? Palette.violet.withAlphaComponent(0.65) : Palette.line).setStroke(); path.lineWidth = 1; path.stroke()
        let attributes: [NSAttributedString.Key: Any] = [.font:NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor:(primary ? Palette.background : Palette.text).withAlphaComponent(isEnabled ? 1 : 0.4)]
        let text = title as NSString; let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2), withAttributes: attributes)
        if focusRingType != .none && window?.firstResponder === self { NSFocusRingPlacement.only.set(); path.fill() }
    }
    @objc func invoke() { if isEnabled { perform?() } }
}
final class PromptTextView: NSTextView {
    var placeholder = "Write here…"
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty { (placeholder as NSString).draw(at: NSPoint(x: textContainerInset.width + 5, y: textContainerInset.height), withAttributes: [.font:font ?? NSFont.systemFont(ofSize: 14), .foregroundColor:Palette.muted.withAlphaComponent(0.7)]) }
    }
    override func didChangeText() { super.didChangeText(); needsDisplay = true }
}
final class FlippedStack: NSStackView { override var isFlipped: Bool { true } }
@MainActor final class Hub: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    let controller: DictationController
    let content = CanvasView()
    let pages = NSStackView()
    var page = 0
    var previousApp: NSRunningApplication?
    let navigation = NSSegmentedControl(labels: ["History", "Vocabulary", "Snippets", "Styles", "Settings"], trackingMode: .selectOne, target: nil, action: nil)
    let preview: Bool
    let heading = NSTextField(labelWithString: "")
    let subtitle = NSTextField(labelWithString: "")
    let permissionLabel = NSTextField(labelWithString: "")
    var permissionButton: ActionButton?
    var sidebarButtons: [SidebarButton] = []
    var metricValues: [NSTextField] = []
    var historyWasEmpty = true
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
    private weak var startupStatus: NSTextField?
    private weak var startupButton: ActionButton?
    private weak var shortcutWarning: NSTextField?
    private weak var sidebarShortcut: NSTextField?
    var checks: [String: NSButton] = [:]
    var fields: [String: NSTextField] = [:]
    init(controller: DictationController, preview: Bool = false) {
        self.controller = controller; self.preview = preview
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1140, height: 820), styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Keydown"; window.minSize = NSSize(width: 1040, height: 760); window.isReleasedWhenClosed = false; window.isRestorable = false
        window.titlebarAppearsTransparent = true; window.titleVisibility = .hidden; window.appearance = NSAppearance(named: .darkAqua); window.backgroundColor = Palette.background; window.contentView = content
        super.init(window: window)
        buildShell(); window.center(); render()
    }
    required init?(coder: NSCoder) { fatalError("Unsupported initializer") }
    func label(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text); field.font = .systemFont(ofSize: size, weight: weight); field.textColor = size >= 20 ? Palette.text : Palette.muted; return field
    }
    func column(_ spacing: CGFloat = 14) -> NSStackView { let stack = FlippedStack(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = spacing; return stack }
    func row(_ views: [NSView]) -> NSStackView { let stack = NSStackView(views: views); stack.orientation = .horizontal; stack.spacing = 12; return stack }
    func buildShell() {
        statusLabel.stringValue = "Ready · " + controller.shortcutTitle
        let sidebar = SurfaceView(); sidebar.color = NSColor(srgbRed: 0.057, green: 0.065, blue: 0.10, alpha: 1); sidebar.radius = 0
        let brand = row([BrandMark(), label("Keydown", size: 25, weight: .semibold)])
        let nav = column(5)
        let titles = ["History", "Vocabulary", "Snippets", "App styles", "Settings"]
        let icons = ["clock.arrow.circlepath", "character.book.closed", "text.quote", "slider.horizontal.3", "gearshape"]
        for index in titles.indices {
            let button = SidebarButton(titles[index], icon: icons[index]) { [weak self] in self?.page = index; self?.navigation.selectedSegment = index; self?.render() }
            nav.addArrangedSubview(button); button.widthAnchor.constraint(equalTo: nav.widthAnchor).isActive = true; sidebarButtons.append(button)
        }
        let local = column(8)
        let privacy = label("●  PRIVATE BY DESIGN", size: 10, weight: .semibold); privacy.textColor = Palette.mint
        local.addArrangedSubview(privacy); local.addArrangedSubview(label("Your voice stays on this Mac.", size: 11))
        let shortcut = label(controller.shortcutSymbols, size: 15, weight: .medium)
        sidebarShortcut = shortcut
        local.addArrangedSubview(shortcut); local.addArrangedSubview(label("Start. Speak. Press again.", size: 11))
        for view in [brand, nav, local] { view.translatesAutoresizingMaskIntoConstraints = false; sidebar.addSubview(view) }
        sidebar.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(sidebar)
        heading.font = .systemFont(ofSize: 32, weight: .bold); heading.textColor = Palette.text
        subtitle.font = .systemFont(ofSize: 13); subtitle.textColor = Palette.muted
        let top = column(10); top.addArrangedSubview(heading); top.addArrangedSubview(subtitle)
        permissionLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        let permission = column(7); permission.alignment = .trailing; permission.addArrangedSubview(permissionLabel)
        let grant = ActionButton("Enable insertion") { Self.privacy("Privacy_Accessibility") }; permissionButton = grant; permission.addArrangedSubview(grant)
        refreshPermissions()
        navigation.selectedSegment = 0; navigation.target = self; navigation.action = #selector(navigate)
        pages.orientation = .vertical; pages.alignment = .leading; pages.spacing = 17; pages.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        pages.wantsLayer = true; pages.layer?.backgroundColor = Palette.surface.cgColor; pages.layer?.cornerRadius = 20; pages.layer?.borderColor = Palette.line.cgColor; pages.layer?.borderWidth = 1
        let start = ActionButton("Start dictation", primary: true) { [weak self] in self?.dictateFromHub() }
        let footer = row([statusLabel, start, ActionButton("Cancel") { [weak self] in self?.controller.cancel() }])
        statusLabel.font = .systemFont(ofSize: 11, weight: .medium); statusLabel.textColor = Palette.muted; statusLabel.lineBreakMode = .byTruncatingTail; statusLabel.setContentHuggingPriority(.init(1), for: .horizontal); footer.distribution = .fill
        for view in [top, permission, pages, footer] { view.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(view) }
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: content.leadingAnchor), sidebar.topAnchor.constraint(equalTo: content.topAnchor), sidebar.bottomAnchor.constraint(equalTo: content.bottomAnchor), sidebar.widthAnchor.constraint(equalToConstant: 212),
            brand.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 60), brand.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 24),
            nav.topAnchor.constraint(equalTo: brand.bottomAnchor, constant: 44), nav.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 14), nav.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -14),
            local.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 26), local.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -30),
            top.topAnchor.constraint(equalTo: content.topAnchor, constant: 54), top.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: 32), top.trailingAnchor.constraint(lessThanOrEqualTo: permission.leadingAnchor, constant: -12),
            permission.topAnchor.constraint(equalTo: top.topAnchor, constant: 4), permission.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -32),
            pages.topAnchor.constraint(equalTo: top.bottomAnchor, constant: 28), pages.leadingAnchor.constraint(equalTo: top.leadingAnchor), pages.trailingAnchor.constraint(equalTo: permission.trailingAnchor), pages.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -20),
            footer.leadingAnchor.constraint(equalTo: top.leadingAnchor), footer.trailingAnchor.constraint(equalTo: permission.trailingAnchor), footer.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -24)
        ])
        controller.status = { [weak self] message in self?.statusLabel.stringValue = message; self?.refreshPermissions() }
        controller.received = { [weak self] text in self?.details.string = text }
        controller.changed = { [weak self] in self?.reloadHistory() }
        controller.validationChanged = { [weak self] in if self?.page == 4 { self?.render() } }
    }
    func refreshPermissions() {
        sidebarShortcut?.stringValue = controller.shortcutSymbols
        let trusted = AXIsProcessTrusted()
        permissionLabel.stringValue = trusted ? "●  ON DEVICE" : "●  PASTE ACCESS NEEDED"
        permissionLabel.textColor = trusted ? Palette.mint : .systemOrange
        permissionButton?.isHidden = trusted
        permissionButton?.toolTip = "Allow Keydown in System Settings → Privacy & Security → Accessibility to insert text at your cursor."
        if page == 4 {
            let message = controller.hotkeys.availabilityMessage
            shortcutWarning?.stringValue = message ?? ""
            shortcutWarning?.isHidden = message == nil
            refreshStartupStatus()
        }
    }
    func dictateFromHub() {
        window?.orderOut(nil)
        previousApp?.activate(options: [.activateAllWindows])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.controller.toggle() }
    }
    func show() { if let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp = app }; NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil); refreshPermissions(); if page == 0 { reloadHistory() } }
    @objc func navigate() { page = navigation.selectedSegment; render() }
    func render() {
        for view in pages.arrangedSubviews { pages.removeArrangedSubview(view); view.removeFromSuperview() }
        let titles = ["Your words, at a glance.", "A language of your own.", "Say less. Write more.", "The right voice, anywhere.", "Make it yours."]
        let descriptions = ["A little less typing. A little more room to think.", "The people, places, and terms that matter to you.", "Turn a short phrase into something you say often.", "Personal touches for the apps you use every day.", "Fine-tune your sound, shortcuts, and preferences."]
        heading.stringValue = titles[min(page, 4)]; subtitle.stringValue = descriptions[min(page, 4)]
        for (index, button) in sidebarButtons.enumerated() { button.chosen = index == page }
        switch page { case 0: historyPage(); case 1: dictionaryPage(); case 2: snippetsPage(); case 3: stylesPage(); default: settingsPage() }
        let space = NSView(); space.setContentHuggingPriority(.init(1), for: .vertical); pages.addArrangedSubview(space)
        if !Palette.reduceMotion, window?.isVisible == true {
            pages.alphaValue = 0.45
            NSAnimationContext.runAnimationGroup { context in context.duration = 0.20; pages.animator().alphaValue = 1 }
        }
        refreshPermissions()
    }
    func fillWidth(_ view: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = false; pages.addArrangedSubview(view)
        if view is ActionButton { view.widthAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true }
        else { view.widthAnchor.constraint(equalTo: pages.widthAnchor, constant: -48).isActive = true }
    }
    func scroll(_ document: NSView, height: CGFloat? = nil) -> NSScrollView {
        let scroller = NSScrollView(); scroller.hasVerticalScroller = true; scroller.drawsBackground = true; scroller.backgroundColor = Palette.background; scroller.borderType = .noBorder; scroller.wantsLayer = true; scroller.layer?.cornerRadius = 10; scroller.layer?.borderColor = Palette.line.cgColor; scroller.layer?.borderWidth = 1; scroller.documentView = document
        if let height { scroller.heightAnchor.constraint(equalToConstant: height).isActive = true }; return scroller
    }
    func editor(_ text: String, height: CGFloat = 180) -> (NSTextView, NSScrollView) {
        let view = PromptTextView(frame: NSRect(x: 0, y: 0, width: 700, height: height)); view.string = text; view.isRichText = false; view.backgroundColor = Palette.background; view.textColor = Palette.text; view.insertionPointColor = Palette.violet; view.font = .systemFont(ofSize: 14); view.textContainerInset = NSSize(width: 12, height: 10)
        view.isVerticallyResizable = true; view.autoresizingMask = [.width]; view.textContainer?.widthTracksTextView = true
        return (view, scroll(view, height: height))
    }
    func metric(_ value: String, title: String, icon: String) -> SurfaceView {
        let card = SurfaceView(); card.color = Palette.raised; card.radius = 13
        let number = label(value, size: 27, weight: .semibold); metricValues.append(number)
        let caption = label(title, size: 11); let image = NSImageView(image: Palette.symbol(icon, size: 15, color: Palette.violet) ?? NSImage())
        for view in [number, caption, image] { view.translatesAutoresizingMaskIntoConstraints = false; card.addSubview(view) }
        NSLayoutConstraint.activate([card.heightAnchor.constraint(equalToConstant: 96), number.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18), number.topAnchor.constraint(equalTo: card.topAnchor, constant: 14), caption.leadingAnchor.constraint(equalTo: number.leadingAnchor), caption.topAnchor.constraint(equalTo: number.bottomAnchor, constant: 4), image.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16), image.topAnchor.constraint(equalTo: card.topAnchor, constant: 19), image.widthAnchor.constraint(equalToConstant: 16), image.heightAnchor.constraint(equalToConstant: 16)])
        return card
    }
    func historyPage() {
        rows = preview ? [] : (try? controller.history?.records()) ?? []; historyWasEmpty = rows.isEmpty
        let stats = UsageStatistics(rows); metricValues = []
        let metrics = row([metric("\(stats.words)", title: "WORDS SPOKEN", icon: "text.alignleft"), metric("\(Int(stats.wordsPerMinute))", title: "WORDS PER MINUTE", icon: "speedometer"), metric("\(stats.streak) days", title: "CURRENT STREAK", icon: "sparkles")]); metrics.distribution = .fillEqually; fillWidth(metrics)
        if rows.isEmpty {
            let hero = WaveArtwork(); hero.wantsLayer = true; hero.layer?.cornerRadius = 16
            let title = label("Speak freely.\nKeep your rhythm.", size: 32, weight: .bold)
            let detail = label("A thought, a message, a first draft.\nPlace your cursor, then let your voice take over.", size: 13)
            let shortcut = label(controller.shortcutSymbols, size: 15, weight: .semibold); shortcut.textColor = Palette.mint
            for view in [title, detail, shortcut] { view.translatesAutoresizingMaskIntoConstraints = false; hero.addSubview(view) }
            NSLayoutConstraint.activate([hero.heightAnchor.constraint(equalToConstant: 260), title.leadingAnchor.constraint(equalTo: hero.leadingAnchor, constant: 28), title.topAnchor.constraint(equalTo: hero.topAnchor, constant: 28), detail.leadingAnchor.constraint(equalTo: title.leadingAnchor), detail.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 16), shortcut.leadingAnchor.constraint(equalTo: title.leadingAnchor), shortcut.topAnchor.constraint(equalTo: detail.bottomAnchor, constant: 23)])
            fillWidth(hero)
            let steps = row([label("01   Focus a text field", size: 12, weight: .medium), label("02   Press & speak", size: 12, weight: .medium), label("03   Press again to insert", size: 12, weight: .medium)]); steps.distribution = .fillEqually; fillWidth(steps)
            fillWidth(label("Your dictation history will appear here. It stays on this Mac.", size: 11))
            return
        }
        search = NSSearchField(); search.placeholderString = "Search your dictations"; search.delegate = self; fillWidth(search)
        table = NSTableView(); table.backgroundColor = Palette.background; table.rowHeight = 38; table.headerView = NSTableHeaderView(); table.gridColor = Palette.line; table.selectionHighlightStyle = .regular
        for (key, title, width) in [("when", "When", 140.0), ("app", "Application", 150.0), ("text", "Text", 380.0)] { let c = NSTableColumn(identifier: .init(key)); c.title = title; c.width = width; table.addTableColumn(c) }
        table.dataSource = self; table.delegate = self; fillWidth(scroll(table, height: 140))
        let (detail, detailScroll) = editor("Select a dictation to see its transcript and delivery details.", height: 130); details = detail; details.isEditable = false; fillWidth(detailScroll)
        fillWidth(row([ActionButton("Copy selected") { [weak self] in self?.copySelected() }, ActionButton("Delete selected") { [weak self] in self?.deleteSelected() }, ActionButton("Export history…") { [weak self] in self?.exportHistory() }]))
    }
    func reloadHistory() {
        guard page == 0, !preview else { return }
        let all = (try? controller.history?.records()) ?? []
        if historyWasEmpty != all.isEmpty { render(); return }
        rows = (try? controller.history?.records(search: search.stringValue)) ?? []; table.reloadData()
        let stats = UsageStatistics(all)
        for (field, value) in zip(metricValues, ["\(stats.words)", "\(Int(stats.wordsPerMinute))", "\(stats.streak) days"]) { field.stringValue = value }
    }
    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
    func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
        guard rows.indices.contains(row) else { return nil }; let record = rows[row]
        let value: String
        switch column?.identifier.rawValue { case "when": value = record.timestamp.formatted(date: .abbreviated, time: .shortened); case "app": value = record.application.isEmpty ? "Unknown" : record.application; default: value = record.cleaned }
        let cell = NSTextField(labelWithString: value); cell.lineBreakMode = .byTruncatingTail; cell.font = .systemFont(ofSize: 12); cell.textColor = Palette.text; return cell
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
        let save = NSSavePanel(); save.allowedContentTypes = [.json]; save.nameFieldStringValue = "Keydown-history.json"
        if save.runModal() == .OK, let url = save.url { do { let records = try controller.history?.records() ?? []; let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601; try encoder.encode(records).write(to: url, options: .atomic); statusLabel.stringValue = "History exported" } catch { statusLabel.stringValue = error.localizedDescription } }
    }
    func dictionaryPage() {
        fillWidth(label("Names worth getting right", size: 22, weight: .semibold))
        fillWidth(label("Add a name or term on each line. Keydown uses these as recognition hints and keeps their capitalization."))
        let terms = preview ? [] : (try? controller.history?.dictionary()) ?? []
        let (view, scroller) = editor(terms.joined(separator: "\n"), height: 260); words = view; fillWidth(scroller)
        fillWidth(ActionButton("Save vocabulary", primary: true) { [weak self] in guard let self else { return }; do { try self.controller.history?.setDictionary(self.words.string.components(separatedBy: .newlines)); self.statusLabel.stringValue = "Vocabulary saved" } catch { self.statusLabel.stringValue = error.localizedDescription } })
    }
    func snippetsPage() {
        snippetRows = []; fillWidth(label("A few words, a longer message", size: 22, weight: .semibold))
        fillWidth(label("Say a trigger by itself to insert its full text. Expansions preserve your line breaks."))
        let stack = column(16); snippetStack = stack
        let values = preview ? [:] : (try? controller.history?.values(table: "expansions")) ?? [:]
        for key in values.keys.sorted() { addSnippet(key, value: values[key] ?? "") }
        if values.isEmpty { addSnippet("", value: "") }
        let scroller = scroll(stack, height: 280); fillWidth(scroller)
        fillWidth(row([ActionButton("Add expansion") { [weak self] in self?.addSnippet("", value: "") }, ActionButton("Save expansions", primary: true) { [weak self] in self?.saveSnippets() }]))
    }
    func addSnippet(_ trigger: String, value: String) {
        guard let stack = snippetStack else { return }
        let field = NSTextField(string: trigger); field.placeholderString = "Spoken trigger"; field.widthAnchor.constraint(equalToConstant: 180).isActive = true
        let (text, scroller) = editor(value, height: 76); scroller.widthAnchor.constraint(equalToConstant: 480).isActive = true
        let container = row([field, scroller]); stack.addArrangedSubview(container); snippetRows.append((field, text))
        stack.layoutSubtreeIfNeeded(); stack.frame.size = NSSize(width: 680, height: CGFloat(snippetRows.count) * 100)
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
        let styles = preview ? [:] : (try? controller.history?.values(table: "app_styles")) ?? [:]
        for key in styles.keys.sorted() { addStyle(key, style: styles[key] ?? "neutral") }
        if styles.isEmpty { addStyle("", style: "neutral") }
        fillWidth(scroll(stack, height: 230))
        fillWidth(row([ActionButton("Add app") { [weak self] in self?.addStyle("", style: "neutral") }, ActionButton("Choose application…") { [weak self] in self?.chooseApp() }, ActionButton("Save styles", primary: true) { [weak self] in self?.saveStyles() }]))
        fillWidth(label("Enable local text context in Settings to include selected and nearby words as spelling hints. Protected fields are excluded."))
    }
    func addStyle(_ app: String, style: String) {
        guard let stack = styleStack else { return }
        let field = NSTextField(string: app); field.placeholderString = "Application identifier"; field.widthAnchor.constraint(equalToConstant: 440).isActive = true
        let picker = NSPopUpButton(); picker.addItems(withTitles: WritingStyle.allCases.map(\.rawValue)); picker.selectItem(withTitle: style)
        stack.addArrangedSubview(row([field, picker])); styleRows.append((field, picker)); stack.frame.size = NSSize(width: 680, height: CGFloat(styleRows.count) * 42)
    }
    func chooseApp() { let picker = NSOpenPanel(); picker.allowedContentTypes = [.applicationBundle]; picker.directoryURL = URL(fileURLWithPath: "/Applications"); if picker.runModal() == .OK, let url = picker.url, let id = Bundle(url: url)?.bundleIdentifier { addStyle(id, style: "neutral") } }
    func saveStyles() { var values: [String: String] = [:]; for (field, picker) in styleRows where !field.stringValue.isEmpty { values[field.stringValue] = picker.titleOfSelectedItem ?? "neutral" }; do { try controller.history?.setValues(values, table: "app_styles"); statusLabel.stringValue = "App styles saved" } catch { statusLabel.stringValue = error.localizedDescription } }
    func settingsPage() {
        fillWidth(label("Make room for your voice", size: 22, weight: .semibold))
        let body = column(14); checks = [:]; fields = [:]
        let prefs = controller.preferences
        let feedback = SessionMeasurements.median(controller.measurements.feedbackMilliseconds).map { String(format: "%.0f ms", $0) } ?? "not measured"
        let insertion = SessionMeasurements.median(controller.measurements.insertionMilliseconds).map { String(format: "%.0f ms", $0) } ?? "not measured"
        body.addArrangedSubview(label("PERFORMANCE THIS SESSION", size: 10, weight: .semibold))
        body.addArrangedSubview(label("This launch · shortcut feedback: \(feedback) · dictation completion: \(insertion)."))
        let permissionText = "Microphone \(AVCaptureDevice.authorizationStatus(for: .audio) == .authorized ? "✓" : "needs access") · Accessibility \(AXIsProcessTrusted() ? "✓" : "needs access") · Input Monitoring \(CGPreflightListenEventAccess() ? "✓" : "optional")"
        body.addArrangedSubview(label("ACCESS & INSERTION", size: 10, weight: .semibold))
        body.addArrangedSubview(label(permissionText))
        body.addArrangedSubview(label("Automatic insertion needs Accessibility. If delivery falls back to copying, the indicator tells you why."))
        body.addArrangedSubview(row([ActionButton("Enable microphone") { AVCaptureDevice.requestAccess(for: .audio) { _ in } }, ActionButton("Accessibility…") { Self.privacy("Privacy_Accessibility") }, ActionButton("Input Monitoring…") { Self.privacy("Privacy_ListenEvent") }]))
        body.addArrangedSubview(label("OPEN AT LOGIN", size: 10, weight: .semibold))
        let loginStatus = label("")
        let loginButton = ActionButton("Open at Login") {}
        startupStatus = loginStatus
        startupButton = loginButton
        body.addArrangedSubview(loginStatus)
        body.addArrangedSubview(row([loginButton, ActionButton("Login Items Settings…") { SMAppService.openSystemSettingsLoginItems() }]))
        micPicker = NSPopUpButton(); micPicker.addItem(withTitle: "System default microphone"); micIDs = [0]
        for device in Self.microphones() { micPicker.addItem(withTitle: device.1); micIDs.append(device.0) }
        micPicker.selectItem(at: micIDs.firstIndex(of: prefs.microphone) ?? 0)
        languagePicker = NSPopUpButton(); languagePicker.addItems(withTitles: ["English (US)", "English (India)", "English (UK)"]); languagePicker.selectItem(at: ["en-US", "en-IN", "en-GB"].firstIndex(of: prefs.language) ?? 0)
        body.addArrangedSubview(label("SOUND & LANGUAGE", size: 10, weight: .semibold))
        body.addArrangedSubview(row([label("Microphone"), micPicker, label("Language"), languagePicker]))
        body.addArrangedSubview(label("The bundled speech model recognizes English. Other languages require a compatible local model."))
        retentionPicker = NSPopUpButton(); retentionPicker.addItems(withTitles: ["Keep history", "Delete after a day", "Never save history"]); retentionPicker.selectItem(at: Retention.allCases.firstIndex(of: prefs.retention) ?? 0)
        body.addArrangedSubview(label("EVERYDAY PREFERENCES", size: 10, weight: .semibold))
        body.addArrangedSubview(row([label("History"), retentionPicker]))
        hotkeyPicker = NSPopUpButton(); hotkeyPicker.addItems(withTitles: ["Control Option Space", "Control Option D"]); hotkeyPicker.selectItem(at: prefs.toggleKey == 2 ? 1 : 0)
        body.addArrangedSubview(row([label("Toggle shortcut"), hotkeyPicker]))
        let warning = label("")
        warning.textColor = .systemOrange
        shortcutWarning = warning
        body.addArrangedSubview(warning)
        holdPicker = NSPopUpButton(); holdPicker.addItems(withTitles: HoldKey.allCases.map(\.title)); holdPicker.selectItem(at: HoldKey.allCases.firstIndex(of: prefs.holdKey) ?? 0)
        body.addArrangedSubview(row([label("Hold-to-talk key"), holdPicker]))
        enginePicker = NSPopUpButton(); enginePicker.addItems(withTitles: SpeechEngine.allCases.map(\.title)); enginePicker.selectItem(at: SpeechEngine.allCases.firstIndex(of: prefs.speechEngine) ?? 0)
        body.addArrangedSubview(row([label("Speech engine"), enginePicker]))
        for (key, title, value) in [("hold", "Enable the selected hold-to-talk key", prefs.holdEnabled), ("code", "Preserve exact syntax in code editors and terminals", prefs.preserveCode), ("hands", "Hands-free: finish after silence", prefs.handsFree), ("context", "Use selected and nearby text as local spelling context", prefs.contextEnabled), ("return", "Allow spoken ‘press enter’ at the end", prefs.spokenReturn), ("audio", "Keep recordings on this Mac (off by default)", prefs.keepAudio)] {
            let check = NSButton(checkboxWithTitle: title, target: nil, action: nil); check.state = value ? .on : .off; checks[key] = check; body.addArrangedSubview(check)
        }
        let holdHelp = prefs.holdKey == .globe ? "Set Keyboard → Press globe key → Do Nothing to avoid the emoji picker." : "Your chosen hold key is passed through to the app you are using."
        body.addArrangedSubview(label("Hold your chosen key by itself. " + holdHelp + " Editing: Control Option R. Paste previous: Control Option V."))
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
        body.addArrangedSubview(row([ActionButton("Choose speech model…") { [weak self] in self?.chooseSpeechModel() }, ActionButton("Choose decoder…") { [weak self] in self?.chooseDecoder() }]))
        let scroller = scroll(body); fillWidth(scroller); scroller.heightAnchor.constraint(greaterThanOrEqualToConstant: 300).isActive = true
        body.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([body.leadingAnchor.constraint(equalTo: scroller.contentView.leadingAnchor, constant: 16), body.topAnchor.constraint(equalTo: scroller.contentView.topAnchor, constant: 16), body.widthAnchor.constraint(equalTo: scroller.contentView.widthAnchor, constant: -32)])
        for item in body.arrangedSubviews where item is NSTextField { item.widthAnchor.constraint(lessThanOrEqualTo: body.widthAnchor).isActive = true }
        scroller.contentView.scroll(to: .zero); scroller.reflectScrolledClipView(scroller.contentView)
        fillWidth(ActionButton("Save settings", primary: true) { [weak self] in self?.saveSettings() })
    }
    static func privacy(_ category: String) {
        if category == "Privacy_Accessibility", !AXIsProcessTrusted() {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        if category == "Privacy_ListenEvent", !CGPreflightListenEventAccess() { _ = CGRequestListenEventAccess() }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?" + category) { NSWorkspace.shared.open(url) }
    }
    private func refreshStartupStatus() {
        guard let statusLabel = startupStatus, let button = startupButton else { return }
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            statusLabel.stringValue = "Open the Keydown app bundle to set up a login item."
            button.isEnabled = false
            return
        }
        let status = SMAppService.mainApp.status
        switch status {
        case .enabled:
            statusLabel.stringValue = "On. Keydown starts in the menu bar when you log in."
            button.title = "Disable Open at Login"
        case .notRegistered:
            statusLabel.stringValue = "Off. Keydown can start in the menu bar when you log in."
            button.title = "Enable Open at Login"
        case .requiresApproval:
            statusLabel.stringValue = "Approval needed. Allow Keydown in Login Items to start it automatically."
            button.title = "Remove Login Item"
        case .notFound:
            statusLabel.stringValue = "No login item found. Add Keydown to start it at login."
            button.title = "Enable Open at Login"
        @unknown default:
            statusLabel.stringValue = "Login item status is unavailable. Check Login Items in System Settings."
            button.title = "Open at Login"
        }
        let canRegister = status == .notRegistered || status == .notFound
        button.isEnabled = canRegister || status == .enabled || status == .requiresApproval
        button.perform = { [weak self] in self?.setStartupEnabled(canRegister) }
        button.invalidateIntrinsicContentSize()
    }
    private func setStartupEnabled(_ enabled: Bool) {
        let service = SMAppService.mainApp
        defer { refreshStartupStatus() }
        do {
            switch (enabled, service.status) {
            case (true, .notRegistered), (true, .notFound):
                try service.register()
            case (false, .enabled), (false, .requiresApproval):
                try service.unregister()
            default:
                return
            }
            statusLabel.stringValue = "Login item updated."
        } catch {
            if enabled, service.status == .requiresApproval {
                statusLabel.stringValue = "Approve Keydown in Login Items to start it automatically."
            } else {
                statusLabel.stringValue = "Couldn’t update the login item. \(error.localizedDescription)"
            }
        }
    }
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
