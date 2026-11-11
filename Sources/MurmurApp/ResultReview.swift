import AppKit
import MurmurCore

/// Opened only by an explicit user action. Copy never posts input to another app.
@MainActor final class ResultReviewController: NSWindowController, NSWindowDelegate, NSTextViewDelegate {
    private let recognized = NSTextView()
    private let formatted = NSTextView()
    private let summary = NSTextField(wrappingLabelWithString: "")
    private var placement: WindowPlacement?
    private let presentation: AppPresentation
    private let board: NSPasteboard
    var learnTerm: ((String) throws -> Void)?
    var practiceAction: (() -> Void)?
    var closed: (() -> Void)?
    var rawText: String { recognized.string }
    var formattedText: String { formatted.string }

    convenience init(board: NSPasteboard = .general, practice: Bool = false) {
        self.init(board: board, role: practice ? .practice : .historyReview,
                  presentation: AppPresentation(), geometryDefaults: nil)
    }

    init(board: NSPasteboard = .general, role: WorkspaceRole, presentation: AppPresentation,
         geometryDefaults: UserDefaults?) {
        self.board = board
        self.presentation = presentation
        let practice = role == .practice
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 470), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = role == .suggestionReview ? "Review suggested edit" : practice ? "Practice dictation" : "Review dictation"
        window.collectionBehavior = [.primary, .fullScreenPrimary]
        window.isRestorable = false
        window.minSize = NSSize(width: 650, height: 400); window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self; formatted.delegate = self
        let content = NSStackView(); content.orientation = .vertical; content.alignment = .leading; content.spacing = 14
        content.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        let instruction = NSTextField(wrappingLabelWithString: practice
            ? "Keep this window focused. Hold your dictation key or use Start / stop. These practice results stay in this window and are not saved to history."
            : "Compare both versions. Names and meaning need your review, even when automated checks pass. Edit the result, then copy deliberately.")
        content.addArrangedSubview(instruction)
        let columns = NSStackView(); columns.orientation = .horizontal; columns.spacing = 16; columns.distribution = .fillEqually
        for (title, view, editable) in [("Recognized", recognized, false), ("Result · editable", formatted, true)] {
            let column = NSStackView(); column.orientation = .vertical; column.alignment = .leading; column.spacing = 8
            column.addArrangedSubview(NSTextField(labelWithString: title))
            let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
            view.isEditable = editable; view.isRichText = false; view.allowsUndo = editable
            view.font = .systemFont(ofSize: 14); view.textContainerInset = NSSize(width: 10, height: 10)
            view.isVerticallyResizable = true; view.autoresizingMask = [.width]
            view.textContainer?.widthTracksTextView = true
            view.setAccessibilityLabel(title)
            scroll.documentView = view; column.addArrangedSubview(scroll)
            scroll.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
            columns.addArrangedSubview(column)
        }
        content.addArrangedSubview(columns)
        columns.heightAnchor.constraint(greaterThanOrEqualToConstant: 210).isActive = true
        content.addArrangedSubview(summary)
        let buttons = NSStackView(); buttons.orientation = .horizontal; buttons.spacing = 10
        if practice { buttons.addArrangedSubview(ActionButton("Start / stop") { [weak self] in self?.practiceAction?() }) }
        buttons.addArrangedSubview(ActionButton("Copy result", primary: true) { [weak self] in self?.copyFormatted() })
        buttons.addArrangedSubview(ActionButton("Add spelling to vocabulary…") { [weak self] in self?.addTerm() })
        buttons.addArrangedSubview(ActionButton("Clear") { [weak self] in self?.clear() })
        content.addArrangedSubview(buttons)
        window.contentView = content
        for view in [instruction, columns, summary] { view.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -36).isActive = true }
        placement = WindowPlacement(window: window, role: role, defaults: geometryDefaults)
    }
    required init?(coder: NSCoder) { fatalError("Unsupported initializer") }
    func update(raw: String, cleaned: String, outcome: String) {
        recognized.string = raw; formatted.string = cleaned; formatted.undoManager?.removeAllActions()
        summary.stringValue = outcome + (raw == cleaned ? " · Wording unchanged" : " · Changes highlighted; check names, numbers and meaning")
        highlightChanges()
    }
    func textDidChange(_ notification: Notification) { highlightChanges() }
    private func highlightChanges() {
        let difference = ReviewDifference.between(recognized.string, formatted.string)
        for (view, range) in [(recognized, difference.original), (formatted, difference.result)] {
            view.textStorage?.removeAttribute(.backgroundColor, range: NSRange(location: 0, length: view.string.utf16.count))
            if range.length > 0 { view.textStorage?.addAttribute(.backgroundColor, value: NSColor.systemYellow.withAlphaComponent(0.22), range: range) }
        }
    }
    func present() { if let window { presentation.present(window) } }
    func copyFormatted() {
        guard !formatted.string.isEmpty else { return }
        board.clearContents()
        summary.stringValue = board.setString(formatted.string, forType: .string) ? "Copied result" : "Could not copy result"
    }
    func clear() {
        recognized.string = ""; formatted.string = ""; formatted.undoManager?.removeAllActions(); summary.stringValue = "Cleared"
    }
    func windowDidFailToEnterFullScreen(_ window: NSWindow) { placement?.fullscreenTransitionFailed() }

    func windowDidFailToExitFullScreen(_ window: NSWindow) { placement?.fullscreenTransitionFailed() }

    func windowWillClose(_ notification: Notification) { clear(); closed?() }
    private func addTerm() {
        guard let window, window.attachedSheet == nil else { return }
        guard learnTerm != nil else { summary.stringValue = "Vocabulary storage is unavailable"; return }
        let alert = NSAlert(); alert.messageText = "Add a spelling hint"
        alert.informativeText = "Enter one name or term exactly as you want it spelled. This adds a local recognition hint; it does not create an automatic replacement."
        let entry = NSTextField(frame: NSRect(x: 0, y: 0, width: 350, height: 24))
        let selection = formatted.selectedRange()
        if selection.length > 0, let range = Range(selection, in: formatted.string) { entry.stringValue = String(formatted.string[range]) }
        alert.accessoryView = entry; alert.addButton(withTitle: "Save hint"); alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self, self.window?.isVisible == true else { return }
            let terms = SpeechRequest.vocabulary([entry.stringValue])
            guard let term = terms.first else {
                self.summary.stringValue = "Use a short name or term without control characters"
                return
            }
            do { try self.learnTerm?(term); self.summary.stringValue = "Vocabulary hint saved" }
            catch { self.summary.stringValue = "Could not save the vocabulary hint" }
        }
    }
}
