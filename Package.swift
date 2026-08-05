// swift-tools-version: 6.0
import PackageDescription

// flintfind's engine, as a package the way reepub's scan-ocr and epub-kit are packages: the library
// is the single implementation, and every door — the CLI here, marktile's editor later — reads THAT
// rather than a copy of it. reepub's Package.swift carries the scar this avoids; its app and its
// command-line binary each held a copy of the OCR engine, and one of them claimed to be in sync in
// a comment nothing verified.
//
// Naming follows the same house form: a lowercase-hyphen directory and package, an UpperCamel
// module, a `<Module>CLI` target.
//
// THE GATE IS AN EXECUTABLE, NOT A testTarget, and that is not a preference. XCTest lives inside
// Xcode.app and swift-testing did not resolve either; this machine has Command Line Tools only, so
// `swift test` cannot run here at all. reepub reached the same place and ships ReepubSelfTest as an
// executable product — run it, it exits non-zero when something is wrong. That also keeps the gate
// runnable in exactly the way the Python one is: `python3 test_ff.py` and `swift run
// flintfind-selftest` are the same gesture.
//
// ONE DELIBERATE DEVIATION. reepub names each executable after its package (`scan-ocr`, `epub-kit`);
// this one is `ff`. That is not an oversight — the command is typed fifty times a day and the short
// form is the point, the way ripgrep ships as `rg`. flintfind is the name; ff is what you press.
let package = Package(
    name: "flintfind-kit",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "FlintfindKit", targets: ["FlintfindKit"]),
        .executable(name: "ff", targets: ["FlintfindCLI"]),
        .executable(name: "flintfind-selftest", targets: ["FlintfindSelfTest"]),
    ],
    targets: [
        .target(name: "FlintfindKit"),
        .executableTarget(name: "FlintfindCLI", dependencies: ["FlintfindKit"]),
        .executableTarget(name: "FlintfindSelfTest", dependencies: ["FlintfindKit"]),
    ]
)
