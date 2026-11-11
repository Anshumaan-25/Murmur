import Foundation

struct HubDraftRow: Equatable {
    var key: String
    var value: String
}

enum HubDraft: Equatable {
    case vocabulary(String)
    case rows([HubDraftRow])
    case settings([String: String])
}

struct HubDrafts {
    private var saved: [Int: HubDraft] = [:]

    subscript(page: Int) -> HubDraft? {
        get { saved[page] }
        set { saved[page] = newValue }
    }

    var pages: [Int] { saved.keys.sorted() }

    func isDirty(_ page: Int, working: HubDraft?) -> Bool {
        guard let baseline = saved[page], let working else { return false }
        return baseline != working
    }

    static func vocabulary(_ text: String, baseline: String, latest: [String]) -> [String] {
        func terms(_ value: String) -> Set<String> {
            Set(value.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty })
        }
        let original = terms(baseline)
        let edited = terms(text)
        return Set(latest).subtracting(original.subtracting(edited))
            .union(edited.subtracting(original)).sorted()
    }
}
