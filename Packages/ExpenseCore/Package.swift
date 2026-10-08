// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ExpenseCore",
    defaultLocalization: "ru",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "ExpenseCore", targets: ["ExpenseCore"])
    ],
    targets: [
        .target(name: "ExpenseCore"),
        .testTarget(name: "ExpenseCoreTests", dependencies: ["ExpenseCore"])
    ]
)
