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
@MainActor final class Hub: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSWindowDelegate, NSMenuItemValidation {
    let controller: DictationController
    private var placement: WindowPlacement?
    private let permissions: PermissionAccess
    private var permissionViews: [PermissionAccess.Kind: (NSTextField, ActionButton)] = [:]
    let content = CanvasView()
    private let pageHost = NSView()
    private var pages = NSStackView()
    private var pageViews: [Int: (NSScrollView, NSStackView)] = [:]
    private var drafts = HubDrafts()
    private var resolvingDrafts = false
    private var workspaceObservers: [NSObjectProtocol] = []
    private weak var validationSummary: NSTextField?
    private weak var validationButton: ActionButton?
    private weak var performanceLabel: NSTextField?
    var page = 0
    private(set) var previousApp: NSRunningApplication?
    private var hubStart: (request: UUID, target: pid_t)?
    let navigation = NSSegmentedControl(labels: ["History", "Vocabulary", "Snippets", "Styles", "Settings"], trackingMode: .selectOne, target: nil, action: nil)
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
    var modePicker = NSPopUpButton()
    private var appearancePicker = NSPopUpButton()
    private weak var startupStatus: NSTextField?
    private weak var startupButton: ActionButton?
    private weak var shortcutWarning: NSTextField?
    private weak var sidebarShortcut: NSTextField?
    var checks: [String: NSButton] = [:]
    var fields: [String: NSTextField] = [:]
    init(controller: DictationController, permissions: PermissionAccess? = nil) {
        self.controller = controller
        self.permissions = permissions ?? PermissionAccess()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1140, height: 820), styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Keydown"; window.minSize = NSSize(width: 760, height: 560); window.isReleasedWhenClosed = false; window.isRestorable = false
        window.titlebarAppearsTransparent = true; window.titleVisibility = .hidden; window.backgroundColor = Palette.background; window.contentView = content
        super.init(window: window)
        window.collectionBehavior = [.primary, .fullScreenPrimary]
        window.delegate = self
        buildShell()
        placement = WindowPlacement(window: window, role: .hub, defaults: controller.ephemeral ? nil : .standard)
        render()
        if let app = NSWorkspace.shared.frontmostApplication { observedActivation(app) }
        let workspace = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            MainActor.assumeIsolated {
                if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                    self?.observedActivation(app)
                }
            }
        })
        workspaceObservers.append(workspace.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.sidebarButtons.forEach { $0.needsDisplay = true } }
        })
    }

    deinit {
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
    }

    required init?(coder: NSCoder) { fatalError("Unsupported initializer") }
    func label(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text); field.font = .systemFont(ofSize: size, weight: weight); field.textColor = size >= 20 ? Palette.text : Palette.muted; return field
    }
    func column(_ spacing: CGFloat = 14) -> NSStackView { let stack = FlippedStack(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = spacing; return stack }
    func row(_ views: [NSView]) -> NSStackView { let stack = NSStackView(views: views); stack.orientation = .horizontal; stack.spacing = 12; return stack }
    func buildShell() {
        statusLabel.stringValue = "Ready · " + controller.shortcutTitle
        let sidebar = SurfaceView(); sidebar.color = Palette.surface; sidebar.radius = 0
        let brand = row([BrandMark(), label("Keydown", size: 25, weight: .semibold)])
        let nav = column(5)
        let titles = ["History", "Vocabulary", "Snippets", "App styles", "Settings"]
        let icons = ["clock.arrow.circlepath", "character.book.closed", "text.quote", "slider.horizontal.3", "gearshape"]
        for index in titles.indices {
            let button = SidebarButton(titles[index], icon: icons[index]) { [weak self] in self?.selectPage(index) }
            button.moveSelection = { [weak self] delta in
                guard let self else { return }
                let next = (index + delta + titles.count) % titles.count
                self.selectPage(next)
                self.window?.makeFirstResponder(self.sidebarButtons[next])
            }
            nav.addArrangedSubview(button); button.widthAnchor.constraint(equalTo: nav.widthAnchor).isActive = true; sidebarButtons.append(button)
        }
        let local = column(8)
        let shortcut = label(controller.shortcutSymbols, size: 15, weight: .medium)
        sidebarShortcut = shortcut
        local.addArrangedSubview(shortcut)
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
        pageHost.wantsLayer = true
        pageHost.layer?.cornerRadius = 14
        pageHost.layer?.masksToBounds = true
        let start = ActionButton("Start dictation", primary: true) { [weak self] in self?.dictateFromHub() }
        let footer = row([statusLabel, start, ActionButton("Cancel") { [weak self] in self?.controller.cancel() }])
        statusLabel.font = .systemFont(ofSize: 11, weight: .medium); statusLabel.textColor = Palette.muted; statusLabel.lineBreakMode = .byTruncatingTail; statusLabel.setContentHuggingPriority(.init(1), for: .horizontal); footer.distribution = .fill
        for view in [top, permission, pageHost, footer] { view.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(view) }
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: content.leadingAnchor), sidebar.topAnchor.constraint(equalTo: content.topAnchor), sidebar.bottomAnchor.constraint(equalTo: content.bottomAnchor), sidebar.widthAnchor.constraint(equalToConstant: 184),
            brand.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 60), brand.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 24),
            nav.topAnchor.constraint(equalTo: brand.bottomAnchor, constant: 44), nav.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 14), nav.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -14),
            local.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 26), local.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -30),
            top.topAnchor.constraint(equalTo: content.topAnchor, constant: 54), top.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: 20), top.trailingAnchor.constraint(lessThanOrEqualTo: permission.leadingAnchor, constant: -12),
            permission.topAnchor.constraint(equalTo: top.topAnchor, constant: 4), permission.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            pageHost.topAnchor.constraint(equalTo: top.bottomAnchor, constant: 20), pageHost.leadingAnchor.constraint(equalTo: top.leadingAnchor), pageHost.trailingAnchor.constraint(equalTo: permission.trailingAnchor), pageHost.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -16),
            footer.leadingAnchor.constraint(equalTo: top.leadingAnchor), footer.trailingAnchor.constraint(equalTo: permission.trailingAnchor), footer.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -24)
        ])
        controller.status = { [weak self] message in self?.statusLabel.stringValue = message; self?.refreshPermissions() }
        controller.received = { [weak self] text in
            guard let self, self.table.selectedRow == -1 else { return }
            self.details.string = text
        }
        controller.changed = { [weak self] in self?.reloadHistory() }
        controller.validationChanged = { [weak self] in self?.refreshValidation() }
    }
    func refreshPermissions() {
        sidebarShortcut?.stringValue = controller.shortcutSymbols
        let trusted = AXIsProcessTrusted()
        permissionLabel.stringValue = trusted ? "●  ON DEVICE" : "●  PASTE ACCESS NEEDED"
        permissionLabel.textColor = trusted ? Palette.mint : .systemOrange
        permissionButton?.isHidden = trusted
        permissionButton?.toolTip = "Allow Keydown in System Settings → Privacy & Security → Accessibility to insert text at your cursor."
        if page == 4 {
            let feedback = SessionMeasurements.median(controller.measurements.feedbackMilliseconds).map { String(format: "%.0f ms", $0) } ?? "not measured"
            let insertion = SessionMeasurements.median(controller.measurements.insertionMilliseconds).map { String(format: "%.0f ms", $0) } ?? "not measured"
            performanceLabel?.stringValue = "This launch · first draw dispatch: \(feedback) · dictation completion: \(insertion)."
            let message = controller.hotkeys.availabilityMessage
            shortcutWarning?.stringValue = message ?? ""
            shortcutWarning?.isHidden = message == nil
            refreshStartupStatus()
            refreshCapturePermissions(trusted: trusted)
        }
    }
    func observedActivation(_ application: NSRunningApplication) {
        let pid = application.processIdentifier
        if pid != ProcessInfo.processInfo.processIdentifier {
            previousApp = application
        }
        if hubStart?.target != pid { hubStart = nil }
    }

    func dictateFromHub() {
        guard !controller.hasLocalDialog, !controller.preparingToQuit else { return }
        guard let previousApp, !previousApp.isTerminated else {
            controller.announce("The previous app is unavailable. Start dictation in your destination.")
            return
        }
        let expectedPID = previousApp.processIdentifier
        let intent = controller.intent
        let request = UUID()
        hubStart = (request, expectedPID)
        window?.orderOut(nil)
        guard previousApp.activate() else {
            show()
            controller.announce("The previous app could not be activated.")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, self.hubStart?.request == request else { return }
            self.hubStart = nil
            guard self.controller.intent == intent, !previousApp.isTerminated,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == expectedPID else { return }
            self.controller.start(expectedPID: expectedPID)
        }
    }

    func show() {
        hubStart = nil
        if let app = NSWorkspace.shared.frontmostApplication { observedActivation(app) }
        if let window { controller.presentation.present(window) }
        refreshPermissions()
        if page == 0 { reloadHistory() }
    }

    @objc func navigate() { selectPage(navigation.selectedSegment) }

    func selectPage(_ index: Int) {
        guard (0...4).contains(index), !resolvingDrafts else { return }
        if index != page, window?.makeFirstResponder(nil) == false { return }
        page = index
        navigation.selectedSegment = index
        render()
        if index == 0 { reloadHistory() }
    }

    func render() {
        let titles = ["Your words, at a glance.", "A language of your own.", "A little less typing.", "The right voice, anywhere.", "Make it yours."]
        let descriptions = ["Your dictation history", "Recognition hints for names and terms", "Turn a short phrase into longer text", "Choose how dictation reads in each app", "Sound, shortcuts, and preferences"]
        heading.stringValue = titles[page]
        subtitle.stringValue = descriptions[page]
        for (index, button) in sidebarButtons.enumerated() { button.chosen = index == page }

        let scroller: NSScrollView
        if let (cached, stack) = pageViews[page] {
            scroller = cached
            pages = stack
        } else {
            pages = column(16)
            pages.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
            scroller = scroll(pages)
            scroller.backgroundColor = Palette.surface
            pages.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                pages.leadingAnchor.constraint(equalTo: scroller.contentView.leadingAnchor),
                pages.topAnchor.constraint(equalTo: scroller.contentView.topAnchor),
                pages.widthAnchor.constraint(equalTo: scroller.contentView.widthAnchor),
            ])
            switch page {
            case 0: historyPage()
            case 1: dictionaryPage()
            case 2: snippetsPage()
            case 3: stylesPage()
            default: settingsPage()
            }
            pageViews[page] = (scroller, pages)
            drafts[page] = workingDraft(page)
        }

        if scroller.superview !== pageHost {
            pageHost.subviews.forEach { $0.removeFromSuperview() }
            scroller.translatesAutoresizingMaskIntoConstraints = false
            pageHost.addSubview(scroller)
            NSLayoutConstraint.activate([
                scroller.leadingAnchor.constraint(equalTo: pageHost.leadingAnchor),
                scroller.trailingAnchor.constraint(equalTo: pageHost.trailingAnchor),
                scroller.topAnchor.constraint(equalTo: pageHost.topAnchor),
                scroller.bottomAnchor.constraint(equalTo: pageHost.bottomAnchor),
            ])
        }
        if page == 1 { refreshVocabulary() }
        refreshPermissions()
    }

    func fillWidth(_ view: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        pages.addArrangedSubview(view)
        if !(view is ActionButton) {
            view.widthAnchor.constraint(equalTo: pages.widthAnchor, constant: -32).isActive = true
        }
    }
    func scroll(_ document: NSView, height: CGFloat? = nil) -> NSScrollView {
        let scroller = WorkspaceScrollView(); scroller.hasVerticalScroller = true; scroller.drawsBackground = true; scroller.backgroundColor = Palette.background; scroller.borderType = .noBorder; scroller.wantsLayer = true; scroller.layer?.cornerRadius = 10; scroller.layer?.borderColor = Palette.line.cgColor; scroller.layer?.borderWidth = 1; scroller.documentView = document
        if let height { scroller.heightAnchor.constraint(equalToConstant: height).isActive = true }; return scroller
    }
    func editor(_ text: String, height: CGFloat = 180) -> (NSTextView, NSScrollView) {
        let view = PromptTextView(frame: NSRect(x: 0, y: 0, width: 700, height: height)); view.string = text; view.isRichText = false; view.backgroundColor = Palette.background; view.textColor = Palette.text; view.insertionPointColor = Palette.violet; view.font = .systemFont(ofSize: 14); view.textContainerInset = NSSize(width: 12, height: 10)
        view.allowsUndo = true; view.isVerticallyResizable = true; view.autoresizingMask = [.width]; view.textContainer?.widthTracksTextView = true
        return (view, scroll(view, height: height))
    }
    func metric(_ value: String, title: String, icon: String) -> SurfaceView {
        let card = SurfaceView(); card.color = Palette.raised; card.radius = 13
        let number = label(value, size: 27, weight: .semibold); metricValues.append(number)
        let caption = label(title, size: 11); let image = NSImageView(image: NSImage(systemSymbolName: icon, accessibilityDescription: nil) ?? NSImage())
        image.contentTintColor = Palette.violet
        for view in [number, caption, image] { view.translatesAutoresizingMaskIntoConstraints = false; card.addSubview(view) }
        NSLayoutConstraint.activate([card.heightAnchor.constraint(equalToConstant: 96), number.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18), number.topAnchor.constraint(equalTo: card.topAnchor, constant: 14), caption.leadingAnchor.constraint(equalTo: number.leadingAnchor), caption.topAnchor.constraint(equalTo: number.bottomAnchor, constant: 4), image.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16), image.topAnchor.constraint(equalTo: card.topAnchor, constant: 19), image.widthAnchor.constraint(equalToConstant: 16), image.heightAnchor.constraint(equalToConstant: 16)])
        return card
    }
    func historyPage() {
        rows = (try? controller.history?.records()) ?? []; historyWasEmpty = rows.isEmpty
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
        fillWidth(row([
            ActionButton("Copy selected") { [weak self] in self?.copySelected() },
            ActionButton("Review selected") { [weak self] in
                guard let self, self.rows.indices.contains(self.table.selectedRow) else { return }
                self.controller.reviewRecord(self.rows[self.table.selectedRow])
            },
        ]))
        fillWidth(row([
            ActionButton("Delete selected") { [weak self] in self?.deleteSelected() },
            ActionButton("Export history…") { [weak self] in self?.exportHistory() },
        ]))
    }
    func reloadHistory() {
        guard page == 0 else { return }
        let all = (try? controller.history?.records()) ?? []
        if historyWasEmpty != all.isEmpty { pageViews[0] = nil; render(); return }
        let selectedID = rows.indices.contains(table.selectedRow) ? rows[table.selectedRow].id : nil
        rows = (try? controller.history?.records(search: search.stringValue)) ?? []
        table.reloadData()
        if let selectedID, let index = rows.firstIndex(where: { $0.id == selectedID }) {
            table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            showSelectedHistory()
        } else if selectedID != nil {
            table.deselectAll(nil)
            details.string = ""
        }
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
    func tableViewSelectionDidChange(_ notification: Notification) { showSelectedHistory() }

    private func showSelectedHistory() {
        guard rows.indices.contains(table.selectedRow) else { details.string = ""; return }
        let r = rows[table.selectedRow]
        details.string = "RECOGNIZED\n\(r.raw)\n\nFORMATTED\n\(r.cleaned)\n\nDELIVERY STATUS · \(r.outcome)\n\(r.inserted)\n\nReady in \(String(format: "%.2f", r.latency)) s"
    }
    func controlTextDidChange(_ notification: Notification) { if notification.object as? NSSearchField === search { reloadHistory() } }
    func copySelected() { guard rows.indices.contains(table.selectedRow) else { return }; NSPasteboard.general.clearContents(); NSPasteboard.general.setString(rows[table.selectedRow].cleaned, forType: .string); statusLabel.stringValue = "Copied" }
    func deleteSelected() { guard rows.indices.contains(table.selectedRow) else { return }; do { let id = rows[table.selectedRow].id
            try controller.history?.delete(id)
            controller.clearPrevious(id)
            reloadHistory(); details.string = "Deleted locally." } catch { statusLabel.stringValue = error.localizedDescription } }
    private func chooseURL(_ panel: NSSavePanel, completion: @escaping (URL) -> Void) {
        guard let window, window.attachedSheet == nil, !controller.preparingToQuit else { return }
        panel.beginSheetModal(for: window) { response in
            if response == .OK, let url = panel.url { completion(url) }
        }
    }

    func exportHistory() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Keydown-history.json"
        chooseURL(panel) { [weak self] url in
            guard let self else { return }
            do {
                let records = try self.controller.history?.records() ?? []
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                encoder.dateEncodingStrategy = .iso8601
                try encoder.encode(records).write(to: url, options: .atomic)
                self.statusLabel.stringValue = "History exported"
            } catch { self.statusLabel.stringValue = error.localizedDescription }
        }
    }
    func dictionaryPage() {
        fillWidth(label("Names worth getting right", size: 22, weight: .semibold))
        fillWidth(label("Add one name or term per line. Bundled and system recognition use bounded local hints. Exact spelling is preserved during prose formatting; hints do not guarantee recognition or create fuzzy replacements."))
        let terms = (try? controller.history?.dictionary()) ?? []
        let (view, scroller) = editor(terms.joined(separator: "\n"), height: 260); words = view; words.setAccessibilityLabel("Vocabulary"); fillWidth(scroller)
        addDraftButtons("Save vocabulary", page: 1)
    }
    func snippetsPage() {
        snippetRows = []
        fillWidth(label("A few words, a longer message", size: 22, weight: .semibold))
        fillWidth(label("Say a trigger by itself to insert its full text. Expansions preserve your line breaks."))
        let stack = column(16)
        snippetStack = stack
        fillWidth(stack)
        let values = (try? controller.history?.values(table: "expansions")) ?? [:]
        for key in values.keys.sorted() { addSnippet(key, value: values[key] ?? "") }
        if values.isEmpty { addSnippet("", value: "") }
        fillWidth(ActionButton("Add expansion") { [weak self] in self?.addSnippet("", value: "") })
        addDraftButtons("Save expansions", page: 2)
    }
    func addSnippet(_ trigger: String, value: String) {
        guard let stack = snippetStack else { return }
        let field = NSTextField(string: trigger)
        field.placeholderString = "Spoken trigger"
        field.setAccessibilityLabel("Spoken trigger")
        let (text, scroller) = editor(value, height: 76)
        text.setAccessibilityLabel("Expansion text")
        let container = column(6)
        container.addArrangedSubview(field)
        container.addArrangedSubview(scroller)
        stack.addArrangedSubview(container)
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalTo: stack.widthAnchor),
            field.widthAnchor.constraint(equalTo: container.widthAnchor),
            scroller.widthAnchor.constraint(equalTo: container.widthAnchor),
        ])
        snippetRows.append((field, text))
    }
    func stylesPage() {
        styleRows = []; fillWidth(label("A voice for each app", size: 22, weight: .semibold))
        fillWidth(label("Choose neutral, formal, or casual wording for an application. Neutral keeps your own phrasing."))
        let stack = column(); styleStack = stack
        let styles = (try? controller.history?.values(table: "app_styles")) ?? [:]
        for key in styles.keys.sorted() { addStyle(key, style: styles[key] ?? "neutral") }
        if styles.isEmpty { addStyle("", style: "neutral") }
        fillWidth(stack)
        fillWidth(row([ActionButton("Add app") { [weak self] in self?.addStyle("", style: "neutral") }, ActionButton("Choose application…") { [weak self] in self?.chooseApp() }]))
        addDraftButtons("Save styles", page: 3)
        fillWidth(label("Enable local text context in Settings to include selected and nearby words as spelling hints. Protected fields are excluded."))
    }
    func addStyle(_ app: String, style: String) {
        guard let stack = styleStack else { return }
        let field = NSTextField(string: app); field.placeholderString = "Application identifier"; field.setAccessibilityLabel("Application identifier"); field.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        let picker = NSPopUpButton(); picker.addItems(withTitles: WritingStyle.allCases.map(\.rawValue)); picker.selectItem(withTitle: style)
        let controls = row([field, picker]); stack.addArrangedSubview(controls)
        controls.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        styleRows.append((field, picker))
    }
    func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        chooseURL(panel) { [weak self] url in
            if let id = Bundle(url: url)?.bundleIdentifier { self?.addStyle(id, style: "neutral") }
        }
    }
    func settingsPage() {
        fillWidth(label("Make room for your voice", size: 22, weight: .semibold))
        let body = column(14); checks = [:]; fields = [:]
        let prefs = controller.preferences
        body.addArrangedSubview(label(BuildInfo.summary, size: 11))
        body.addArrangedSubview(ActionButton("Export diagnostics…") { [weak self] in self?.exportDiagnostics() })
        body.addArrangedSubview(row([ActionButton("Practice dictation") { [weak self] in self?.controller.showPractice() }, ActionButton("Preview indicator") { [weak self] in
            guard let self, self.controller.sessions.canStart else { return }; self.controller.indicator.preview()
        }, ActionButton("Reset indicator position") { [weak self] in
            guard let self, self.controller.sessions.canStart else { return }; self.controller.indicator.preview(reset: true)
        }]))
        body.addArrangedSubview(label("PERFORMANCE THIS SESSION", size: 10, weight: .semibold))
        let performance = label("")
        performanceLabel = performance
        body.addArrangedSubview(performance)
        body.addArrangedSubview(label("ACCESS & INSERTION", size: 10, weight: .semibold))
        permissionViews = [:]
        for (kind, title) in [(PermissionAccess.Kind.microphone, "Microphone"), (.speech, "Speech Recognition")] {
            let status = label("")
            let button = ActionButton("Request Access") { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    let opened = await self.permissions.perform(kind) { self.refreshPermissions() }
                    if !opened { self.statusLabel.stringValue = "Open System Settings → Privacy & Security → " + title + "." }
                }
            }
            permissionViews[kind] = (status, button)
            body.addArrangedSubview(status)
            body.addArrangedSubview(button)
        }
        body.addArrangedSubview(label("Automatic insertion needs Accessibility. Use Copy Previous Text when Keydown cannot verify the target."))
        body.addArrangedSubview(row([ActionButton("Accessibility…") { Self.privacy("Privacy_Accessibility") },
                                     ActionButton("Input Monitoring…") { Self.privacy("Privacy_ListenEvent") }]))
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
        body.addArrangedSubview(row([label("Microphone"), micPicker]))
        body.addArrangedSubview(row([label("Language"), languagePicker]))
        micPicker.widthAnchor.constraint(lessThanOrEqualToConstant: 320).isActive = true
        body.addArrangedSubview(label("Bundled recognition uses the same English model for India, US and UK. Regional locale selection applies to system providers. Bundled vocabulary hints stay local; approved custom decoders receive no hints."))
        retentionPicker = NSPopUpButton(); retentionPicker.addItems(withTitles: ["Keep history", "Delete after a day", "Never save history"]); retentionPicker.selectItem(at: Retention.allCases.firstIndex(of: prefs.retention) ?? 0)
        modePicker = NSPopUpButton(); modePicker.addItems(withTitles: DictationMode.allCases.map(\.title)); modePicker.selectItem(at: DictationMode.allCases.firstIndex(of: prefs.dictationMode) ?? 0)
        body.addArrangedSubview(row([label("Dictation behavior"), modePicker]))
        body.addArrangedSubview(label("Dictate prose formats speech. Exact text keeps recognized wording; say ‘spell A B hyphen zero zero seven’ for AB-007. Follow app preference preserves code in editors and terminals."))
        body.addArrangedSubview(label("EVERYDAY PREFERENCES", size: 10, weight: .semibold))
        appearancePicker = NSPopUpButton()
        appearancePicker.addItems(withTitles: ["System", "Light", "Dark"])
        appearancePicker.selectItem(at: AppAppearance.allCases.firstIndex(of: prefs.appearance) ?? 0)
        body.addArrangedSubview(row([label("Appearance"), appearancePicker]))
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
        enginePicker.target = self
        enginePicker.action = #selector(refreshEnginePermissions)
        body.addArrangedSubview(row([label("Speech engine"), enginePicker]))
        for (key, title, value) in [("pauseMedia", "Pause current media before dictation", prefs.pauseMedia), ("hold", "Enable the selected hold-to-talk key", prefs.holdEnabled), ("code", "Preserve exact syntax in code editors and terminals", prefs.preserveCode), ("hands", "Hands-free: finish after silence", prefs.handsFree), ("context", "Use selected and nearby text as local spelling context", prefs.contextEnabled), ("audio", "Keep recordings on this Mac (off by default)", prefs.keepAudio)] {
            let check = NSButton(checkboxWithTitle: title, target: nil, action: nil); check.state = value ? .on : .off; checks[key] = check; body.addArrangedSubview(check)
        }
        body.addArrangedSubview(label("Media stays paused afterward. Pause targets the macOS Now Playing session; unsupported or simultaneous players may need manual pausing. No system volume changes."))
        let holdHelp = prefs.holdKey == .globe ? "Set Keyboard → Press globe key → Do Nothing to avoid the emoji picker." : "Your chosen hold key is passed through to the app you are using."
        body.addArrangedSubview(label("Hold your chosen key by itself. " + holdHelp + " Editing: Control Option R. Paste previous: Control Option V."))
        for (key, title, value) in [("silence", "Silence before hands-free finishes (seconds)", prefs.silenceSeconds), ("maximum", "Maximum recording (seconds)", prefs.maximumSeconds), ("clipboard", "Clipboard recovery delay (seconds)", prefs.clipboardDelay)] {
            let input = NSTextField(string: String(value)); input.setAccessibilityLabel(title); input.widthAnchor.constraint(equalToConstant: 80).isActive = true; fields[key] = input; body.addArrangedSubview(row([label(title), input]))
        }
        let modelCleanup = NSButton(checkboxWithTitle: "Use validated on-device punctuation cleanup", target: nil, action: nil)
        modelCleanup.state = prefs.useModel && controller.modelPassValidated ? .on : .off
        modelCleanup.isEnabled = controller.modelPassValidated; checks["model"] = modelCleanup; body.addArrangedSubview(modelCleanup)
        let summary = label("")
        validationSummary = summary
        body.addArrangedSubview(summary)
        let validate = ActionButton("Validate local cleanup") { [weak self] in
            self?.controller.validateCleanup()
            self?.refreshValidation()
        }
        validationButton = validate
        body.addArrangedSubview(validate)
        body.addArrangedSubview(ActionButton("Refresh permission status") { [weak self] in self?.refreshPermissions() })
        body.addArrangedSubview(row([ActionButton("Choose speech model…") { [weak self] in self?.chooseSpeechModel() }, ActionButton("Choose decoder…") { [weak self] in self?.chooseDecoder() }]))
        fillWidth(body)
        for item in body.arrangedSubviews {
            item.widthAnchor.constraint(lessThanOrEqualTo: body.widthAnchor).isActive = true
        }
        addDraftButtons("Save settings", page: 4)
        refreshValidation()
    }

    @objc private func refreshEnginePermissions() { refreshPermissions() }

    private func refreshCapturePermissions(trusted: Bool) {
        let showsSpeech = enginePicker.indexOfSelectedItem == SpeechEngine.allCases.firstIndex(of: .systemLegacy)
        for (kind, views) in permissionViews {
            let (label, button) = views
            let state = permissions.status(kind)
            let title = kind == .microphone ? "Microphone" : "Speech Recognition"
            let hidden = kind == .speech && !showsSpeech
            label.isHidden = hidden
            button.isHidden = hidden
            let insertion = kind == .microphone ? " · Accessibility: " + (trusted ? "Allowed" : "Needed for insertion") : ""
            label.stringValue = title + ": " + state.text + insertion
            button.title = state.buttonTitle
            button.setAccessibilityLabel(title + " — " + button.title)
            button.invalidateIntrinsicContentSize()
            button.isEnabled = state.canAct && !permissions.pending.contains(kind)
        }
    }

    private func refreshValidation() {
        guard let validationSummary else { return }
        let eligible = controller.modelPassValidated
        checks["model"]?.isEnabled = eligible
        validationButton?.isEnabled = controller.validationTask == nil
        validationButton?.title = controller.validationTask == nil ? "Validate local cleanup" : "Validation in progress…"
        validationButton?.invalidateIntrinsicContentSize()
        validationSummary.stringValue = CleanupQualification.load().map {
            "Cleanup checks: \($0.passed)/\($0.cases); 95th percentile \(String(format: "%.2f", $0.p95Seconds)) s."
        } ?? "Validate the installed on-device model before enabling cleanup. Slow or changed content falls back to rules."
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
    func chooseSpeechModel() {
        chooseURL(NSOpenPanel()) { [weak self] url in
            guard let self else { return }
            var proposed = self.controller.preferences
            proposed.customSpeechModel = url.path
            do {
                let warning = try self.controller.savePreferences(proposed)
                self.statusLabel.stringValue = warning ?? "Local speech model selected"
            } catch { self.statusLabel.stringValue = "Could not save the speech model selection." }
        }
    }

    func chooseDecoder() {
        chooseURL(NSOpenPanel()) { [weak self] url in
            // The open panel must finish before the approval sheet is attached.
            DispatchQueue.main.async { self?.confirmDecoder(url) }
        }
    }

    private func confirmDecoder(_ url: URL) {
        guard let window, window.attachedSheet == nil, !controller.preparingToQuit else { return }
        let confirmation = NSAlert()
        confirmation.messageText = "Approve this custom decoder?"
        confirmation.informativeText = "Keydown runs this program as your user and gives it your microphone recording. Choose only software you trust."
        confirmation.addButton(withTitle: "Approve Decoder")
        confirmation.addButton(withTitle: "Cancel")
        confirmation.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            self.approveDecoder(url)
        }
    }

    private func approveDecoder(_ url: URL) {
        do {
            let approval = try DecoderApproval(executable: url)
            var proposed = controller.preferences
            proposed.customSpeechExecutable = url.path
            proposed.decoderApproval = approval
            proposed.speechEngine = .custom
            let warning = try controller.savePreferences(proposed)
            if case .settings(var baseline) = drafts[4],
               baseline["engine"] == String(enginePicker.indexOfSelectedItem),
               let index = SpeechEngine.allCases.firstIndex(of: .custom) {
                enginePicker.selectItem(at: index)
                baseline["engine"] = String(index)
                drafts[4] = .settings(baseline)
                refreshPermissions()
            }
            statusLabel.stringValue = warning ?? "Custom decoder approved"
        } catch {
            statusLabel.stringValue = error.localizedDescription
        }
    }
    private func workingDraft(_ page: Int) -> HubDraft? {
        switch page {
        case 1: return .vocabulary(words.string)
        case 2: return .rows(snippetRows.map { HubDraftRow(key: $0.0.stringValue, value: $0.1.string) })
        case 3: return .rows(styleRows.map { HubDraftRow(key: $0.0.stringValue, value: $0.1.titleOfSelectedItem ?? "neutral") })
        case 4:
            var values = fields.mapValues(\.stringValue)
            for (name, check) in checks { values[name] = check.state == .on ? "1" : "0" }
            for (name, picker) in [("language", languagePicker), ("retention", retentionPicker), ("toggle", hotkeyPicker),
                                   ("holdKey", holdPicker), ("engine", enginePicker), ("mode", modePicker), ("appearance", appearancePicker)] {
                values[name] = String(picker.indexOfSelectedItem)
            }
            if micIDs.indices.contains(micPicker.indexOfSelectedItem) {
                values["mic"] = String(micIDs[micPicker.indexOfSelectedItem])
            }
            return .settings(values)
        default: return nil
        }
    }

    private func refreshVocabulary() {
        guard !drafts.isDirty(1, working: workingDraft(1)),
              let terms = try? controller.history?.dictionary() else { return }
        let text = terms.joined(separator: "\n")
        if words.string != text {
            words.string = text
            drafts[1] = .vocabulary(text)
        }
    }

    private func addDraftButtons(_ title: String, page: Int) {
        fillWidth(row([
            ActionButton(title, primary: true) { [weak self] in _ = self?.saveDraft(page) },
            ActionButton("Revert changes") { [weak self] in
                guard let self, self.window?.makeFirstResponder(nil) != false else { return }
                self.discardDraft(page)
            },
        ]))
    }

    @objc func saveCurrentDraft(_ sender: Any?) { _ = saveDraft(page) }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        !resolvingDrafts && window?.attachedSheet == nil && drafts.isDirty(page, working: workingDraft(page))
    }

    private func saveDraft(_ page: Int) -> Bool {
        guard window?.makeFirstResponder(nil) != false,
              let working = workingDraft(page) else { return false }
        guard drafts.isDirty(page, working: working) else { return true }
        do {
            var warning: String?
            switch working {
            case .vocabulary(let text):
                guard let history = controller.history, case .vocabulary(let baseline) = drafts[page] else {
                    throw MurmurError.unavailable("Vocabulary storage is unavailable.")
                }
                let terms = HubDrafts.vocabulary(text, baseline: baseline, latest: try history.dictionary())
                try history.setDictionary(terms)
                words.string = terms.joined(separator: "\n")
            case .rows(let rows):
                guard let history = controller.history else { throw MurmurError.unavailable("Local storage is unavailable.") }
                var values: [String: String] = [:]
                for row in rows {
                    let trimmed = row.key.trimmingCharacters(in: .whitespacesAndNewlines)
                    let key = page == 2 ? trimmed.lowercased() : trimmed
                    if key.isEmpty { continue }
                    guard values[key] == nil else { throw MurmurError.unavailable("Each entry must have a unique identifier.") }
                    values[key] = row.value
                }
                try history.setValues(values, table: page == 2 ? "expansions" : "app_styles")
            case .settings(let values):
                guard case .settings(let baseline) = drafts[page] else { return false }
                warning = try controller.savePreferences(try changedSettings(values, baseline: baseline))
            }
            drafts[page] = workingDraft(page)
            statusLabel.stringValue = warning ?? "Changes saved"
            refreshPermissions()
            // Leave the window open so a retention failure can be seen.
            return warning == nil
        } catch {
            statusLabel.stringValue = error.localizedDescription
            return false
        }
    }

    private func changedSettings(_ values: [String: String], baseline: [String: String]) throws -> Preferences {
        var preferences = controller.preferences
        func assign<Value>(_ key: String, _ path: WritableKeyPath<Preferences, Value>, _ value: Value) {
            if values[key] != baseline[key] { preferences[keyPath: path] = value }
        }
        func pick<Value>(_ key: String, _ choices: [Value]) -> Value {
            let index = Int(values[key] ?? "") ?? 0
            return choices[choices.indices.contains(index) ? index : 0]
        }
        func number(_ key: String, _ range: ClosedRange<Double>) throws -> Double {
            guard let value = Double(values[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""),
                  value.isFinite, range.contains(value) else {
                throw MurmurError.unavailable("Enter a value from \(range.lowerBound) to \(range.upperBound) for \(key).")
            }
            return value
        }
        assign("appearance", \.appearance, pick("appearance", AppAppearance.allCases))
        assign("mic", \.microphone, UInt32(values["mic"] ?? "") ?? 0)
        assign("language", \.language, pick("language", ["en-US", "en-IN", "en-GB"]))
        assign("mode", \.dictationMode, pick("mode", DictationMode.allCases))
        assign("retention", \.retention, pick("retention", Retention.allCases))
        assign("toggle", \.toggleKey, pick("toggle", [49, 2]))
        assign("holdKey", \.holdKey, pick("holdKey", HoldKey.allCases))
        assign("engine", \.speechEngine, pick("engine", SpeechEngine.allCases))
        assign("pauseMedia", \.pauseMedia, values["pauseMedia"] == "1")
        assign("hold", \.holdEnabled, values["hold"] == "1")
        assign("code", \.preserveCode, values["code"] == "1")
        assign("hands", \.handsFree, values["hands"] == "1")
        assign("context", \.contextEnabled, values["context"] == "1")
        assign("audio", \.keepAudio, values["audio"] == "1")
        if values["model"] != baseline["model"] {
            guard values["model"] != "1" || controller.modelPassValidated else {
                throw MurmurError.unavailable("Validate local cleanup before enabling it.")
            }
            preferences.useModel = values["model"] == "1"
        }
        if values["silence"] != baseline["silence"] { preferences.silenceSeconds = try number("silence", 0.5...10) }
        if values["maximum"] != baseline["maximum"] { preferences.maximumSeconds = try number("maximum", 5...600) }
        if values["clipboard"] != baseline["clipboard"] { preferences.clipboardDelay = try number("clipboard", 0.1...2) }
        return preferences
    }

    private func discardDraft(_ index: Int) {
        pageViews[index]?.0.removeFromSuperview()
        pageViews[index] = nil
        drafts[index] = nil
        if index == page { render() }
    }

    func resolveDrafts(completion: @escaping (Bool) -> Void) {
        guard !resolvingDrafts, let window, window.attachedSheet == nil,
              window.makeFirstResponder(nil) else { completion(false); return }
        let dirty = drafts.pages.filter { drafts.isDirty($0, working: workingDraft($0)) }
        guard !dirty.isEmpty else { completion(true); return }
        resolvingDrafts = true
        controller.presentation.present(window)
        let alert = NSAlert()
        alert.messageText = "Save your changes to Keydown?"
        alert.informativeText = "You have unsaved changes in one or more pages."
        alert.addButton(withTitle: "Save Changes")
        alert.addButton(withTitle: "Discard Changes")
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { completion(false); return }
            self.resolvingDrafts = false
            switch response {
            case .alertFirstButtonReturn:
                for index in dirty where !self.saveDraft(index) {
                    let message = self.statusLabel.stringValue
                    self.selectPage(index)
                    self.statusLabel.stringValue = message
                    completion(false)
                    return
                }
                completion(true)
            case .alertSecondButtonReturn:
                for index in dirty { self.discardDraft(index) }
                completion(true)
            default:
                completion(false)
            }
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !resolvingDrafts, sender.attachedSheet == nil, sender.makeFirstResponder(nil) else { return false }
        if !drafts.pages.contains(where: { drafts.isDirty($0, working: workingDraft($0)) }) { return true }
        resolveDrafts { allowed in
            if allowed { DispatchQueue.main.async { sender.close() } }
        }
        return false
    }

    func windowDidFailToEnterFullScreen(_ window: NSWindow) { placement?.fullscreenTransitionFailed() }

    func windowDidFailToExitFullScreen(_ window: NSWindow) { placement?.fullscreenTransitionFailed() }

    func windowWillClose(_ notification: Notification) { hubStart = nil }

    func exportDiagnostics() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Keydown-diagnostics.json"
        chooseURL(panel) { [weak self] url in self?.writeDiagnostics(to: url) }
    }

    private func writeDiagnostics(to url: URL) {
        do {
            let data = try JSONSerialization.data(withJSONObject: LiveDiagnostics.snapshot(controller: controller), options: [.prettyPrinted, .sortedKeys])
            let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
            guard fd >= 0 else { statusLabel.stringValue = "Choose a new filename for the diagnostic report"; return }
            let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
            defer { try? handle.close() }
            try handle.write(contentsOf: data)
            statusLabel.stringValue = "Diagnostics exported · no audio, transcript or clipboard contents"
        } catch { statusLabel.stringValue = "Could not export diagnostics" }
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
