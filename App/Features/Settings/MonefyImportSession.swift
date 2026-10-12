import Foundation
import Observation
import SwiftData
import ExpenseCore

/// Один перенос трат из Monefy: файл уже прочитан — сопоставление категорий, импорт, отчёт.
/// Сопоставление запоминается по имени категории Monefy: повторный перенос того же файла — одно нажатие.
@Observable
final class MonefyImportSession: Identifiable {
    /// `[String: String]` — последнее сопоставление: имя категории Monefy → `MonefyCategoryTarget.storageValue`.
    static let mappingDefaultsKey = "monefyCategoryMapping"

    let id = UUID()
    let plan: MonefyImportPlan
    private(set) var mapping: [String: MonefyCategoryTarget]
    private(set) var report: MonefyImportReport?
    /// Идёт импорт: кнопка показывает индикатор, шит не закрывается свайпом.
    private(set) var isImporting = false
    var alert: FailureAlert?

    @ObservationIgnored private let defaults: UserDefaults

    /// - Parameter categoryIDs: категории приложения — запомненный выбор удалённой категории не восстанавливается.
    init(plan: MonefyImportPlan, categoryIDs: Set<UUID>, defaults: UserDefaults = .standard) {
        self.plan = plan
        self.defaults = defaults
        let stored = defaults.dictionary(forKey: Self.mappingDefaultsKey) as? [String: String] ?? [:]
        mapping = plan.restoredMapping(stored, categoryIDs: categoryIDs)
    }

    /// Сколько категорий Monefy ещё без выбора.
    var unmappedCount: Int { plan.unmappedCount(mapping) }

    /// Сколько трат пойдёт в импорт (без «Не переносить»).
    var importCount: Int { plan.importCount(mapping) }

    /// Выбрано для всех категорий и есть что переносить.
    var canImport: Bool { unmappedCount == 0 && importCount > 0 && !isImporting && report == nil }

    func select(_ target: MonefyCategoryTarget, for groupName: String) {
        mapping[groupName] = target
        var stored = defaults.dictionary(forKey: Self.mappingDefaultsKey) as? [String: String] ?? [:]
        stored[groupName] = target.storageValue
        defaults.set(stored, forKey: Self.mappingDefaultsKey)
    }

    func apply(context: ModelContext) async {
        guard canImport else { return }
        isImporting = true
        defer { isImporting = false }
        await BackupModel.letProgressAppear()
        do {
            report = try MonefyImporter.apply(plan, mapping: mapping, store: ExpenseStore(context: context))
        } catch {
            alert = .monefyApply
        }
    }
}
