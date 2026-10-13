import SwiftUI

/// Движение линзы выбранного дня — по замерам системной линзы iOS 26 (`Picker(.segmented)`, таб-бар `TabView`):
/// при выборе линза за ≈ 0,1 с поднимается (растёт, заливка уходит — остаётся прозрачное стекло), летит
/// пружиной без заметного перелёта (≈ 90 % пути за 0,2 с), вытягиваясь по ходу движения, и над новой клеткой
/// оседает к своему размеру с лёгким отскоком, заливка возвращается. Цифры линза в полёте не везёт: под ней видны
/// цифры клеток, увеличенные и без размытия (`LensWindow`), цифры выбранного дня проявляются после посадки.
/// Под пальцем линза чуть приподнимается.
nonisolated enum LensMotion {
    /// Перелёт к новой клетке: прерывание сохраняет скорость (пружины SwiftUI складываются).
    static let flight: Animation = .spring(duration: 0.32, bounce: 0.12)
    /// Подъём при выборе и посадка: отскок посадки — линза на миг чуть меньше своего размера.
    static let liftUp: Animation = .spring(duration: 0.16, bounce: 0)
    static let settle: Animation = .spring(duration: 0.34, bounce: 0.4)
    /// Когда подъём сменяется посадкой (её отскок), а цифры новой клетки под линзой гаснут (их копия — в окне).
    /// Сам размер оседает по мере подлёта — на последних `landingDistance` pt пути, а не по часам.
    static let cruise: Duration = .milliseconds(140)
    static let landingDistance: CGFloat = 20
    /// Когда проявляются цифры выбранного дня, а окно линзы гаснет.
    static let landing: Duration = .milliseconds(280)
    static let digitsIn: Animation = .easeOut(duration: 0.12)
    /// Окно гаснет за то же время, но с медленным началом: в наплыве цифры не тускнеют. Наплыв короткий —
    /// цифры клетки в окне и цифры линзы чуть расходятся по ширине (сумма в линзе может ужаться).
    static let windowOut: Animation = .easeIn(duration: 0.12)
    /// Касание выбранного дня: линза приподнимается, как интерактивное стекло.
    static let press: Animation = .spring(duration: 0.24, bounce: 0.25)

    /// Подъём в полёте и под пальцем (доля размера линзы).
    static let liftScale: CGFloat = 0.14
    static let pressScale: CGFloat = 0.07
    /// Насколько уходит заливка (тинт клетки): в полёте — до четверти, под пальцем — до половины.
    static let liftClearing: Double = 0.75
    static let pressClearing: Double = 0.5
    /// Остаток пути, ближе которого линза считается севшей: заливка возвращается по мере подлёта.
    static let transitDistance: CGFloat = 12
    /// Вытягивание по ходу движения: доля остатка пути, не больше 14 pt; поперёк линза сужается на треть этого.
    static let stretchPerPoint: CGFloat = 0.2
    static let maxStretch: CGFloat = 14
    static let crossSqueeze: CGFloat = 0.35
    /// Увеличение в окне линзы: цифры клетки (13) ×1,2 почти совпадают с цифрами линзы (16) — смена при посадке
    /// читается как наплыв, а не как двоение.
    static let magnification: CGFloat = 1.2
    /// Окно без размытия отступает от края линзы на 3 pt и растушёвано на 1,5: по краю остаётся системное стекло.
    static let windowInset: CGFloat = 3
    static let windowFeather: CGFloat = 1.5
}

/// Слой линзы над сеткой: одна линза перелетает от дня к дню. При Reduce Motion у каждого дня своя линза:
/// старая гаснет, новая проявляется, без подъёма и деформаций.
struct SelectionLens<Backdrop: View>: View {
    /// Рамка линзы в покое (клетка с выступом) в координатах сетки.
    let rect: CGRect
    /// Размер сетки и копия её клеток: в полёте линза показывает их увеличенными (`LensWindow`).
    let canvas: CGSize
    let backdrop: Backdrop
    /// Выбранный день: его смена запускает полёт.
    let date: Date
    /// Палец на выбранной клетке.
    let isPressed: Bool
    let lens: DayLens

    @State private var lift: Double = 0
    @State private var window: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            FlyingLens(
                center: CGPoint(x: rect.midX, y: rect.midY),
                lift: lift,
                pressLift: isPressed && !reduceMotion ? 1 : 0,
                window: window,
                target: CGPoint(x: rect.midX, y: rect.midY),
                restSize: rect.size,
                canvas: canvas,
                backdrop: backdrop,
                lens: lens
            )
            .id(reduceMotion ? date : nil)
            .transition(.opacity)
        }
        .animation(reduceMotion ? Motion.reduced : LensMotion.flight, value: date)
        .animation(LensMotion.press, value: isPressed)
        .onChange(of: date) {
            guard !reduceMotion else { return }
            withAnimation(LensMotion.liftUp) { lift = 1 }
        }
        .task(id: date) {
            try? await Task.sleep(for: LensMotion.cruise)
            guard !Task.isCancelled else { return }
            withAnimation(LensMotion.settle) { lift = 0 }
        }
        // Окно — пока линза без своих цифр: при взлёте сразу (цифры дня не едут на линзе), при посадке — наплыв
        // с цифрами дня.
        .onChange(of: lens.showsDigits, initial: true) { _, showsDigits in
            if showsDigits || reduceMotion {
                withAnimation(LensMotion.windowOut) { window = 0 }
            } else {
                // Без анимации, но не `disablesAnimations`: в iOS 27 он гасит и полёт с подъёмом того же кадра — линза прыгает.
                withAnimation(nil) { window = 1 }
            }
        }
    }
}

