import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Файл резервной копии для `.fileExporter`. `readableContentTypes` подходит
/// как `allowedContentTypes` для `.fileImporter`.
public struct BackupDocument: FileDocument {
    public static var readableContentTypes: [UTType] { [.json] }

    public let data: Data

    public init(data: Data) {
        self.data = data
    }

    public init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    /// Читает файл по URL из `.fileImporter`: такой URL доступен только в пределах security scope.
    public init(contentsOf url: URL) throws {
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessing { url.stopAccessingSecurityScopedResource() }
        }
        self.data = try Data(contentsOf: url)
    }

    public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
