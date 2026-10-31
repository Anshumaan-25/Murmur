// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Murmur",
    platforms: [.macOS("26.0")],
    products: [.library(name: "MurmurCore", targets: ["MurmurCore"]), .executable(name: "Murmur", targets: ["MurmurApp"]), .executable(name: "murmur-bench", targets: ["MurmurBench"])],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .target(name: "MurmurCore", dependencies: ["CSQLite"]),
        .executableTarget(name: "MurmurApp", dependencies: ["MurmurCore"]),
        .executableTarget(name: "MurmurBench", dependencies: ["MurmurCore"]),
        .executableTarget(name: "murmur-tests", dependencies: ["MurmurCore"], path: "tests", sources: ["CoreTests.swift"], resources: [.copy("golden")])
    ], swiftLanguageModes: [.v5]
)
