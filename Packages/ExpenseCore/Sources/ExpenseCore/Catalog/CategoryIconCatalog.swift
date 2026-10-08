/// Группа иконок для пикера.
public struct CategoryIconGroup: Identifiable, Hashable, Sendable {
    public let title: String
    /// Имена SF Symbols.
    public let symbols: [String]

    public var id: String { title }
}

/// Иконки для категорий. Только символы, доступные с iOS 17 (SF Symbols 5) и раньше.
public enum CategoryIconCatalog {
    public static let groups: [CategoryIconGroup] = [
        CategoryIconGroup(title: "Еда и покупки", symbols: [
            "cart.fill", "basket.fill", "bag.fill", "fork.knife", "cup.and.saucer.fill",
            "takeoutbag.and.cup.and.straw.fill", "wineglass.fill", "birthday.cake.fill"
        ]),
        CategoryIconGroup(title: "Транспорт и поездки", symbols: [
            "car.fill", "bus.fill", "tram.fill", "bicycle", "fuelpump.fill",
            "parkingsign.circle.fill", "airplane", "suitcase.rolling.fill"
        ]),
        CategoryIconGroup(title: "Дом и ЖКХ", symbols: [
            "house.fill", "sofa.fill", "lightbulb.fill", "bolt.fill", "drop.fill",
            "flame.fill", "washer.fill", "wrench.and.screwdriver.fill"
        ]),
        CategoryIconGroup(title: "Связь и техника", symbols: [
            "wifi", "iphone", "laptopcomputer", "tv.fill", "headphones",
            "antenna.radiowaves.left.and.right"
        ]),
        CategoryIconGroup(title: "Здоровье и спорт", symbols: [
            "cross.case.fill", "pills.fill", "heart.fill", "stethoscope", "dumbbell.fill",
            "figure.run", "leaf.fill"
        ]),
        CategoryIconGroup(title: "Досуг", symbols: [
            "theatermasks.fill", "film.fill", "music.note", "gamecontroller.fill", "ticket.fill",
            "book.fill", "paintpalette.fill", "beach.umbrella.fill"
        ]),
        CategoryIconGroup(title: "Одежда и уход", symbols: [
            "tshirt.fill", "eyeglasses", "scissors", "comb.fill", "sparkles"
        ]),
        CategoryIconGroup(title: "Семья и подарки", symbols: [
            "gift.fill", "person.2.fill", "figure.and.child.holdinghands", "teddybear.fill",
            "pawprint.fill", "graduationcap.fill"
        ]),
        CategoryIconGroup(title: "Финансы и прочее", symbols: [
            "creditcard.fill", "banknote.fill", "building.columns.fill", "briefcase.fill",
            "doc.text.fill", "repeat.circle.fill", "tag.fill", "ellipsis.circle.fill"
        ])
    ]

    /// Все иконки подряд, в порядке групп.
    public static var allSymbols: [String] {
        groups.flatMap(\.symbols)
    }
}
