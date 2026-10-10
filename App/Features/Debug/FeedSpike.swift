#if DEBUG
import SwiftUI
import ExpenseCore

/// Спайк ленты (§6, §7 этап 0): `List(.plain)` + `swipeActions` + липкие стеклянные заголовки дней +
/// бумажный лист r 28 фоном строк + шапка над списком.
/// Аргументы: `-spikeEdge hidden|soft|hard` — край скролла (по умолчанию системный),
/// `-spikeScrolled YES` — сразу прокрутить к третьему дню (видно закреплённый заголовок),
/// `-spikeTopBar inset|bar` — шапка в `safeAreaInset(edge: .top)` или `safeAreaBar(edge: .top)` (iOS 26)
/// вместо рекомендуемой «шапка над List в VStack»: у них закреплённый заголовок дня уезжает под статус-бар.
struct FeedSpike: View {
    var body: some View {
        FeedSpikeContent()
    }
}

struct FeedSpikeContent: View {
    @State private var deleted: Set<UUID> = []
    @State private var repeatCount = 0

    private let edge = UserDefaults.standard.string(forKey: "spikeEdge")
    private let startsScrolled = UserDefaults.standard.bool(forKey: "spikeScrolled")
    private let topBar = UserDefaults.standard.string(forKey: "spikeTopBar")

    var body: some View {
        ScrollViewReader { proxy in
            List {
                Section {
                    SpikeSummary()
                        .padding(.top, Theme.Spacing.xl)
                        .padding(.bottom, Theme.Spacing.md)
                        .listRowInsets(rowInsets)
                        .listRowSeparator(.hidden)
                        .listRowBackground(
                            PaperSheetBackground.shape.fill(Theme.surface)
                        )
                }
                ForEach(SpikeSamples.days) { day in
                    Section {
                        ForEach(day.rows.filter { !deleted.contains($0.id) }) { row in
                            SpikeFeedRow(row: row)
                                .id(row.id)
                                .listRowInsets(rowInsets)
                                .listRowSeparator(.hidden)
                                .listRowBackground(Theme.surface)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        deleted.insert(row.id)
                                    } label: {
                                        Label("Удалить", systemImage: "trash")
                                    }
                                }
                                .swipeActions(edge: .leading) {
                                    Button {
                                        repeatCount += 1
                                    } label: {
                                        Label("Повторить", systemImage: "arrow.clockwise")
                                    }
                                    .tint(Theme.graphic)
                                }
                        }
                    } header: {
                        SpikeDayHeader(day: day)
                            .padding(.horizontal, Theme.Spacing.screen)
                            .padding(.vertical, Theme.Spacing.xs)
                            .background(headerBackground)
                            .listRowInsets(EdgeInsets())
                    }
                }
                Color.clear
                    .frame(height: 400)
                    .listRowBackground(Theme.surface)
                    .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .listSectionSpacing(0)
            .environment(\.defaultMinListRowHeight, 0)
            .modifier(SpikeEdgeEffect(mode: edge))
            .modifier(SpikeTopBar(mode: topBar))
            .background { AuraBackground(tones: [.shalfey, .abrikos]).ignoresSafeArea() }
            .task {
                guard startsScrolled, let target = SpikeSamples.days[2].rows.first?.id else { return }
                try? await Task.sleep(for: .milliseconds(400))
                proxy.scrollTo(target, anchor: .top)
            }
        }
    }

    /// `-spikeHeader clear` — заголовок без фона (как по умолчанию у plain List), иначе — лист под капсулой.
    private var headerBackground: Color {
        UserDefaults.standard.string(forKey: "spikeHeader") == "clear" ? .clear : Theme.surface
    }

    private var rowInsets: EdgeInsets {
        EdgeInsets(top: 0, leading: Theme.Spacing.screen, bottom: 0, trailing: Theme.Spacing.screen)
    }
}

private struct SpikeTopBar: ViewModifier {
    let mode: String?

    func body(content: Content) -> some View {
        switch mode {
        case "bar":
            content.safeAreaBar(edge: .top, spacing: Theme.Spacing.md) { SpikeHomeHeader() }
        case "inset":
            content.safeAreaInset(edge: .top, spacing: Theme.Spacing.md) { SpikeHomeHeader() }
        default:
            VStack(spacing: Theme.Spacing.md) {
                SpikeHomeHeader()
                content
            }
        }
    }
}

private struct SpikeEdgeEffect: ViewModifier {
    let mode: String?

    func body(content: Content) -> some View {
        switch mode {
        case "hidden": content.scrollEdgeEffectHidden(true, for: .all)
        case "soft": content.scrollEdgeEffectStyle(.soft, for: .all)
        case "hard": content.scrollEdgeEffectStyle(.hard, for: .all)
        default: content
        }
    }
}
#endif
