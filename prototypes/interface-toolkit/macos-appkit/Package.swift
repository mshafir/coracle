// swift-tools-version:5.9
// PROTOTYPE, throwaway. Coracle issue #10: interface toolkit. Never merged.
import PackageDescription

let package = Package(
    name: "CoracleAppKit",
    platforms: [.macOS(.v14)],
    targets: [.executableTarget(name: "CoracleAppKit")]
)
