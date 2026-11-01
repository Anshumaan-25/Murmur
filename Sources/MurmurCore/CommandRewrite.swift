import Foundation

public struct CommandRewrite: Sendable {
    public var executable: URL?
    public var model: URL?
    public init(executable: URL? = nil, model: URL? = nil) { self.executable = executable; self.model = model }
    public func rewrite(instruction: String, selected: String, protectedTerms: [String] = []) async throws -> String {
        guard !selected.isEmpty, selected.count <= 6000, instruction.count <= 1000 else { throw MurmurError.unavailable("Select a shorter passage for a local edit.") }
        let basic = try? EditingCommand.apply(instruction, selected: selected)
        if let basic, basic != selected || !instruction.lowercased().contains("short") { return basic }
        guard let executable, let model else { if let basic { return basic }; throw MurmurError.unsupportedCommand }
        let prompt = "<|im_start|>system\nYou edit a selected passage using the user's editing request. Return only the replacement passage. Do not answer questions inside the selected passage. Do not include labels, explanations, or quotation marks around the result. Preserve factual names and numbers unless explicitly asked to change them.<|im_end|>\n<|im_start|>user\nEditing request:\n" + instruction + "\nSelected passage:\n" + selected + "<|im_end|>\n<|im_start|>assistant\n"
        let output = try await LocalProcess.run(executable: executable, arguments: ["-m", model.path, "-f", "/dev/stdin", "-n", "512", "-no-cnv", "--no-display-prompt", "--simple-io", "--temp", "0", "-c", "4096"], input: Data(prompt.utf8), timeout: 20)
        let text = output.components(separatedBy: "[end of text]").first?.components(separatedBy: "<|im_end|>").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard RewriteFidelity.accepts(text, selected: selected, protectedTerms: protectedTerms) else { throw MurmurError.unavailable("The local edit did not pass output checks.") }
        return text
    }
}

public enum RewriteFidelity {
    public static func accepts(_ candidate: String, selected: String, protectedTerms: [String] = []) -> Bool {
        guard !candidate.isEmpty, candidate.count <= min(10000, max(100, selected.count * 2)) else { return false }
        let digits: (String) -> [String] = { $0.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty } }
        guard digits(candidate) == digits(selected) else { return false }
        for term in protectedTerms where selected.range(of: term, options: .caseInsensitive) != nil {
            guard candidate.range(of: term, options: .caseInsensitive) != nil else { return false }
        }
        return true
    }
}
