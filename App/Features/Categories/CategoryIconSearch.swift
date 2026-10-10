import Foundation
import ExpenseCore

/// Поиск иконки категории (§8 п. 19): по имени для VoiceOver (`cat.icon.name.*`) и по синонимам —
/// чем оплачивают, а не что нарисовано («кофе» → чашка, «такси» → машина, «аптека» → лекарства).
/// В `copy.json` ключевых слов нет, список составлен при внедрении и живёт только здесь.
enum CategoryIconSearch {
    /// Синонимы по имени иконки MingCute (только иконки с именем в каталоге строк).
    static let synonyms: [String: [String]] = [
        // Еда и покупки
        "basket-fill": ["продукты", "супермаркет", "магазин", "еда", "покупки"],
        "shopping-cart-1-fill": ["супермаркет", "гипермаркет", "продукты", "покупки"],
        "shopping-bag-1-fill": ["покупки", "шопинг", "маркетплейс", "вещи"],
        "shop-fill": ["лавка", "рынок", "магазин у дома"],
        "bread-fill": ["выпечка", "пекарня", "булочная"],
        "apple-fruit-fill": ["фрукты", "овощи", "рынок", "еда"],
        "fork-knife-fill": ["кафе", "ресторан", "обед", "ужин", "столовая", "еда"],
        "teacup-fill": ["кофе", "чай", "кофейня"],
        "pizza-fill": ["доставка", "фастфуд"],
        "fries-fill": ["фастфуд", "бургер"],
        "ice-cream-fill": ["сладости", "десерт"],
        "wineglass-fill": ["вино", "бар", "алкоголь", "напитки"],
        // Транспорт и поездки
        "bus-fill": ["транспорт", "проезд", "троллейбус", "трамвай", "маршрутка"],
        "car-fill": ["такси", "авто", "автомобиль", "каршеринг"],
        "train-fill": ["метро", "электричка", "вокзал", "транспорт"],
        "gas-station-fill": ["бензин", "топливо", "азс"],
        "airplane-fill": ["авиабилеты", "перелёт", "путешествия", "отпуск"],
        "suitcase-fill": ["путешествия", "отпуск", "поездка", "отель"],
        // Дом и ЖКХ
        "home-4-fill": ["квартира", "аренда", "жильё", "ипотека"],
        "sofa-fill": ["диван", "интерьер"],
        "bulb-fill": ["свет", "коммуналка", "жкх"],
        "drop-fill": ["водоснабжение", "коммуналка", "жкх"],
        "flame-fill": ["отопление", "коммуналка", "жкх"],
        "tool-fill": ["инструменты", "мастер", "стройка"],
        // Связь и техника
        "wifi-fill": ["связь", "роутер"],
        "cellphone-fill": ["связь", "мобильный", "смартфон"],
        "laptop-fill": ["компьютер", "техника"],
        "headphone-fill": ["музыка", "аудио", "техника"],
        "tv-1-fill": ["тв", "кино", "подписки"],
        "camera-fill": ["фото", "камера"],
        // Здоровье и спорт
        "capsule-fill": ["аптека", "таблетки", "здоровье"],
        "first-aid-kit-fill": ["аптека", "врач", "медицина", "больница"],
        "dental-fill": ["зубы", "дантист"],
        "heartbeat-fill": ["здоровье", "врач", "анализы", "медицина"],
        "barbell-fill": ["фитнес", "спорт", "тренировки", "абонемент"],
        "run-fill": ["спорт", "тренировки", "фитнес"],
        // Досуг
        "celebrate-fill": ["праздник", "развлечения", "вечеринка"],
        "ticket-fill": ["концерт", "театр", "мероприятия"],
        "movie-fill": ["фильм", "кинотеатр"],
        "music-fill": ["концерт", "подписки"],
        "game-2-fill": ["видеоигры", "приставка"],
        "book-2-fill": ["чтение", "литература", "учёба"],
        // Одежда и уход
        "t-shirt-fill": ["одежда"],
        "dress-fill": ["одежда"],
        "shoe-fill": ["кроссовки", "туфли"],
        "lipstick-fill": ["красота", "макияж"],
        "scissors-fill": ["парикмахерская", "барбершоп", "салон", "красота"],
        "parfum-fill": ["духи", "красота"],
        // Семья и подарки
        "gift-fill": ["подарки", "день рождения", "праздник"],
        "cake-fill": ["день рождения", "праздник", "сладости"],
        "baby-carriage-fill": ["дети", "ребёнок", "малыш"],
        "paw-fill": ["питомцы", "животные", "кошка", "собака", "ветеринар", "корм"],
        "mortarboard-fill": ["образование", "учёба", "курсы", "школа", "университет"],
        "hand-heart-fill": ["благотворительность", "помощь", "донат"],
        // Финансы и прочее
        "repeat-fill": ["подписки", "регулярные платежи"],
        "bank-card-fill": ["карта", "оплата", "платежи"],
        "bank-fill": ["кредит", "комиссия", "налоги"],
        "pig-money-fill": ["накопления", "сбережения"],
        "bill-fill": ["счета", "квитанции", "платежи"],
        "more-3-fill": ["другое", "прочее", "разное"]
    ]

    /// Имя иконки для VoiceOver (`cat.icon.name.*`); `nil` — строки в каталоге нет.
    static func accessibilityName(of icon: CategoryIcon) -> String? {
        let missing = "\u{0}"
        let name = Bundle.main.localizedString(forKey: icon.accessibilityKey, value: missing, table: nil)
        return name == missing ? nil : name
    }

    /// Иконки группы, которые показывать: с именем в каталоге (группы по 6, как в макете `11-category`).
    /// Иконки прошлой версии без имени (`CategoryIconCatalog`) видны, только если уже выбраны.
    static func visibleIcons(in group: CategoryIconGroup, selection: String) -> [CategoryIcon] {
        group.icons.filter { accessibilityName(of: $0) != nil || $0.name == selection }
    }

    /// Совпадение по имени или синониму: без учёта регистра и «ё», по вхождению.
    static func matches(_ icon: CategoryIcon, query: String) -> Bool {
        let query = normalized(query)
        guard !query.isEmpty else { return true }
        let words = [accessibilityName(of: icon)].compactMap { $0 } + (synonyms[icon.name] ?? [])
        return words.contains { normalized($0).contains(query) }
    }

    private static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: L10n.locale)
    }
}
