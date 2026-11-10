import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Готовит фото чека для модели: поворот по EXIF, ширина не больше 1200 px, длинный чек — фрагменты
/// по 1600 px с перекрытием 120 px, JPEG 0,8.
///
/// Без нарезки сервер ужимает картинку по длинной стороне (Claude 4.7+: до 2576 px и 4784 визуальных
/// токенов), и строки чека длиной 50–60 см становятся нечитаемыми. Фрагмент 1200×1600 — 43×58 = 2494 токена.
public enum ReceiptImagePreparer {
    public static let maxWidth = 1200
    public static let fragmentHeight = 1600
    public static let overlap = 120
    /// Выше `aspectToSplit` × ширина — режем.
    public static let aspectToSplit = 1.5
    /// Не больше фрагментов на запрос (страницы × фрагменты).
    public static let maxFragments = 10
    public static let jpegQuality = 0.8

    /// Фрагменты одного фото (JPEG).
    public struct Photo: Equatable, Sendable {
        public let fragments: [Data]
    }

    /// Все фото запроса. Больше `maxFragments` фрагментов — `tooLarge`, не открылось — `imageUnreadable`.
    public static func prepare(_ images: [Data]) throws -> [Photo] {
        let photos = try images.map { Photo(fragments: try fragments(of: $0)) }
        guard photos.reduce(0, { $0 + $1.fragments.count }) <= maxFragments else { throw AssistantError.tooLarge }
        return photos
    }

    static func fragments(of data: Data) throws -> [Data] {
        let image = try orientedScaledImage(from: data)
        return try tileRects(width: image.width, height: image.height).map { rect in
            guard let tile = image.cropping(to: rect) else { throw AssistantError.imageUnreadable }
            return try jpeg(tile)
        }
    }

    /// Прямоугольники фрагментов сверху вниз; последний прижат к низу.
    static func tileRects(width: Int, height: Int) -> [CGRect] {
        guard Double(height) > Double(width) * aspectToSplit, height > fragmentHeight else {
            return [CGRect(x: 0, y: 0, width: width, height: height)]
        }
        let step = fragmentHeight - overlap
        var rects: [CGRect] = []
        var top = 0
        while true {
            let y = min(top, height - fragmentHeight)
            rects.append(CGRect(x: 0, y: y, width: width, height: fragmentHeight))
            if y + fragmentHeight >= height { break }
            top += step
        }
        return rects
    }

    /// Картинка в правильной ориентации, уменьшенная до `maxWidth` (не увеличивается).
    private static func orientedScaledImage(from data: Data) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let pixelWidth = properties[kCGImagePropertyPixelWidth] as? Int,
              let pixelHeight = properties[kCGImagePropertyPixelHeight] as? Int,
              pixelWidth > 0, pixelHeight > 0 else {
            throw AssistantError.imageUnreadable
        }
        // Ориентации 5–8 поворачивают картинку на 90°: ширина и высота меняются местами.
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        let (width, height) = orientation >= 5 ? (pixelHeight, pixelWidth) : (pixelWidth, pixelHeight)
        let scale = min(1, Double(maxWidth) / Double(width))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, Int((Double(max(width, height)) * scale).rounded())),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw AssistantError.imageUnreadable
        }
        return image
    }

    private static func jpeg(_ image: CGImage) throws -> Data {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw AssistantError.imageUnreadable
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: jpegQuality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw AssistantError.imageUnreadable }
        return output as Data
    }
}
