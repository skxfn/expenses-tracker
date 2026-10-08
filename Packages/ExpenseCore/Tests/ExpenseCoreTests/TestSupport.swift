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
