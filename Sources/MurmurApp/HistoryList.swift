import AppKit
import MurmurCore

enum HistoryRow {
    case day(Date)
    case entry(Utterance)

    static func grouped(_ records: [Utterance], calendar: Calendar = .autoupdatingCurrent) -> [Self] {
        var result: [Self] = []
        var previousDay: Date?
        for record in records {
            let day = calendar.startOfDay(for: record.timestamp)
            if day != previousDay {
                result.append(.day(day))
                previousDay = day
            }
            result.append(.entry(record))
        }
        return result
    }

    var record: Utterance? {
        if case let .entry(value) = self { return value }
        return nil
    }

    static func heading(for day: Date) -> String {
        let calendar = Calendar.autoupdatingCurrent
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(date: .abbreviated, time: .omitted)
    }
}

final class HistoryTable: NSTableView {
    var copySelection: (() -> Void)?

    @objc func copy(_ sender: Any?) { copySelection?() }
}

final class HistoryEntryCell: NSTableCellView {
    private let transcript = NSTextField(labelWithString: "")
    private let context = NSTextField(labelWithString: "")
    private(set) var copyButton = NSButton()
    var onCopy: (() -> Void)?
    var selected = false { didSet { updateCopyVisibility() } }
    private var hovered = false
    private var tracking: NSTrackingArea?

    override init(frame: NSRect) {
        super.init(frame: frame)
        transcript.font = .systemFont(ofSize: 13, weight: .medium)
        context.font = .systemFont(ofSize: 11)
        context.textColor = .secondaryLabelColor
        for label in [transcript, context] {
            label.lineBreakMode = .byTruncatingTail
            label.usesSingleLineMode = true
            addSubview(label)
        }
        textField = transcript
        copyButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        copyButton.imagePosition = .imageOnly
        copyButton.isBordered = false
        copyButton.toolTip = "Copy Text"
        copyButton.setAccessibilityLabel("Copy Text")
        copyButton.target = self
        copyButton.action = #selector(copyText)
        addSubview(copyButton)
        updateCopyVisibility()
    }

    required init?(coder: NSCoder) { fatalError("Unsupported initializer") }

    func configure(_ record: Utterance, appName: String, selected: Bool, onCopy: @escaping () -> Void) {
        transcript.stringValue = record.cleaned
        context.stringValue = appName + " · " + record.timestamp.formatted(date: .omitted, time: .shortened)
        self.selected = selected
        self.onCopy = onCopy
    }

    override func layout() {
        super.layout()
        let width = max(0, bounds.width - 54)
        transcript.frame = NSRect(x: 8, y: bounds.midY + 1, width: width, height: 18)
        context.frame = NSRect(x: 8, y: bounds.midY - 17, width: width, height: 15)
        copyButton.frame = NSRect(x: bounds.maxX - 36, y: bounds.midY - 14, width: 28, height: 28)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(tracking!)
        hovered = window.map { $0.isKeyWindow && visibleRect.contains(convert($0.mouseLocationOutsideOfEventStream, from: nil)) } ?? false
        updateCopyVisibility()
    }

    override func mouseEntered(with event: NSEvent) { hovered = true; updateCopyVisibility() }
    override func mouseExited(with event: NSEvent) { hovered = false; updateCopyVisibility() }

    private func updateCopyVisibility() { copyButton.isHidden = !hovered && !selected }
    @objc private func copyText() { onCopy?() }
}
