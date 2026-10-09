import Foundation

/// Ступени оттенков подкатегорий. Цвет подкатегории не хранится: он выводится из тона
/// родителя и ступени. Порядок — по созданию (INTEGRATION §8 п. 3): цвета не перекрашиваются
/// при смене периода. Таблицы цветов ступеней — в App.
public enum SubcategoryShades {
    /// Ступеней в лесенке; шестая подкатегория повторяет первую (`cat.shades.overflow`).
    public static let stepCount = 5

    /// Ступень (0…4) по номеру подкатегории среди сестёр в порядке создания.
    public static func step(forPosition position: Int) -> Int {
        position % stepCount
    }

    /// Сёстры в порядке ступеней — по появлению в категории: `ExpenseStore` даёт подкатегории
    /// следующий `sortOrder` при создании и переносе, так что перенесённая встаёт в конец и не сдвигает
    /// остальных. При равенстве — по дате создания и id. Архивные тоже держат место.
    public static func ordered(_ siblings: [ExpenseCategory]) -> [ExpenseCategory] {
        siblings.sorted {
            ($0.sortOrder, $0.createdAt, $0.id.uuidString) < ($1.sortOrder, $1.createdAt, $1.id.uuidString)
        }
    }

    /// Ступень подкатегории; `nil` — категория верхнего уровня.
    public static func step(of subcategory: ExpenseCategory) -> Int? {
        guard let parent = subcategory.parent else { return nil }
        let position = ordered(parent.children).firstIndex { $0.id == subcategory.id }
        return position.map(step(forPosition:))
    }
}
