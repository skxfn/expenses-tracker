# Референсы дизайна — «Траты»

> Ничего не утверждено: это варианты, из которых пользователь выбирает сам.

**Источник.** Mobbin MCP отказал («Mobbin MCP requires a paid plan»), поэтому ссылок Mobbin нет. Все картинки — маркетинговые скриншоты App Store (с подписями и рамками, а не «сырые» экраны) и иллюстрации Apple Support. Каждый скриншот просмотрен. Машиночитаемая версия: `references.json`.

**Картинки.** Все 56 уникальных URL открываются без авторизации (`curl -sI` → 200, `image/jpeg|png`, CORS `*`, чужой Referer → 200), подписи/токенов в URL нет. mzstatic кэшируется ~160–195 дней, но URL меняется, если разработчик обновит скриншоты. Картинки Apple Support — с версией iOS в имени, их, вероятно, заменят.


## Добавление расхода


### A · Калькулятор на весь экран: сначала сумма

Экран (или шит на всю высоту) открывается сразу с крупной суммой и своей цифровой клавиатурой. Категория — чип под суммой или отдельный шаг после ввода. Дата/повтор — мелкие чипы.

- **Плюсы:** Самый быстрый ввод суммы: клавиатура всегда под пальцем, системная не нужна. Своя клавиатура естественно пишет сразу в копейки (amountMinor Int64). Минимум элементов — одинаково чисто в светлой и тёмной теме.
- **Минусы:** Категория — второй шаг или мелкий чип: больше тапов, если категория не по умолчанию. Своя клавиатура = своя доступность (VoiceOver, Dynamic Type) и свой десятичный разделитель.
- **Сложность в SwiftUI:** Средняя: Grid из кнопок + форматирование суммы, .sensoryFeedback (iOS 17) на нажатия. Swift Charts не нужен.

Референсы:

