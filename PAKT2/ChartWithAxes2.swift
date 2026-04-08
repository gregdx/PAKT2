import SwiftUI

struct ChartWithAxes: View {
    let histories   : [[Int]]
    let colors      : [Color]
    let goalMinutes : Int
    let xLabels     : [String]
    var names       : [String] = []
    var uids        : [String] = []

    @State private var showFullScreen = false

    private var allPoints: [Int] { histories.flatMap { $0 } }
    private var maxV: Int { max(allPoints.max() ?? 1, goalMinutes + 20) }
    private var minV: Int { max(0, (allPoints.min() ?? 0) - 20) }

    private var yTicks: [Int] {
        // Round to nearest 30 min, generate 4-5 clean ticks
        let step = 30 // always 30 min intervals
        let bottomTick = (minV / step) * step          // round down
        let topTick    = ((maxV / step) + 1) * step    // round up
        var ticks: [Int] = []
        var t = bottomTick
        while t <= topTick {
            ticks.append(t)
            t += step
        }
        // Keep at most 5 ticks, evenly spaced
        if ticks.count > 5 {
            let stride = (ticks.count - 1) / 4
            ticks = (0..<5).map { ticks[min($0 * stride, ticks.count - 1)] }
        }
        return ticks
    }

    func yPosition(for value: Int, in height: CGFloat) -> CGFloat {
        let range = CGFloat(maxV - minV)
        let ratio = range > 0 ? CGFloat(value - minV) / range : 0.5
        return height * (1 - 0.08) - ratio * height * 0.84
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 0) {

                // Y axis
                GeometryReader { geo in
                    ZStack {
                        ForEach(Array(yTicks.enumerated()), id: \.offset) { _, tick in
                            Text(formatTime(tick))
                                .font(AppFont.sans(12))
                                .foregroundColor(Theme.textFaint)
                                .frame(width: 36, alignment: .trailing)
                                .position(
                                    x: 18,
                                    y: yPosition(for: tick, in: geo.size.height)
                                )
                        }
                    }
                }
                .frame(width: 36)

                // Chart area
                GeometryReader { geo in
                    ZStack {
                        // Grid lines
                        ForEach(Array(yTicks.enumerated()), id: \.offset) { _, tick in
                            let y = yPosition(for: tick, in: geo.size.height)
                            Path { p in
                                p.move(to: CGPoint(x: 0, y: y))
                                p.addLine(to: CGPoint(x: geo.size.width, y: y))
                            }
                            .stroke(
                                Theme.border.opacity(0.5),
                                style: StrokeStyle(lineWidth: 0.5, dash: [3, 3])
                            )
                        }

                        // Goal line
                        let yObj = yPosition(for: goalMinutes, in: geo.size.height)
                        Path { p in
                            p.move(to: CGPoint(x: 0, y: yObj))
                            p.addLine(to: CGPoint(x: geo.size.width, y: yObj))
                        }
                        .stroke(
                            Theme.textMuted,
                            style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                        )

                        Text(L10n.t("goal"))
                            .font(AppFont.sans(12))
                            .foregroundColor(Theme.textMuted)
                            .position(x: 18, y: yObj - 9)

                        // Curves
                        ForEach(Array(histories.enumerated()), id: \.offset) { i, pts in
                            CurveShape(
                                points: pts,
                                maxValue: maxV,
                                minValue: minV
                            )
                            .stroke(
                                colors[safe: i] ?? Theme.textMuted,
                                style: StrokeStyle(
                                    lineWidth: histories.count == 1
                                        ? 2
                                        : (i == 0 || i == histories.count - 1 ? 2.5 : 1.6),
                                    lineCap: .round,
                                    lineJoin: .round
                                )
                            )
                            .opacity(
                                histories.count == 1
                                    ? 1
                                    : (i == 0 || i == histories.count - 1 ? 1.0 : 0.55)
                            )
                        }

                        // Details button
                        HStack(spacing: 4) {
                            Text(L10n.t("details"))
                                .font(AppFont.sans(12))
                                .foregroundColor(Theme.textFaint)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12))
                                .foregroundColor(Theme.textFaint)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.bg.opacity(0.85))
                        .cornerRadius(6)
                        .position(x: geo.size.width - 32, y: geo.size.height - 12)
                    }
                }
                .frame(height: 130)
            }
            .frame(height: 130)

            // X axis
            HStack(spacing: 0) {
                Spacer().frame(width: 40)
                HStack {
                    ForEach(Array(xLabels.enumerated()), id: \.offset) { i, label in
                        Text(label)
                            .font(AppFont.sans(13))
                            .foregroundColor(Theme.textFaint)
                        if i < xLabels.count - 1 { Spacer() }
                    }
                }
            }


        }
        .padding(16)
        .liquidGlass(cornerRadius: 16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Theme.border, lineWidth: 0.5)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(chartAccessibilityLabel)
    }

    private var chartAccessibilityLabel: String {
        guard let first = histories.first, !first.isEmpty else { return L10n.t("no_data_yet") }
        let pairs = zip(xLabels, first).map { "\($0): \(formatTime($1))" }
        return "\(L10n.t("goal")) \(formatTime(goalMinutes)). " + pairs.joined(separator: ", ")
    }
}

