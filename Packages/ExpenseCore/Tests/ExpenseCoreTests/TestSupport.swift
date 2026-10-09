import Foundation
import Testing

/// UserDefaults с уникальным suite; домен удаляется вместе с объектом.
final class TemporaryDefaults {
    let suiteName: String
    let defaults: UserDefaults

    init() throws {
        let name = "ExpenseCoreTests.\(UUID().uuidString)"
        suiteName = name
        defaults = try #require(UserDefaults(suiteName: name))
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
    }
}

/// Файлы репозитория (дизайн-пакет, ассеты App) по пути от этого файла.
enum RepositoryFiles {
    /// Корень репозитория: над `Packages/ExpenseCore/Tests/ExpenseCoreTests/`.
    static let root = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    static func json(_ relativePath: String) throws -> Any {
        try JSONSerialization.jsonObject(with: Data(contentsOf: root.appending(path: relativePath)))
    }

    /// Строки `design/copy.json`: id → `final`.
    static func copyFinals() throws -> [String: String] {
        let copy = try #require(try json("design/copy.json") as? [String: Any])
        let screens = try #require(copy["screens"] as? [[String: Any]])
        var finals: [String: String] = [:]
        for item in screens.flatMap({ ($0["items"] as? [[String: Any]]) ?? [] }) {
            if let id = item["id"] as? String, let final = item["final"] as? String {
                finals[id] = final
            }
        }
        return finals
    }
}
