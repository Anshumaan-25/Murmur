// swift-tools-version: 6.0
import PackageDescription
import Foundation

// Standalone Apple Command Line Tools ship the Testing macros in a nested
// directory that SwiftPM's default plugin search path can miss.
var testingSettings: [SwiftSetting] = []
if let sdk = Context.environment["SDKROOT"] {
    let developer = URL(fileURLWithPath: sdk).deletingLastPathComponent().deletingLastPathComponent()
    let plugins = developer.appendingPathComponent("usr/lib/swift/host/plugins/testing")
    if developer.lastPathComponent == "CommandLineTools",
       FileManager.default.fileExists(atPath: plugins.appendingPathComponent("libTestingMacros.dylib").path) {
        testingSettings = [.unsafeFlags(["-plugin-path", plugins.path])]
    }
}
let package = Package(
    name: "Keydown",
    platforms: [.macOS("26.0")],
    products: [.library(name: "MurmurCore", targets: ["MurmurCore"]), .executable(name: "Keydown", targets: ["MurmurApp"]), .executable(name: "murmur-bench", targets: ["MurmurBench"])],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .target(name: "MurmurCore", dependencies: ["CSQLite"]),
        .executableTarget(name: "MurmurApp", dependencies: ["MurmurCore"]),
        .executableTarget(name: "MurmurBench", dependencies: ["MurmurCore"]),
        .executableTarget(name: "murmur-tests", dependencies: ["MurmurCore"], path: "tests", exclude: ["audio", "PasteTarget.swift", "PackagingChecks.py", "SpeechProtocolChecks.py", "QualityChecks.py"], sources: ["CoreTests.swift", "PolishTests.swift"], resources: [.copy("golden")]),
        .testTarget(name: "DictationTests", dependencies: ["MurmurCore"], path: "PackageTests", swiftSettings: testingSettings)
    ], swiftLanguageModes: [.v5]
)
