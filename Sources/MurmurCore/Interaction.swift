import Foundation

public enum HoldKey: String, Codable, CaseIterable, Sendable {
    case globe, rightOption, rightControl, rightShift, f6
    public var title: String {
        switch self { case .globe: return "Fn / Globe"; case .rightOption: return "Right Option"; case .rightControl: return "Right Control"; case .rightShift: return "Right Shift"; case .f6: return "F6" }
    }
    public var code: UInt16 {
        switch self { case .globe: return 63; case .rightOption: return 61; case .rightControl: return 62; case .rightShift: return 60; case .f6: return 97 }
    }
    public var isModifier: Bool { self != .f6 }
}
public struct HoldGesture: Sendable {
    public private(set) var pressed = false
    public init() {}
    public mutating func change(to down: Bool) -> Bool? {
        guard down != pressed else { return nil }
        pressed = down; return down
    }
    public mutating func reset() -> Bool { let prior = pressed; pressed = false; return prior }
}
public enum ApplicationCategory: String, Codable, CaseIterable, Sendable {
    case email, chat, document, browser, code, terminal, other
    public var preservesSyntax: Bool { self == .code || self == .terminal }
    public static func classify(bundle: String, declaredCategory: String = "") -> ApplicationCategory {
        let identity = bundle.lowercased()
        if ["terminal", "iterm", "alacritty", "kitty", "ghostty", "wezterm"].contains(where: identity.contains) { return .terminal }
        if ["vscode", "vscodium", "xcode", "sublime", "jetbrains"].contains(where: identity.contains) || identity.hasSuffix(".zed") { return .code }
        if ["outlook", "superhuman", "airmail"].contains(where: identity.contains) || identity.hasSuffix(".mail") { return .email }
        if ["slack", "discord", "telegram", "whatsapp"].contains(where: identity.contains) || identity.hasSuffix(".ichat") { return .chat }
        if ["safari", "chrome", "firefox", "brave"].contains(where: identity.contains) { return .browser }
        if ["textedit", "notes", "pages", "obsidian", "notion"].contains(where: identity.contains) || identity.hasSuffix(".word") { return .document }
        if declaredCategory.lowercased().contains("developer-tools") { return .code }
        return .other
    }
}
public enum SpeechEngine: String, Codable, CaseIterable, Sendable {
    case automatic, bundled, systemAnalyzer, systemLegacy
    public var title: String {
        switch self { case .automatic: return "Automatic (local only)"; case .bundled: return "Bundled decoder"; case .systemAnalyzer: return "System analyzer"; case .systemLegacy: return "System dictation" }
    }
}
