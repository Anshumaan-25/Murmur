import Foundation
import CryptoKit

public struct CleanupFixture: Codable, Sendable {
    public var input: String
    public var expected: String
    public init(input: String, expected: String) { self.input = input; self.expected = expected }
    public static func bundled() throws -> [CleanupFixture] {
        guard let url = Bundle.main.url(forResource: "cleanup-cases", withExtension: "json") else { throw MurmurError.unavailable("Cleanup validation cases are missing. Rebuild the application.") }
        return try JSONDecoder().decode([Self].self, from: Data(contentsOf: url))
    }
    public static func fingerprint(_ cases: [CleanupFixture]) -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return SHA256.hash(data: (try? encoder.encode(cases)) ?? Data()).map { String(format: "%02x", $0) }.joined()
    }
}
public struct CleanupValidationResult: Codable, Sendable {
    public var qualification: CleanupQualification
    public var details: [Case]
    public struct Case: Codable, Sendable {
        public var index: Int
        public var passed: Bool
        public var seconds: Double
        public var usedModel: Bool
        public var reason: String
    }
}
public enum CleanupValidation {
    public static func run(_ cases: [CleanupFixture], budget: Double = 0.8) async throws -> CleanupValidationResult {
        guard cases.count >= 30, cases.count <= 200 else { throw MurmurError.unavailable("Use a validation suite containing 30 to 200 cases.") }
        guard SystemCleanup.available else { throw MurmurError.unavailable("The installed on-device language model is not ready.") }
        var details: [CleanupValidationResult.Case] = []
        for (index, fixture) in cases.enumerated() {
            try Task.checkCancellation()
            let result = await SystemCleanup(budget: budget).attempt(fixture.input, context: TextContext())
            details.append(.init(index: index, passed: result.text == fixture.expected, seconds: result.seconds, usedModel: result.usedModel, reason: result.reason))
        }
        let sorted = details.map(\.seconds).sorted()
        let p95 = sorted[min(sorted.count - 1, Int(ceil(Double(sorted.count) * 0.95)) - 1)]
        let report = CleanupQualification(cases: cases.count, passed: details.filter(\.passed).count, accepted: details.filter(\.usedModel).count, p95Seconds: p95, fixtureDigest: CleanupFixture.fingerprint(cases))
        return CleanupValidationResult(qualification: report, details: details)
    }
}
