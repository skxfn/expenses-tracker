import Foundation
import SwiftData
import Testing
import UniformTypeIdentifiers
@testable import ExpenseCore

@Suite struct BackupDocumentTests {
    @Test func documentIsJSON() {
        #expect(BackupDocument.readableContentTypes == [.json])
        #expect(BackupDocument.writableContentTypes == [.json])
    }

    @Test func readsExportedFileFromURL() throws {
        let context = ModelContext(try BackupFixture.makeContainer())
        try BackupFixture.seed(context)
        let data = try BackupExporter.exportData(from: context, currencyCode: "BYN")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let document = try BackupDocument(contentsOf: url)

        #expect(document.data == data)
        #expect(try BackupImporter.decode(document.data).expenses.count == 3)
    }
}
