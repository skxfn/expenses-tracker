import SwiftUI

/// Анимации раскрытия категории (§3.6): `viz-expand`, проявление оттенков со стаггером `viz-shades`,
/// `viz-collapse` (оттенки гаснут за 0,12 с, затем форма). При Reduce Motion движение выключено:
/// состояния сменяются кроссфейдом целиком (`vizCrossfade(on:)`).
nonisolated struct VizMotion {
    let isExpanded: Bool
    let reduceMotion: Bool

    /// Форма: рост раскрытой части или возврат к обзору.
    var shape: Animation? {
        reduceMotion ? nil : (isExpanded ? Motion.vizExpand : Motion.vizCollapse)
    }

    /// Остальные части: при раскрытии гаснут быстро, при сворачивании проявляются вместе с формой.
    var others: Animation? {
        reduceMotion ? nil : (isExpanded ? Motion.vizShadesOut : Motion.vizCollapse)
    }

    /// Основа раскрытой части (основной тон под оттенками) прячется, когда проявился последний оттенок,
    /// и сразу возвращается при сворачивании — иначе в зазорах между оттенками виден основной тон.
    func base(lastShadeIndex: Int) -> Animation? {
        guard !reduceMotion else { return nil }
        return isExpanded ? Motion.vizShade(index: max(lastShadeIndex, 0)) : nil
    }
}

extension View {
    /// Проявление оттенка `index` со стаггером при появлении и гашение при сворачивании.
    func vizShade(index: Int, visible: Bool) -> some View {
        modifier(VizShadeAppearance(index: index, visible: visible))
    }

    /// Reduce Motion: вместо движения — кроссфейд состояний по ключу (`Motion.reduced`, только opacity).
    func vizCrossfade<Key: Hashable>(on key: Key) -> some View {
        modifier(VizCrossfade(key: key))
    }
}

private struct VizShadeAppearance: ViewModifier {
    let index: Int
    let visible: Bool
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let isShown = visible && (appeared || reduceMotion)
        content
            .opacity(isShown ? 1 : 0)
            .animation(animation(isShown), value: isShown)
            .onAppear { appeared = true }
    }

    private func animation(_ isShown: Bool) -> Animation? {
        guard !reduceMotion else { return nil }
        return isShown ? Motion.vizShade(index: index) : Motion.vizShadesOut
    }
}

private struct VizCrossfade<Key: Hashable>: ViewModifier {
    let key: Key
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            ZStack {
                content
                    .id(key)
                    .transition(.opacity)
            }
            .animation(Motion.reduced, value: key)
        } else {
            content
        }
    }
}
