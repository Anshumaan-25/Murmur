import Foundation

public enum BuildInfo {
    public static var details: [String: Any] {
        guard let url = Bundle.main.url(forResource: "build-info", withExtension: "json"),
              let data = try? Data(contentsOf: url), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ["version": "development", "source_sha256": "unpackaged"]
        }
        return object
    }
    public static var summary: String {
        let info = details
        return "Keydown \(info["version"] as? String ?? "development") · \((info["source_sha256"] as? String ?? "unpackaged").prefix(12))"
    }
}
