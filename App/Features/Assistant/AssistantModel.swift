import Foundation
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

    init(keyStore: AssistantKeyStore = KeychainAssistantKeyStore(), defaults: UserDefaults = .standard, transport: HTTPTransport = URLSessionTransport()) {
        self.keyStore = keyStore
        self.defaults = defaults
        self.transport = transport
    }

    var canSend: Bool {
        !isSending && !AssistantInput(text: text, images: photos.map(\.data)).isEmpty
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
                formatter: formatter
            )
        } catch {
            self.error = error as? AssistantError ?? .notConfigured
            return
        }
        isSending = true
        task = Task { [weak self] in
            do {
                let result = try await service.parse(input, context: assistantContext)
                guard let self, !Task.isCancelled else { return }
                review = DraftReviewModel(result: result, formatter: formatter, defaults: defaults)
            } catch is CancellationError {
                // Отмена пользователем — ввод остаётся как был.
            } catch {
                self?.error = error as? AssistantError ?? .unreadableResponse
            }
            self?.isSending = false
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

    private static func thumbnail(of data: Data) -> UIImage? {
        UIImage(data: data)?.preparingThumbnail(of: CGSize(width: 160, height: 160))
    }
}
