import SwiftUI

/// Filters for the Events feed. Deliberately does NOT expose a "When"
/// section — the time chip (For You / Today / Weekend / Later / My events)
/// in the parent view is the only temporal selector. Duplicating it here
/// confused users in earlier iterations.
struct EventsFiltersSheet: View {
    @Binding var categories: Set<String>
    @Binding var friendsOnly: Bool

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    whatSection
                    whoSection
                    Spacer().frame(height: 40)
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
            }
            .background(Theme.bg)
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !categories.isEmpty || friendsOnly {
                        Button("Reset") {
                            categories.removeAll()
                            friendsOnly = false
                        }
                        .foregroundColor(Theme.red)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var whatSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Type", "Categories of events")
            FlowLayout(spacing: 8) {
                ForEach(EventsFeedView.CategoryChip.all) { chip in
                    let active = categories.contains(chip.id)
                    Button {
                        if active { categories.remove(chip.id) }
                        else      { categories.insert(chip.id) }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: chip.icon)
                                .font(.system(size: 12, weight: .bold))
                            Text(chip.label)
                                .font(.system(size: 14, weight: active ? .bold : .semibold))
                        }
                        .foregroundColor(active ? .white : Theme.text)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(
                            Capsule().fill(active ? Theme.orange : Theme.bgCard)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var whoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Social", "Narrow by who's going")
            toggleRow(
                title: "Friends only",
                subtitle: "Events where at least one friend is going",
                icon: "person.2.fill",
                isOn: $friendsOnly
            )
        }
    }

    private func sectionHeader(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(Theme.text)
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundColor(Theme.textMuted)
        }
    }

    private func toggleRow(title: String, subtitle: String, icon: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(isOn.wrappedValue ? Theme.orange : Theme.textMuted)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.text)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textMuted)
            }
            Spacer()
            Toggle("", isOn: isOn).labelsHidden().tint(Theme.orange)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.bgCard))
    }
}

/// Lightweight wrapping layout (iOS 16+) so category chips wrap to the next
/// line instead of overflowing the sheet. Used only inside the filters sheet.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
