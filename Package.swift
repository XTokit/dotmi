// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "Xunji", platforms: [.macOS(.v13)], products: [.executable(name: "Xunji", targets: ["Xunji"])], targets: [
    .systemLibrary(name: "CSQLite"),
    .target(name: "SearchCore", dependencies: ["CSQLite"]),
    .executableTarget(name: "Xunji", dependencies: ["SearchCore"]),
    .executableTarget(name: "SearchChecks", dependencies: ["SearchCore", "CSQLite"], path: "Tests/SearchCoreTests")
])
