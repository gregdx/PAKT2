import SwiftUI

/// Generic "advanced filters" modal. Declarative: callers describe the
/// sections they want to expose (categories with labels/colors, durations,
/// an optional featured toggle), and the sheet wires selection state through
/// a binding. Designed so Events can adopt the same UI in a follow-up.
///
/// Binding: the caller passes a `FreeFilterSelection` binding. The sheet
/// mutates it in place and exposes Reset / Apply buttons. Apply simply
/// dismisses — the binding has already mutated.
struct AdvancedFiltersSheet: View {
    @Binding var selection: FreeFilterSelection
    let categories: [FilterCategoryOption]
    let showDurationSection: Bool
    let showFeaturedToggle: Bool
    /// Optional title override (defaults to "Filters"). Useful when reusing
    /// the sheet for Events or other contexts.
    var title: String = L10n.t("advanced_filters")

    @Environment(\.dismiss) private var dismiss

    /// Lightweight descriptor used to render a category chip. We don't reach
    /// into ActCategory directly so that Events (which have their own
    /// category enum) can reuse this sheet.
    struct FilterCategoryOption: Identifiable, Hashable {
        let id: String       // raw value that ends up in selection.categories
        let label: String
        let color: Color
        let icon: String?
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if !categories.isEmpty {
                        section(title: L10n.t("categories")) {
                            FlowChips(items: categories) { opt in
                                let isOn = selection.categories.contains(opt.id)
                                chip(label: opt.label,
                                     icon: opt.icon,
                                     color: opt.color,
                                     isSelected: isOn) {
                                    if isOn {
                                        selection.categories.remove(opt.id)
                                    } else {
                                        selection.categories.insert(opt.id)
                                    }
                                }
                            }
                        }
                    }

                    if showDurationSection {
                        section(title: L10n.t("duration")) {
                            HStack(spacing: 8) {
                                ForEach(ActivityDuration.allCases) { d in
                                    let isOn = selection.durations.contains(d)
                                    chip(label: d.label,
                                         icon: "clock",
                                         color: Theme.blue,
                                         isSelected: isOn) {
                                        if isOn {
                                            selection.durations.remove(d)
                                        } else {
                                            selection.durations.insert(d)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    if showFeaturedToggle {
                        Toggle(isOn: $selection.featuredOnly) {
                            HStack(spacing: 8) {
                                Image(systemName: "star.fill")
                                    .foregroundColor(.yellow)
                                Text(L10n.t("featured_only"))
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(Theme.text)
                            }
                        }
                        .tint(Theme.blue)
                        .padding(.horizontal, 4)
                    }
                }
                .padding(20)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.t("reset_filters")) {
                        selection = FreeFilterSelection(searchText: selection.searchText)
                    }
                    .foregroundColor(Theme.textMuted)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.t("apply_filters")) { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func section<Content: View>(title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(Theme.textMuted)
            content()
        }
    }

    private func chip(label: String,
                      icon: String?,
                      color: Color,
                      isSelected: Bool,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon = icon {
                    Image(systemName: icon).font(.system(size: 11, weight: .semibold))
                }
                Text(label).font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(isSelected ? .white : Theme.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected ? color : color.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
    }
}

/// Minimalist flow layout so chips wrap onto multiple lines. Avoids pulling
/// in a dependency; good enough for <20 chips.
private struct FlowChips<Item: Identifiable & Hashable, ChipView: View>: View {
    let items: [Item]
    @ViewBuilder let chip: (Item) -> ChipView

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items) { item in
                chip(item)
            }
        }
    }
}

/// iOS 16+ Layout implementing a basic left-to-right wrapping flow.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            _ = maxWidth
        }
    }
}

// MARK: - Convenience

extension FreeFilterSelection {
    init(searchText: String) {
        self.init()
        self.searchText = searchText
    }
}

extension AdvancedFiltersSheet.FilterCategoryOption {
    /// Build the standard ActCategory chip options used by the Free section.
    static var freeActivityCategories: [AdvancedFiltersSheet.FilterCategoryOption] {
        ActCategory.allCases.map { cat in
            .init(id: cat.rawValue, label: cat.label, color: cat.color, icon: cat.icon)
        }
    }
}