- **Dime: Budget & Expense Tracker** — Новая трата: сумма + клавиатура. Крупная сумма по центру, под ней чип категории; чипы даты и подписки; клавиатура с ✓ вместо «=». Приложение open-source на SwiftUI (github.com/rafsoh/dimeApp, GPL-3.0) — можно подсмотреть устройство NumberPad, но код под GPL. ([App Store/источник](https://apps.apple.com/us/app/dime-budget-expense-tracker/id1635280255), [картинка](https://is1-ssl.mzstatic.com/image/thumb/Purple116/v4/3b/a7/cd/3ba7cd99-4342-5ffe-f9c6-ea472a79b255/dc626b4d-d1d2-4fbf-9eac-265da6937228_5.5_inch_3.png/460x1000bb.jpg))
- **Monefy** — New expense: калькулятор. Поле суммы + калькулятор с операциями + − × ÷ =, заметка, дата сверху; внизу кнопка «CHOOSE CATEGORY» — категория отдельным шагом после суммы. ([App Store/источник](https://apps.apple.com/us/app/monefy-bills-money-tracker/id1212024409), [картинка](https://is1-ssl.mzstatic.com/image/thumb/Purple123/v4/85/a7/4e/85a74ebe-c812-3ece-caa9-bf098a1b5709/pr_source.png/460x1000bb.jpg))

### B · Сетка категорий + компактная клавиатура на одном экране

Верх — сетка иконок категорий (4–5 в ряд, вкладки или страницы), низ — компактный numpad с заметкой, чипом даты и ✓. Порядок: категория → цифры → готово.

- **Плюсы:** Категория и сумма на одном экране, без второго шага: 2–3 тапа. Иконка + цвет категории сразу работают как подтверждение выбора. Хорошо масштабируется до ~15 категорий без прокрутки.
- **Минусы:** Тесно на маленьких экранах (iPhone SE): сетка и клавиатура занимают всё. При большом числе категорий нужны страницы или прокрутка, экран выглядит «шумно».
- **Сложность в SwiftUI:** Средняя: LazyVGrid + своя клавиатура в одном sheet; выбранная категория красит шапку/кнопку.

Референсы:

- **Money+ Cute Expense Tracker** — Добавление: сетка + клавиатура. Вкладка «Recommended» — частые категории по привычкам пользователя; под сеткой поле Note, чип «TODAY», ✓ и клавиатура. Иконки иллюстрированные, но схема та же. ([App Store/источник](https://apps.apple.com/us/app/money-cute-expense-tracker/id1510760825), [картинка](https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/52/9e/c8/529ec8cd-9907-3857-a51c-283ce57cf20d/Simulator_Screenshot_-_iPhone_17_Pro_Max_-_2026-05-23_at_13.19.26.png/460x1000bb.jpg))
- **EZ Money Tracker & Manager** — Quick entry: сетка + калькулятор. Шапка залита цветом выбранной категории и показывает сумму; 10 круглых категорий + «Manage»; чипы даты и заметки; клавиатура с «+ −», «Again» и «Done». ([App Store/источник](https://apps.apple.com/us/app/ez-money-tracker-manager/id6758570909), [картинка](https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/a0/2e/80/a02e801f-14b2-b127-e0a8-4d2f97eb1726/3.png/460x1000bb.jpg))
- **Money manager, expense tracker (Orange dog)** — Add transaction: сумма + сетка. Сумма вверху, сетка круглых иконок категорий с «More», дата, комментарий, кнопка Add. Без своей клавиатуры — системная. ([App Store/источник](https://apps.apple.com/us/app/money-manager-expense-tracker/id1510997753), [картинка](https://is1-ssl.mzstatic.com/image/thumb/PurpleSource124/v4/8f/e4/6c/8fe46c38-1291-8c91-6282-410926b9b1b3/f476b9d1-6ed1-4551-aaca-cb83de5105ae_Screen_1242x2208px_IPhone8_04_Eng.png/460x1000bb.jpg))
- **Expense Tracker – Money Note** — Ввод расхода: форма с сеткой. Дата со стрелками ‹ ›, заметка, поле суммы, сетка категорий с контурными иконками — вариант без своей клавиатуры. ([App Store/источник](https://apps.apple.com/us/app/expense-tracker-money-note/id1320730220), [картинка](https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/71/4b/38/714b38d8-5ee4-871a-3010-19c7e8f165fc/pr_source.jpg/460x1000bb.jpg))

### C · Сумма + лента чипов категорий

Крупная сумма, под ней один горизонтальный ряд (или облако) чипов категорий, ниже дата/комментарий и клавиатура. Частые категории — первыми.

- **Плюсы:** Компактнее сетки — остаётся место для крупной клавиатуры. Горизонтальная лента вмещает любое число категорий. 3 тапа: цифры → чип → готово.
- **Минусы:** Категории за краем ленты надо искать прокруткой. Текстовые чипы (как в Toshl) читаются хуже иконок; нужно решить, какая категория выбрана по умолчанию.
- **Сложность в SwiftUI:** Низкая–средняя: ScrollView(.horizontal) с чипами + та же клавиатура, что в варианте A.

Референсы:

- **Daily Cost: Expense Tracker** — Entry: сумма + ряд чипов. Сумма справа сверху, ряд круглых чипов (Unlabeled/Coffee/Fun/Groceries/Home/Transport), чип даты, комментарий, клавиатура. Подпись: «Amount, label, done» за 3 тапа. Тёмная тема с золотым акцентом. ([App Store/источник](https://apps.apple.com/us/app/daily-cost-expense-tracker/id6784723743), [картинка](https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/56/f6/24/56f62489-75e2-5894-237b-f0d031220f44/21.png/460x1000bb.jpg))
- **Toshl Finance** — Add expense: сумма + облако категорий. Крупная сумма, облако текстовых категорий постранично, ниже Tags/Account/Date. В описании App Store: ввод «in only 4 taps». ([App Store/источник](https://apps.apple.com/us/app/toshl-finance-best-budget/id921590251), [картинка](https://is1-ssl.mzstatic.com/image/thumb/PurpleSource126/v4/89/57/a1/8957a13d-d77d-fc29-0eca-3e23e930120f/3d959707-6f9e-4846-8ea7-798faffb092a_5_APP_IPHONE_55_5.png/460x1000bb.jpg))
- **Spendly: Visual Expense Log** — New Expense: быстрые суммы. Поле суммы + чипы быстрых сумм $5/$10/$20/$50/$100, затем строки Category/Date и «More options»; сверху скан чека. ([App Store/источник](https://apps.apple.com/us/app/spendly-visual-expense-log/id6787908462), [картинка](https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/2a/d3/f9/2ad3f975-e6a0-e5be-8d3e-707c8b2afdac/04_APP_IPHONE_67_04_add.png/460x1000bb.jpg))

### D · Сначала категория: главный экран = категории

На главном экране сразу все категории (плитки или иконки вокруг диаграммы). Тап (или перетаскивание) по категории открывает ввод суммы уже с выбранной категорией.

- **Плюсы:** 2 тапа до клавиатуры, категория выбрана «бесплатно». Главный экран одновременно — сводка по категориям (суммы на плитках).
- **Минусы:** Главный экран занят категориями — список трат и статистика уходят на другие вкладки. При >12 категориях плитки мельчают; drag-and-drop (CoinKeeper) неочевиден.
- **Сложность в SwiftUI:** Средняя: LazyVGrid плиток + sheet с клавиатурой. Drag-and-drop между счётом и категорией — высокая.

Референсы:

- **Monefy** — Главный: иконки вокруг donut. Иконки категорий по кругу вокруг диаграммы, кнопки − / + внизу. По описанию на https://screensdesign.com/showcase/monefy-money-tracker, расход добавляется тапом по иконке категории вокруг диаграммы. ([App Store/источник](https://apps.apple.com/us/app/monefy-bills-money-tracker/id1212024409), [картинка](https://is1-ssl.mzstatic.com/image/thumb/Purple113/v4/ba/b8/15/bab815e4-530e-626f-63a1-9691f5a8fbcf/pr_source.png/460x1000bb.jpg))
- **CoinKeeper 3** — Счета и категории на одном экране. Сетка кругов: счета сверху, категории ниже, под каждой сумма. По справке CoinKeeper: тянешь счёт на категорию, отпускаешь и вводишь сумму (https://enhelp.coinkeeper.me/How-to-create-an-expense-income-8681c0bd7d0c46df9ef13ffd2c96c19c). ([App Store/источник](https://apps.apple.com/us/app/coinkeeper-3-money-manager/id1335547405), [картинка](https://is1-ssl.mzstatic.com/image/thumb/PurpleSource116/v4/49/7e/7c/497e7ca1-1e86-34c0-1b22-576a6ad96cd4/cf880379-13b0-434b-afc5-aca1eabb10d4_04_iPhone_8_EN.jpg/460x1000bb.jpg))
- **Budget app – spending tracker (Inner Grow)** — Главный: плитки категорий. Плитки категорий с суммой и тонким прогрессом; сверху «Spending $234», переключатель Daily/Today. На соседнем скрине (index 1) ввод суммы с рядом подкатегорий Breakfast/Lunch/Dinner/Snack; переход «тап по плитке → ввод» по скринам не проверен. ([App Store/источник](https://apps.apple.com/us/app/budget-app-spending-tracker/id1525179720), [картинка](https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/ea/61/b5/ea61b553-1fda-6f1b-6afb-382804052c5c/a91a6b07-8721-4cf1-97d1-3383d8c2565e_card2.png/460x1000bb.jpg))

**Ещё видели (вне направлений):**

- **Fleur – Budget Planner** — New transaction: нативная форма. Сумма крупно + строки Category/Date/Account/Repeating/Paid/Notes. Базовый вариант на SwiftUI Form — самый простой, но медленнее остальных. ([App Store/источник](https://apps.apple.com/us/app/fleur-budget-planner-app/id1621020173), [картинка](https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/99/3a/41/993a41fe-8b8d-3748-cc88-f7979a3e8c2c/6.png/460x1000bb.jpg))
- **Spending Tracker (MH Riley)** — Transaction: grouped-таблица. Классическая таблица: Date/Amount/Category + блок повтора + заметка. Пример «как не надо» для быстрого ввода. ([App Store/источник](https://apps.apple.com/us/app/spending-tracker/id548615579), [картинка](https://is1-ssl.mzstatic.com/image/thumb/PurpleSource124/v4/72/c7/08/72c70887-6f65-ef79-2412-4eacc36b96e7/9f607dba-e1df-4e07-89b0-7770736e9073_3.png/460x1000bb.jpg))
- **Budget app – spending tracker (Inner Grow)** — Виджет + ввод с подкатегориями. Интерактивный виджет и панель ввода: сумма, чипы подкатегорий, клавиатура с ✓. В описании App Store: запись трат прямо из виджета. ([App Store/источник](https://apps.apple.com/us/app/budget-app-spending-tracker/id1525179720), [картинка](https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/bd/b8/69/bdb8693b-6f87-9b90-5ef0-fb4fc1f8a6da/8cd32c2d-1ef0-4616-bb50-5cd172dada21_en2_2.png/460x1000bb.jpg))

## Статистика


### S1 · Donut + список категорий

Переключатель периода (день/неделя/месяц/год), donut с итогом в центре, ниже список категорий: иконка, %, сумма, иногда прогресс-бар.

- **Плюсы:** Сразу отвечает «куда ушли деньги»; список дублирует donut и читается даже при 10+ категориях. Всё есть в Swift Charts: SectorMark (iOS 17) + chartAngleSelection (iOS 17) для тапа по сегменту.
- **Минусы:** Не показывает динамику во времени; близкие доли сравниваются плохо. Мелкие категории приходится сворачивать в «Прочее».
- **Сложность в SwiftUI:** Низкая: SectorMark(innerRadius:angularInset:) + List; выбор сегмента — .chartAngleSelection.

Референсы:

- **Money manager, expense tracker (Orange dog)** — Expenses: donut + список. Вкладки Day/Week/Month/Year/Period, итог в центре, список: иконка, %, сумма; FAB «+» поверх donut. Ближе всего к нашему ТЗ. ([App Store/источник](https://apps.apple.com/us/app/money-manager-expense-tracker/id1510997753), [картинка](https://is1-ssl.mzstatic.com/image/thumb/PurpleSource124/v4/b9/05/70/b90570e5-b4b4-c6f6-1aa9-9fd929aa9831/d71fa477-0510-493f-a8b1-9ed848ab985a_Screen_1242x2208px_IPhone8_01_Eng.png/460x1000bb.jpg))
- **Buddy: Budget Planner** — Spending: кольцо с зазорами. Сегменты с промежутками; в центре иконка и сумма выбранной категории (паттерн «тап по сегменту → центр показывает категорию»). Делается через angularInset + chartAngleSelection. ([App Store/источник](https://apps.apple.com/us/app/buddy-budget-planner-app/id936422955), [картинка](https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/6d/be/0c/6dbe0cad-9b74-6e1d-e539-b5c12bd64585/buddy_appstore_02.jpg/460x1000bb.jpg))
- **Weple Money** — Статистика: donut с выносками. Иконки категорий на выносках вокруг donut; список: % + цветной прогресс + сумма, мелким — сумма-ориентир. ([App Store/источник](https://apps.apple.com/us/app/weple-money-expense-tracker/id467936485), [картинка](https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/d5/26/8d/d5268d48-6f8a-0a77-d995-dc0885040ab9/1e78a101-f985-4ccf-9ee5-747de143ea63_Simulator_Screenshot_-_iPhone_8_Plus_-_2024-06-03_at_15.21.34.png/460x1000bb.jpg))
- **EZ Money Tracker & Manager** — Month/Year/Custom + donut. Сегмент Month/Year/Custom, Total Spent + число транзакций + сумма в день ($201.76/day), donut с подписями-выносками, ниже Category Breakdown. ([App Store/источник](https://apps.apple.com/us/app/ez-money-tracker-manager/id6758570909), [картинка](https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/3e/97/4d/3e974d9a-21c4-4ac0-a4ef-b990066f3e2a/2.png/460x1000bb.jpg))

### S2 · Бары по времени + период + фраза-сравнение

Сегмент Week/Month/Year, крупный итог, одна фраза сравнения с прошлым периодом, столбики по дням/неделям (иногда раскрашены по категориям), пунктир средней.

- **Плюсы:** Итог, динамика и сравнение в одном блоке; нативный вид как в Apple Wallet. Всё есть в Swift Charts: BarMark, RuleMark для средней, .chartXSelection (iOS 17) для тапа по дню.
- **Минусы:** Категории внутри столбика читаются хуже donut. Для года нужно агрегировать по месяцам, для дня — по часам или показывать список.
- **Сложность в SwiftUI:** Низкая–средняя: BarMark + RuleMark(среднее) + .chartXSelection; листание периодов — кнопки ‹ › или свайп.

Референсы:

- **Dime: Budget & Expense Tracker** — Insights: бары + среднее. Week-dropdown, «spent/day», карточки income/expense, бары по дням с пунктиром средней, полоса долей категорий с %, ниже транзакции. Open-source SwiftUI (InsightsView.swift). ([App Store/источник](https://apps.apple.com/us/app/dime-budget-expense-tracker/id1635280255), [картинка](https://is1-ssl.mzstatic.com/image/thumb/Purple116/v4/83/bb/27/83bb27b4-c6b9-4ac7-67be-e60b879dcbdd/373fb933-c3e8-4a1e-8b66-6741188a1193_5.5_inch_4.png/460x1000bb.jpg))
- **Apple Wallet (Apple Card)** — Monthly spending: Week/Month/Year. Total Spending + фраза «spent $998.13 more than the previous month», столбики по неделям, раскрашены по категориям. Иллюстрация с Apple Support (iOS 27). ([App Store/источник](https://support.apple.com/en-us/102329), [картинка](https://cdsassets.apple.com/live/7WUAS350/images/apple-pay/ios-27-iphone-17-pro-wallet-apple-card-balance-monthly-spending.png))
- **Apple Wallet (Insights, connected card)** — Insights: сравнение на ту же дату. «So far, you've spent £412 less than last month at this time» — сравнение с прошлым месяцем на ту же дату; блок Highlights «6-Month Average». ([App Store/источник](https://support.apple.com/en-us/123096), [картинка](https://cdsassets.apple.com/live/7WUAS350/images/apple-pay/ios-27-iphone-17-pro-wallet-connected-card-activity-month.png))
- **Daily Budget Original** — Analysis: три графика. Surplus по дням (бары вверх/вниз), расходы по категориям (бары с иконками под осью), расходы во времени; у каждого подпись «Daily average». ([App Store/источник](https://apps.apple.com/us/app/daily-budget-original/id651896614), [картинка](https://is1-ssl.mzstatic.com/image/thumb/PurpleSource126/v4/26/bc/d0/26bcd04e-0c8f-0a8b-4feb-8b36c6715e20/1953260d-fa04-4cc4-9e69-5665e03f65a6_5.5EN3.png/460x1000bb.jpg))

### S3 · Накопительная линия и темп трат

Кривая накопленных трат текущего периода поверх кривой прошлого/среднего периода; маркер «сегодня»; подпись «можно тратить X в день» или «на Y меньше, чем в это же время».

- **Плюсы:** Лучше всего отвечает «трачу быстрее обычного?» уже в середине месяца. Одна картинка вместо двух чисел; в AGENTS.md уже есть расчёт «кривой текущего периода».
- **Минусы:** Без легенды непонятна; для «дня» и «недели» мало точек — режим в основном для месяца/года. Spendee и Cashew строят темп от бюджета, а у нас бюджетов нет — фразу придётся адаптировать.
- **Сложность в SwiftUI:** Средняя: два LineMark с series (текущий/прошлый) + RuleMark «сегодня»; данные считаются в ExpenseCore.

Референсы:

- **Money Lover** — Trending report: месяц vs среднее. Expenses/Income, кривая «This month» против пунктира «3 month average», тултип с суммой на дату. ([App Store/источник](https://apps.apple.com/us/app/money-lover-money-manager/id486312413), [картинка](https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/fe/49/8c/fe498c9d-34c7-8be7-a74e-e862197a653b/6be2838a-bec5-4d8b-acb6-bdcf92be66bc_5.5_-_ENG_-_01.png/460x1000bb.jpg))
- **Spendee** — Budget: линия + темп. Линия трат против пунктира лимита, «You can spend 25.20 € each day for the rest of the period», прогресс периода с маркером Today, список прошлых периодов. ([App Store/источник](https://apps.apple.com/us/app/expense-budget-app-spendee/id635861140), [картинка](https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/46/4d/7e/464d7eb7-3c49-2fd8-f46f-a0b10a3f4a92/d1e631be-f53c-4428-87c8-1343e895d983_2208_iOS_App_Store_Screenshots_1_Copy_9.png/460x1000bb.jpg))
- **Cashew** — Monthly Spending: прогресс + линия. «$124.54 left of $500», прогресс с маркером Today, «You can keep spending $24.91 for 3 more days», ниже линия. ([App Store/источник](https://apps.apple.com/us/app/cashew-expense-budget-tracker/id6463662930), [картинка](https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/e5/cc/41/e5cc41f2-f4cd-129a-d1d4-df565601e743/58701135-6e5d-4f0d-853e-5a3ca1562779_Frame_1.png/460x1000bb.jpg))

### S4 · Тепловая карта + карточки-инсайты

Календарь месяца или годовая сетка дней, цвет ячейки = сумма трат; рядом короткие карточки: среднее в день, самый дорогой месяц, топ-категория, «обычно vs сейчас».

- **Плюсы:** Сразу видны «тихие» и «дорогие» дни и привычки по дням недели. Карточки дают вывод словами, а не графиком; хорошо для режима «год».
- **Минусы:** Нужна легенда цвета и аккуратная шкала в тёмной теме; при малом числе трат карта пустая. Готового календаря в Swift Charts нет — сетку проще собрать руками.
- **Сложность в SwiftUI:** Средняя: LazyVGrid 7×N с opacity по квантилям (или RectangleMark); карточки — простые View.

Референсы:

- **Spendly: Visual Expense Log** — Insights: годовая тепловая карта. Сетка недели×дни недели в красной шкале, Year Total / Avg/Day / Transactions, «Busiest month: July», лента месяцев-чипов, Top category. ([App Store/источник](https://apps.apple.com/us/app/spendly-visual-expense-log/id6787908462), [картинка](https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/43/8a/b9/438ab98a-ff7b-860f-5d25-5e7b8031fef2/03_APP_IPHONE_67_03_insights.png/460x1000bb.jpg))
- **EZ Money Tracker & Manager** — Календарь месяца с заливкой. Дни залиты оранжевым по сумме, сумма внутри ячейки; ниже траты выбранного дня. ([App Store/источник](https://apps.apple.com/us/app/ez-money-tracker-manager/id6758570909), [картинка](https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/fc/9c/01/fc9c01f3-e802-1c2f-5c38-df539ef5675f/1.png/460x1000bb.jpg))
- **Daily Cost: Expense Tracker** — Calendar: тёмная тепловая карта. Тёмный календарь, золотые ячейки по интенсивности, Month total сверху. Хороший пример тепловой карты в тёмной теме. ([App Store/источник](https://apps.apple.com/us/app/daily-cost-expense-tracker/id6784723743), [картинка](https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/f3/c6/2b/f3c62bbc-6d2a-646a-2bc8-88868dbdf9c1/19.png/460x1000bb.jpg))
- **Opal: Screen Time Control** — Не финансы: «обычно vs эта неделя». Screen Time: кольцо «1h 23m less than usual» + строки «Usually 4h04m a day / This week 2h41m a day». Взят ради формата карточки-сравнения. ([App Store/источник](https://apps.apple.com/us/app/opal-screen-time-control/id1497465230), [картинка](https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/4a/09/57/4a0957f1-c3d9-1b39-c1ac-8699c13c0780/AppstoreArtboard_1.jpg/460x1000bb.jpg))

**Ещё видели (вне направлений):**

- **Apple Fitness** — Не финансы: Summary плитками. Плитки метрик с мини-барами — каркас для дашборда карточек. ([App Store/источник](https://apps.apple.com/us/app/apple-fitness/id1208224953), [картинка](https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/a0/e0/ad/a0e0ad1b-f65e-9134-9b7d-dca428d14346/Fitness-iPhone6p9-LuckC-USEN-Wrapper1.png/460x1000bb.jpg))
- **Gentler Streak** — Не финансы: «Above Typical Saturday». Крупное число + сравнение с тем же днём недели. ([App Store/источник](https://apps.apple.com/us/app/gentler-streak-workout-tracker/id1576857102), [картинка](https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/5c/db/eb/5cdbeb12-8cb6-1819-a85e-d5319dbc78c4/Valera_English_iPhone4.png/460x1000bb.jpg))
- **Gentler Streak** — Не финансы: вердикт словами + плитки. «Sleep Quality: Excellent», короткий текст, плитки с бейджами «Normal / As Usual». ([App Store/источник](https://apps.apple.com/us/app/gentler-streak-workout-tracker/id1576857102), [картинка](https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/c8/03/00/c80300ac-bd26-aba8-2d35-0e2d56bb8972/Valera_English_iPhone3.png/460x1000bb.jpg))
- **Athlytic** — Не финансы: метрики «vs avg». Плитки «↑ 69% vs avg» относительно 60-дневной базы. ([App Store/источник](https://apps.apple.com/us/app/athlytic-fitness-recovery/id1543571755), [картинка](https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/c2/8c/d6/c28cd6b9-58df-2b4d-1203-e2c11b7bafe9/Athlytic_app_store_assets_iPhone_1320x2868_260714_Artboard-3.png/460x1000bb.jpg))
- **Wallet by BudgetBakers** — Обзор статистики карточками. Строки-карточки с мини-графиком справа: баланс, расходы (donut), поток. Скриншот на польском. ([App Store/источник](https://apps.apple.com/us/app/wallet-daily-budget-profit/id1032467659), [картинка](https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/5d/b0/a5/5db0a5a2-3ab8-bb25-808d-0b302c1a81f8/5.5_Iphone6_plus_Img_3.jpg/460x1000bb.jpg))
- **Spendee** — Карточки-инсайты. «This year, you've already spent $1 284 on Food & Drinks», «Monthly Cash Flow» — инсайты фразами. ([App Store/источник](https://apps.apple.com/us/app/expense-budget-app-spendee/id635861140), [картинка](https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/77/b0/8c/77b08c10-a9b9-41d7-74da-ed2b11394139/7b699b2c-c00e-4b4f-ae14-2cf4469d95cd_2208_iOS_App_Store_Screenshots_1_Copy_10.png/460x1000bb.jpg))
- **Zenmoney** — Donut + мини-бары месяцев. Donut с % и под ним мини-бары по месяцам, которые работают как выбор периода. ([App Store/источник](https://apps.apple.com/us/app/zenmoney-expense-tracker/id905934786), [картинка](https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/a6/e7/b0/a6e7b08c-4bb1-6dd2-311a-b1d3daed4351/iOS_1.jpg/460x1000bb.jpg))
- **Zenmoney** — Bubble chart категорий. Круги, размер = сумма. Альтернатива donut, в Swift Charts готовой нет. ([App Store/источник](https://apps.apple.com/us/app/zenmoney-expense-tracker/id905934786), [картинка](https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/5e/36/81/5e368155-bdbd-4853-4683-49a0a57c9232/iOS_4.jpg/460x1000bb.jpg))
- **Zenmoney** — Spending trends по категориям. Линии по категориям за полгода, чипы 3m/6m/1y/All, блок «Steadily growing». ([App Store/источник](https://apps.apple.com/us/app/zenmoney-expense-tracker/id905934786), [картинка](https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/95/00/c3/9500c369-b2e3-0a20-c084-6423da134a55/5.jpg/460x1000bb.jpg))
- **Expenses: Spending Tracker (Blue Comet Labs)** — Trends: Daily/Weekly/Monthly. Три area-графика стопкой, у каждого свой масштаб времени. ([App Store/источник](https://apps.apple.com/us/app/expenses-spending-tracker/id1492055171), [картинка](https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/b3/05/12/b3051252-85a1-76b2-6484-c2b2130f8798/English__U0028United_States_U0029__U005ben-US_U005d_-_iPhone_-_6.9_U0022_Display_-_4.jpeg/460x1000bb.jpg))
- **Cashew** — Donut с иконками на сегментах. Иконки категорий-бейджи на сегментах, ниже список с прогресс-барами. ([App Store/источник](https://apps.apple.com/us/app/cashew-expense-budget-tracker/id6463662930), [картинка](https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/0d/7a/4b/0d7a4b12-6c02-5085-ada5-e04f8e91af56/25e1fb28-0574-4305-b3e6-df3930f6b9f3_Frame_2.png/460x1000bb.jpg))
- **Daily Cost: Expense Tracker** — Stats: Week/Month/Year + By day. Крупное «Spent $257.00» и бары по дням; тёмная тема. ([App Store/источник](https://apps.apple.com/us/app/daily-cost-expense-tracker/id6784723743), [картинка](https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/3e/22/09/3e220909-ea4c-ecfa-8064-fddb7f9c3d95/20.png/460x1000bb.jpg))

## Главный экран / список расходов (меньше внимания)


### H1 · Итог периода сверху + лента по дням

Крупный итог периода, под ним траты, сгруппированные по дням с суммой дня; центральная «+» или кнопка внизу.

- **Плюсы:** Привычно, быстро сканируется; итог дня в заголовке группы. Нативно: List + Section.
- **Минусы:** Без графика: статистика только на отдельной вкладке.
- **Сложность в SwiftUI:** Низкая: List с Section по дням, sectioned @Query или группировка в ExpenseCore.

Референсы:

- **Dime: Budget & Expense Tracker** — Home: итог + лента. Net total this month, income/expense, группы по дням с суммой дня, таб-бар с центральной «+». ([App Store/источник](https://apps.apple.com/us/app/dime-budget-expense-tracker/id1635280255), [картинка](https://is1-ssl.mzstatic.com/image/thumb/Purple116/v4/01/33/e5/0133e53f-db30-e2dc-a405-99b86e78ebfd/ef70779b-ba35-4c0c-8c88-17b71bb62eed_5.5_inch.png/460x1000bb.jpg))
- **Spendly: Visual Expense Log** — Activity: лента + фильтры. Группы по дням с Day total, поиск, чипы фильтров Today / месяц / Day / Category, кнопка Add Expense внизу. ([App Store/источник](https://apps.apple.com/us/app/spendly-visual-expense-log/id6787908462), [картинка](https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/ef/dc/5f/efdc5ff7-275e-0376-a975-0e7a861ee8d0/02_APP_IPHONE_67_02_activity.png/460x1000bb.jpg))
- **Cashew** — Transactions: вкладки месяцев. Вкладки месяцев, группы по датам с суммой дня, цветные круглые иконки, FAB «+». ([App Store/источник](https://apps.apple.com/us/app/cashew-expense-budget-tracker/id6463662930), [картинка](https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/7e/f2/08/7ef208ed-6181-3342-3929-bc62bf47c9b4/30e68680-32e1-455c-8a55-5cf7d7a4da10_Frame_4.png/460x1000bb.jpg))
- **Daily Cost: Expense Tracker** — Spent today: одно большое число. «Spent today $57.00» крупно, тонкий прогресс, ниже записи. Минимальный главный экран. ([App Store/источник](https://apps.apple.com/us/app/daily-cost-expense-tracker/id6784723743), [картинка](https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/de/47/55/de475517-edc3-a17c-5f08-619a08f8ab9f/18.png/460x1000bb.jpg))

### H2 · Календарь как главный экран

Месячная сетка с суммами по дням, под ней траты выбранного дня.

- **Плюсы:** Совмещает список и обзор месяца.
- **Минусы:** Мелкие цифры в ячейках, тесно на маленьких экранах.
- **Сложность в SwiftUI:** Средняя: своя сетка календаря (LazyVGrid).

Референсы:

- **Weple Money** — Календарь с суммами. Месяц с суммами по дням, выделенный день, ниже траты дня, FAB «+». ([App Store/источник](https://apps.apple.com/us/app/weple-money-expense-tracker/id467936485), [картинка](https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/c2/3c/eb/c23ceb92-e315-c003-e0c7-f666e2571462/86dc8ef2-3621-44c2-be6b-11bec8ab14b7_Simulator_Screenshot_-_iPhone_8_Plus_-_2024-06-03_at_15.20.37.png/460x1000bb.jpg))
- **Money+ Cute Expense Tracker** — Calendar: суммы в ячейках. Красные/зелёные суммы в ячейках, ниже лента по дням. ([App Store/источник](https://apps.apple.com/us/app/money-cute-expense-tracker/id1510760825), [картинка](https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/f6/02/43/f60243d7-00bf-509a-84eb-8f76cc0f2f34/Simulator_Screenshot_-_iPhone_17_Pro_Max_-_2026-05-23_at_13.19.39.png/460x1000bb.jpg))

**Ещё видели (вне направлений):**

- **Dime: Budget & Expense Tracker** — Home в тёмной теме. Чисто чёрный фон (подпись «Gorgeous In Black»), та же структура, что в светлой. ([App Store/источник](https://apps.apple.com/us/app/dime-budget-expense-tracker/id1635280255), [картинка](https://is1-ssl.mzstatic.com/image/thumb/Purple126/v4/24/c9/09/24c90982-e2d7-e445-141e-8073f35b3ecb/0c60cc67-58ef-4d61-af79-894928111da4_5.5_inch_7.png/460x1000bb.jpg))
- **Expenses: Spending Tracker (Blue Comet Labs)** — Sensitive Mode. Суммы скрыты серыми плашками — режим приватности для показа экрана. ([App Store/источник](https://apps.apple.com/us/app/expenses-spending-tracker/id1492055171), [картинка](https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/bd/e6/01/bde6014d-e5cc-7182-5788-fd7a2cb49c41/English__U0028United_States_U0029__U005ben-US_U005d_-_iPhone_-_6.9_U0022_Display_-_5.jpeg/460x1000bb.jpg))

## Выбор иконки и цвета категории (меньше внимания)


### C1 · Превью + цвета + сетка иконок на одном экране

Сверху крупное превью (иконка в цвете) и имя, ниже ряд/сетка цветов кружками, ниже сетка иконок по группам.

- **Плюсы:** Всё видно сразу, превью мгновенно реагирует. Ложится на SF Symbols + Color.
- **Минусы:** Длинный экран при большом наборе иконок; нужен поиск или группы.
- **Сложность в SwiftUI:** Низкая: Form/ScrollView + LazyVGrid; группы иконок — массивы имён SF Symbols (проверять доступность в iOS 17, см. AGENTS.md).

Референсы:

- **EZ Money Tracker & Manager** — New Category: превью + цвета + иконки. Крупное превью, поле имени, 14 цветов кружками с ✓, иконки по группам (Food & Dining, Shopping). Ближе всего к SF Symbols + цвет. ([App Store/источник](https://apps.apple.com/us/app/ez-money-tracker-manager/id6758570909), [картинка](https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/50/6a/c8/506ac88d-652e-f144-d516-8460c61c189f/4.png/460x1000bb.jpg))
- **Money manager, expense tracker (Orange dog)** — Create new category. Имя, Expense/Income, сетка круглых иконок постранично, ряд цветов, кнопка Add. ([App Store/источник](https://apps.apple.com/us/app/money-manager-expense-tracker/id1510997753), [картинка](https://is1-ssl.mzstatic.com/image/thumb/PurpleSource124/v4/da/3b/8c/da3b8c2c-3097-cbf0-1f07-cbd92feff8bb/8bd8ac88-7efa-480d-b98a-e56b8de57631_Screen_1242x2208px_IPhone8_02_Eng.png/460x1000bb.jpg))
- **Monefy** — Edit category: сетка иконок. Имя на цветной плашке, сетка контурных иконок, выбранная залита цветом. ([App Store/источник](https://apps.apple.com/us/app/monefy-bills-money-tracker/id1212024409), [картинка](https://is1-ssl.mzstatic.com/image/thumb/Purple123/v4/37/f5/c7/37f5c7eb-d729-2b51-b398-3fc3e3e826ef/pr_source.png/460x1000bb.jpg))

### C2 · Цвет и иконка отдельными шитами/списками

Категории списком или сеткой; цвет выбирается в маленьком шите поверх экрана.

- **Плюсы:** Основной экран чище; шит цвета переиспользуется.
- **Минусы:** Лишний тап на каждую настройку.
- **Сложность в SwiftUI:** Низкая: .sheet с presentationDetents([.height(...)]).

Референсы:

- **Cashew** — Select Color: шит. Шит «Select Color» с 10 кружками поверх экрана. ([App Store/источник](https://apps.apple.com/us/app/cashew-expense-budget-tracker/id6463662930), [картинка](https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/c1/b6/91/c1b69149-5942-e5dc-5e26-791d80bbd740/c458f839-4a4d-4c35-bc05-103abfb53b27_Frame_5.png/460x1000bb.jpg))
- **Fleur – Budget Planner** — Category: сетка контурных иконок. Сетка категорий с контурными иконками в цвет, поиск, «+ New». ([App Store/источник](https://apps.apple.com/us/app/fleur-budget-planner-app/id1621020173), [картинка](https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/bf/9f/e1/bf9fe1d9-09bc-b9ae-5a19-07da930cc24d/3.png/460x1000bb.jpg))
- **Money+ Cute Expense Tracker** — New Category: огромная сетка. Иллюстрированные иконки по группам. Пример «слишком много»: долго листать. ([App Store/источник](https://apps.apple.com/us/app/money-cute-expense-tracker/id1510760825), [картинка](https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/b0/3d/d8/b03dd87b-7129-f634-b855-4d21b2e161a5/Simulator_Screenshot_-_iPhone_17_Pro_Max_-_2026-05-23_at_13.19.52.png/460x1000bb.jpg))

## Мелкие находки

- **Два режима ввода суммы.** В Dime есть настройка Number Entry: «Pre-dotted» (копейки ставятся сами: 599 → 5.99) и «Cent-less» (целые суммы). Pre-dotted напрямую ложится на amountMinor Int64. ([источник](https://github.com/rafsoh/dimeApp/blob/main/app/dime/Views/Settings/Settings%20Subviews/SettingsNumberEntryView.swift))
- **Уровни haptics.** Dime: настройка Haptic Feedback None / Subtle / Excessive; «The 'Excessive' mode makes the entire numpad haptic». В SwiftUI — .sensoryFeedback(_:trigger:) и SensoryFeedback (iOS 17). ([источник](https://github.com/rafsoh/dimeApp/blob/main/app/dime/Views/Settings/Settings%20Subviews/SettingsHapticsView.swift))
- **«Again» рядом с «Done».** EZ Money Tracker: клавиша «Again» сохраняет трату и сразу открывает ввод следующей — удобно разносить чек на несколько категорий. ([источник](https://apps.apple.com/us/app/ez-money-tracker-manager/id6758570909))
- **Частые категории первыми.** Money+: вкладка «Recommended» в сетке категорий («Based on your habits, frequent categories are recommended»). ([источник](https://apps.apple.com/us/app/money-cute-expense-tracker/id1510760825))
- **Чипы быстрых сумм.** Spendly: $5 / $10 / $20 / $50 / $100 под полем суммы. ([источник](https://apps.apple.com/us/app/spendly-visual-expense-log/id6787908462))
- **Калькулятор в клавиатуре.** Monefy: + − × ÷ = прямо в клавиатуре суммы (в описании App Store: «Built-in calculator»). EZ — «+ −». ([источник](https://apps.apple.com/us/app/monefy-bills-money-tracker/id1212024409))
- **Честное сравнение середины периода.** Apple Wallet: «So far, you've spent £412 less than last month at this time» — сравнение с тем же днём прошлого месяца, а не со всем прошлым месяцем. ([источник](https://support.apple.com/en-us/123096))
- **«Обычно vs сейчас» и «как в типичную субботу».** Opal: «Usually 4h04m a day / This week 2h41m a day». Gentler Streak: «Above Typical Saturday». Формулировки для карточек-инсайтов (средняя в день, тот же день недели). ([источник](https://apps.apple.com/us/app/opal-screen-time-control/id1497465230))
- **Форматирование суммы.** Daily Cost и Spendly: крупные целые, мелкие символ валюты и копейки ($57.00 с уменьшенными .00). Dime показывает «$5.99» с мелким $. В SwiftUI — конкатенация Text разных размеров; для анимации смены числа — .contentTransition(.numericText()) (iOS 16). ([источник](https://apps.apple.com/us/app/daily-cost-expense-tracker/id6784723743))
- **Пунктир средней на барах.** Dime Insights: горизонтальный пунктир средней поверх баров по дням (в Swift Charts — RuleMark). ([источник](https://apps.apple.com/us/app/dime-budget-expense-tracker/id1635280255))
- **Режим приватности.** Expenses (Blue Comet Labs): «Sensitive Mode» прячет суммы под серые плашки. ([источник](https://apps.apple.com/us/app/expenses-spending-tracker/id1492055171))
- **Тёмная тема как полноценная.** Dime («Gorgeous In Black»), Copilot («Light mode, when you need it»), Daily Cost (тёмная с золотым акцентом): одинаковая структура в обеих темах, акцентный цвет сохраняется. ([источник](https://apps.apple.com/us/app/dime-budget-expense-tracker/id1635280255))
- **Ввод вне приложения.** Dime: Home screen quick actions для новой траты (описание App Store). Budget app (Inner Grow): запись трат прямо из интерактивного виджета (описание App Store). ([источник](https://apps.apple.com/us/app/budget-app-spending-tracker/id1525179720))
- **Прогресс + ориентир в строке категории.** Weple и Cashew: в списке категорий под суммой цветной прогресс-бар и мелкая сумма-ориентир (бюджет или прошлый период). ([источник](https://apps.apple.com/us/app/weple-money-expense-tracker/id467936485))
- **Пустые состояния — не найдены.** В маркетинговых скриншотах App Store пустых состояний нет; без Mobbin этот пункт не закрыт.

## Что показать первым

- **Добавление:** «Сетка категорий + компактная клавиатура на одном экране» + «Сумма + лента чипов категорий». Оба дают 2–3 тапа без отдельного шага выбора категории и опираются на иконку+цвет категории. Внешне они заметно разные: вся сетка категорий сразу против компактной ленты и крупной клавиатуры. Вариант A (Dime) — минималистичная альтернатива, если почти всегда одна-две категории.
- **Статистика:** «Бары по времени + период + фраза-сравнение» + «Donut + список категорий». Вместе закрывают всё ТЗ: итог, переключение периода, график по времени, сравнение с прошлым периодом, средняя в день, разбивка и топ категорий. Оба собираются из стандартных марок Swift Charts (iOS 17). Как в Dime, их можно сложить в один прокручиваемый экран. S3 (накопительная линия) и S4 (тепловая карта) — вторым кругом, как дополнительные карточки.
