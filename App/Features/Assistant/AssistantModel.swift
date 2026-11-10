import Foundation
import ImageIO
import Observation
import SwiftData
import UIKit
import ExpenseCore

/// Фото, приложенное к запросу: данные как пришли (JPEG/HEIC) и миниатюра для ряда над полем.
struct AttachedPhoto: Identifiable {
    let id = UUID()
    let data: Data
    let thumbnail: UIImage?
}

/// Состояние шита ИИ-записи: ввод → запрос → черновики. Ничего не сохраняет — это делает `DraftReviewModel`
/// по нажатию «Записать».
@Observable
final class AssistantModel {
    /// Не больше фото за раз (ограничение выбора в фотоплёнке и камере).
    static let maxPhotos = 5

    var text = ""
    private(set) var photos: [AttachedPhoto] = []
    private(set) var isSending = false
    var error: AssistantError?
    private(set) var review: DraftReviewModel?

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let keyStore: AssistantKeyStore
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let transport: HTTPTransport
    /// Дата трат, для которых модель даты не назвала (день из шита записи).
    @ObservationIgnored private let defaultDate: EntryDate

    init(
        keyStore: AssistantKeyStore = KeychainAssistantKeyStore(), defaults: UserDefaults = .standard,
        transport: HTTPTransport = URLSessionTransport(), defaultDate: EntryDate = .today
    ) {
        self.keyStore = keyStore
        self.defaults = defaults
        self.transport = transport
        self.defaultDate = defaultDate
    }

    /// Есть текст или фото — закрытие шита спросит.
    var hasInput: Bool {
        !AssistantInput(text: text, images: photos.map(\.data)).isEmpty
    }

    var canSend: Bool {
        !isSending && hasInput
    }

    var canAddPhotos: Bool { photos.count < Self.maxPhotos }

    /// Ключ и сервер заданы — иначе над полем подсказка про настройки.
    var isConfigured: Bool {
        AssistantConfiguration.load(from: defaults).isComplete && ((try? keyStore.readKey())?.isEmpty == false)
    }

    func addPhoto(_ data: Data) {
        guard canAddPhotos else { return }
        photos.append(AttachedPhoto(data: data, thumbnail: Self.thumbnail(of: data)))
    }

    func removePhoto(_ id: UUID) {
        photos.removeAll { $0.id == id }
    }

    /// Отправить ввод. Ошибка остаётся над полем, ввод не теряется.
    func send(context: ModelContext, formatter: MoneyFormatter, calendar: Calendar = .current) {
        guard canSend else { return }
        error = nil
        let input = AssistantInput(text: text, images: photos.map(\.data))
        let service: AssistantService
        let assistantContext: AssistantContext
        do {
            service = try AssistantService(
                configuration: .load(from: defaults),
                apiKey: (try? keyStore.readKey()) ?? "",
                transport: transport
            )
            let catalog = AssistantCatalog(offering: try ExpenseStore(context: context).allCategories())
            assistantContext = AssistantContext(
                catalog: catalog,
                now: .now,
                calendar: calendar,
                currencyCode: formatter.currencyCode,
                noteLanguage: AppLanguage.current.code,
                formatter: formatter,
                defaultDate: defaultDate
            )
        } catch {
            self.error = error as? AssistantError ?? .notConfigured
            return
        }
        task?.cancel()
        isSending = true
        task = Task { [weak self] in
            let outcome: Result<AssistantResult, Error>
            do {
                outcome = .success(try await service.parse(input, context: assistantContext))
            } catch {
                outcome = .failure(error)
            }
            // Отменённый запрос ничего не трогает: «Отменить» уже вернуло ввод, а новый запрос мог начаться
            // (нарезку фото не прервать — старая задача доходит сюда позже).
            guard let self, !Task.isCancelled else { return }
            isSending = false
            switch outcome {
            case .success(let result):
                review = DraftReviewModel(result: result, formatter: formatter, defaults: defaults)
            case .failure(is CancellationError):
                break
            case .failure(let error):
                self.error = error as? AssistantError ?? .unreadableResponse
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        isSending = false
    }

    /// Назад к вводу из черновиков (кнопка «Изменить запрос»).
    func backToInput() {
        review = nil
    }

    /// Миниатюра через ImageIO: без декодирования всего снимка (12 Мп) на главном потоке, с учётом EXIF-поворота.
    private static func thumbnail(of data: Data) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 320,
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}
