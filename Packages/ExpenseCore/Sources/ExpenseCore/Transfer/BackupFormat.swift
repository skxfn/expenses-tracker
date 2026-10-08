import Foundation

/// Параметры JSON-формата резервной копии: версия, кодировщики, представление дат.
enum BackupFormat {
    /// Текущая версия формата. Повышать только при несовместимом изменении структуры файла.
    static let currentVersion = 1

    /// ISO 8601 в UTC с миллисекундами: `2026-10-08T09:15:42.120Z`.
    /// При чтении принимает и даты без долей секунды, и со смещением (`+03:00`).
    private static let dateStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(string(from: date))
        }
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let date = try? dateStyle.parse(string) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Некорректная дата: \(string)")
            }
            return normalized(date)
        }
        return decoder
    }

    /// Дата, округлённая до миллисекунд, — ровно то значение, что вернётся после записи и чтения файла.
    static func normalized(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 * 1000).rounded() / 1000)
    }

    /// `ISO8601FormatStyle` отбрасывает доли миллисекунды, а прочитанная дата бывает на ~1e-7 с
    /// меньше записанной — без поправки каждый цикл «экспорт → импорт» мог бы терять 1 мс.
    /// Поэтому округляем сами и форматируем середину нужной миллисекунды.
    static func string(from date: Date) -> String {
        let milliseconds = (date.timeIntervalSince1970 * 1000).rounded()
        return Date(timeIntervalSince1970: (milliseconds + 0.5) / 1000).formatted(dateStyle)
    }
}
