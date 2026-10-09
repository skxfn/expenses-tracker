import SwiftUI

/// Стеклянный тост (DESIGN.md → Motion & Haptics, `toast.*`): капсула 50 над таб-баром, текст SF 15/600,
/// необязательная кнопка («Отменить»). Только вид: таймер 4 с, фиксацию удаления и объявление VoiceOver
/// делает экран; пауза таймера — по `onPressingChanged` (палец на тосте).
struct GlassToast: View {
    struct Action {
        let title: LocalizedStringKey
        let handler: () -> Void
    }

    let message: LocalizedStringKey
    var action: Action?
    var onPressingChanged: (Bool) -> Void = { _ in }

    @State private var isPressing = false
    @State private var actionCount = 0

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Text(message)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
            if let action {
                Spacer(minLength: Theme.Spacing.sm)
                Button {
                    actionCount += 1
                    action.handler()
                } label: {
                    Text(action.title)
                        .foregroundStyle(Theme.ink)
                        .frame(minHeight: Theme.Size.chip)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .sensoryFeedback(Haptic.light, trigger: actionCount)
            }
        }
        .typeStyle(.callout)
        .padding(.horizontal, Theme.Spacing.xl)
        .frame(minHeight: Theme.Size.actionButton)
        .glassEffect(.regular, in: .capsule)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in setPressing(true) }
                .onEnded { _ in setPressing(false) }
        )
        .accessibilityElement(children: .combine)
    }

    private func setPressing(_ pressing: Bool) {
        guard pressing != isPressing else { return }
        isPressing = pressing
        onPressingChanged(pressing)
    }
}

extension View {
    /// Показывает тост у нижнего края: появление `enter` (снизу + opacity), уход `exit` (opacity);
    /// при Reduce Motion — только opacity.
    func glassToast<Toast: View>(
        isPresented: Bool,
        bottomPadding: CGFloat = Theme.Spacing.sm,
        @ViewBuilder toast: () -> Toast
    ) -> some View {
        modifier(GlassToastPresenter(isPresented: isPresented, bottomPadding: bottomPadding, toast: toast()))
    }
}

private struct GlassToastPresenter<Toast: View>: ViewModifier {
    let isPresented: Bool
    let bottomPadding: CGFloat
    let toast: Toast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if isPresented {
                toast
                    .padding(.horizontal, Theme.Spacing.screen)
                    .padding(.bottom, bottomPadding)
                    .transition(transition)
            }
        }
    }

    private var transition: AnyTransition {
        if reduceMotion {
            return .opacity.animation(Motion.reduced)
        }
        return .asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity).animation(Motion.enter),
            removal: .opacity.animation(Motion.exit)
        )
    }
}

#if DEBUG
private struct ToastDemo: View {
    @State private var isShown = true
    @State private var isPaused = false

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Button(isShown ? "Скрыть" : "Показать") { isShown.toggle() }
            Text(isPaused ? "таймер на паузе" : "таймер идёт")
                .typeStyle(.footnote)
                .foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 160, alignment: .top)
        .background(AuraBackground(tones: [.shalfey, .abrikos]))
        .glassToast(isPresented: isShown) {
            GlassToast(
                message: "Удалено",
                action: .init(title: "Отменить") { isShown = false },
                onPressingChanged: { isPaused = $0 }
            )
        }
    }
}

#Preview("Тост") {
    ThemePreview { ToastDemo() }
}
#endif