/// Линза на кадре анимации. Центр летит пружиной `LensMotion.flight`; цель не анимируется — остаток пути до неё
/// вытягивает линзу по ходу движения (у неподвижной линзы его нет). Подъём увеличивает линзу и делает стекло
/// прозрачнее; отрицательный подъём (отскок посадки) чуть уменьшает её. Поверх стекла — окно (`window` —
/// его непрозрачность): системное стекло размывает цифры под собой, от него остаются кромка с преломлением и блик.
private struct FlyingLens<Backdrop: View>: View, Animatable {
    var center: CGPoint
    var lift: Double
    var pressLift: Double
    var window: Double
    let target: CGPoint
    let restSize: CGSize
    let canvas: CGSize
    let backdrop: Backdrop
    let lens: DayLens

    var animatableData: AnimatablePair<CGPoint.AnimatableData, AnimatablePair<Double, AnimatablePair<Double, Double>>> {
        get { AnimatablePair(center.animatableData, AnimatablePair(lift, AnimatablePair(pressLift, window))) }
        set {
            center.animatableData = newValue.first
            lift = newValue.second.first
            pressLift = newValue.second.second.first
            window = newValue.second.second.second
        }
    }

    var body: some View {
        let dx = target.x - center.x
        let dy = target.y - center.y
        let distance = hypot(dx, dy)
        // Подлетая к клетке, линза оседает; отрицательный подъём (отскок посадки) — как есть.
        let approach = min(distance / LensMotion.landingDistance, 1)
        let lift = self.lift > 0 ? self.lift * approach * approach * (3 - 2 * approach) : self.lift
        let raised = min(max(lift, 0), 1)
        let stretch = min(distance * LensMotion.stretchPerPoint, LensMotion.maxStretch) * raised
        let along = distance > 0 ? CGSize(width: abs(dx) / distance, height: abs(dy) / distance) : .zero
        let scale = 1 + LensMotion.liftScale * lift + LensMotion.pressScale * pressLift
        let size = CGSize(
            width: restSize.width * scale + stretch * (along.width - LensMotion.crossSqueeze * along.height),
            height: restSize.height * scale + stretch * (along.height - LensMotion.crossSqueeze * along.width)
        )
        // Заливка уходит от взлёта до подлёта к клетке.
        let flight = max(raised, min(distance / LensMotion.transitDistance, 1))
        let clearing = max(LensMotion.liftClearing * flight, LensMotion.pressClearing * pressLift)
        ZStack {
            lens.filled(1 - clearing)
                .frame(width: size.width, height: size.height)
                .position(center)
            // Окно непрозрачно (бумага и копия клеток) — и при Reduce Transparency цифры под линзой видны.
            if window > 0 {
                LensWindow(
                    rect: CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height),
                    anchor: CGPoint(x: center.x - Self.anchorShift(restWidth: restSize.width), y: center.y),
                    canvas: canvas,
                    backdrop: backdrop
                )
                .opacity(window)
                // Появляется и исчезает вместе с кадром, а не переходом поверх пружины.
                .transition(.identity)
            }
        }
    }
}

extension FlyingLens {
    /// Насколько точка увеличения окна левее центра: так цифры клетки в окне ложатся на место цифр линзы
    /// (отступ слева у клетки 7, у линзы 12 при выступе 6), и при посадке они сменяются почти без сдвига.
    static func anchorShift(restWidth: CGFloat) -> CGFloat {
        let scale = LensMotion.magnification
        let lensDigits = CalendarMetrics.lensPadding.leading - CalendarMetrics.lensOutset
        let fromCellLeading = (lensDigits - scale * CalendarMetrics.cellPadding.leading) / (1 - scale)
        return restWidth / 2 - CalendarMetrics.lensOutset - fromCellLeading
    }
}

/// Середина поднятой линзы: клетки под ней увеличены и не размыты, как у системной линзы в полёте; по краю
/// остаётся системное стекло (окно мягко уходит в него). Зазоры между клетками — бумага экрана.
private struct LensWindow<Backdrop: View>: View {
    let rect: CGRect
    /// Точка, от которой увеличены клетки (в координатах сетки).
    let anchor: CGPoint
    let canvas: CGSize
    let backdrop: Backdrop

    var body: some View {
        let inset = LensMotion.windowInset
        ZStack(alignment: .topLeading) {
            Theme.canvas
            backdrop
                .frame(width: canvas.width, height: canvas.height)
                .scaleEffect(
                    LensMotion.magnification,
                    anchor: UnitPoint(x: anchor.x / max(canvas.width, 1), y: anchor.y / max(canvas.height, 1))
                )
        }
        .frame(width: canvas.width, height: canvas.height, alignment: .topLeading)
        .mask(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: max(Theme.Radius.lens - inset, 0), style: .continuous)
                .frame(width: max(rect.width - 2 * inset, 0), height: max(rect.height - 2 * inset, 0))
                .blur(radius: LensMotion.windowFeather)
                .offset(x: rect.minX + inset, y: rect.minY + inset)
        }
        // Гаснет целиком: без группы бумага-подложка просвечивает отдельно и окно темнеет в наплыве.
        .compositingGroup()
        .allowsHitTesting(false)
    }
}
