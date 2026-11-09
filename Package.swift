// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Keydown",
    platforms: [.macOS("26.0")],
    products: [.library(name: "MurmurCore", targets: ["MurmurCore"]), .executable(name: "Keydown", targets: ["MurmurApp"]), .executable(name: "murmur-bench", targets: ["MurmurBench"])],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .target(name: "MurmurCore", dependencies: ["CSQLite"]),
        .executableTarget(name: "MurmurApp", dependencies: ["MurmurCore"]),
        .executableTarget(name: "MurmurBench", dependencies: ["MurmurCore"]),
        .executableTarget(name: "murmur-tests", dependencies: ["MurmurCore"], path: "tests", exclude: ["audio", "PasteTarget.swift", "PackagingChecks.py", "SpeechProtocolChecks.py", "QualityChecks.py"], sources: ["CoreTests.swift", "PolishTests.swift"], resources: [.copy("golden")])
    ], swiftLanguageModes: [.v5]
)
