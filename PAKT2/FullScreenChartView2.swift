import SwiftUI

struct FullScreenChartView: View {
    let histories   : [[Int]]
    let colors      : [Color]
    let goalMinutes : Int
    let xLabels     : [String]
    let names       : [String]
    var uids        : [String] = []

    @Environment(\.dismiss) var dismiss
    @State private var avatarCache: [String: UIImage] = [:]

    // MARK: - Computed

    private var allPoints: [Int] { histories.flatMap { $0 } }
    private var maxV: Int { max(allPoints.max() ?? 1, goalMinutes + 20) }
    private var minV: Int { max(0, (allPoints.min() ?? 0) - 20) }

    private func avgMins(_ pts: [Int]) -> Int {
        let nonZero = pts.filter { $0 > 0 }
        guard !nonZero.isEmpty else { return 0 }
        return nonZero.reduce(0, +) / nonZero.count
    }
    private func wakingPct(_ minutes: Int) -> Int { Int(Double(minutes) / kWakingMinutesPerDay * 100) }
    private func daysPerYear(_ minutes: Int) -> Int { Int(Double(minutes) * 365.0 / 1440.0) }
    private var yTicks: [Int] {
        let step = 30
        let bottomTick = (minV / step) * step
        let topTick    = ((maxV / step) + 1) * step
        var ticks: [Int] = []
        var t = bottomTick
        while t <= topTick { ticks.append(t); t += step }
        if ticks.count > 5 {
            let s = (ticks.count - 1) / 4
            ticks = (0..<5).map { ticks[min($0 * s, ticks.count - 1)] }
        }
        return ticks
    }

    func yPosition(for value: Int, in height: CGFloat) -> CGFloat {
        let range = CGFloat(maxV - minV)
        let ratio = range > 0 ? CGFloat(value - minV) / range : 0.5
        return height * (1 - 0.06) - ratio * height * 0.88
    }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    header
                    chartView.padding(.horizontal, 24)
                    AppDivider()
                    wakingLifeSection
                    AppDivider()
                    raceSection
                    AppDivider()
                    worstMomentSection
                    Spacer().frame(height: 80)
                }
            }
        }
        .onAppear { loadAvatars() }
    }

    // MARK: - Header

    var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.t("details"))
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(Theme.text)
                Text("goal · \(formatTime(goalMinutes)) / day")
                    .font(.system(size: 15))
                    .foregroundColor(Theme.textFaint)
            }
            Spacer()
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 16))
                    .foregroundColor(Theme.textMuted)
                    .frame(width: 36, height: 36)
                    .liquidGlass(cornerRadius: 10)
            }
            .accessibilityLabel(L10n.t("done"))
        }
        .padding(.horizontal, 24)
        .padding(.top, 60)
        .padding(.bottom, 28)
    }

    // MARK: - Line chart (unchanged)

    var chartView: some View {
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                GeometryReader { geo in
                    ZStack {
                        ForEach(Array(yTicks.enumerated()), id: \.offset) { _, tick in
                            Text(formatTime(tick))
                                .font(.system(size: 12))
                                .foregroundColor(Theme.textFaint)
                                .frame(width: 44, alignment: .trailing)
                                .position(x: 20, y: yPosition(for: tick, in: geo.size.height))
                        }
                    }
                }
                .frame(width: 44)

                GeometryReader { geo in
                    ZStack {
                        ForEach(Array(yTicks.enumerated()), id: \.offset) { _, tick in
                            let y = yPosition(for: tick, in: geo.size.height)
                            Path { p in
                                p.move(to: CGPoint(x: 0, y: y))
                                p.addLine(to: CGPoint(x: geo.size.width, y: y))
                            }
                            .stroke(Theme.border.opacity(0.5),
                                    style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                        }

                        let yObj = yPosition(for: goalMinutes, in: geo.size.height)
                        Path { p in
                            p.move(to: CGPoint(x: 0, y: yObj))
                            p.addLine(to: CGPoint(x: geo.size.width, y: yObj))
                        }
                        .stroke(Theme.textMuted, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

                        Text(L10n.t("goal"))
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textMuted)
                            .position(x: 18, y: yObj - 10)

                        ForEach(Array(histories.enumerated()), id: \.offset) { i, pts in
                            CurveShape(points: pts, maxValue: maxV, minValue: minV)
                                .stroke(
                                    colors[safe: i] ?? Theme.textMuted,
                                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                                )
                                .opacity(histories.count == 1 ? 1 : (i == 0 || i == histories.count - 1 ? 1 : 0.5))

                            ForEach(Array(pts.enumerated()), id: \.offset) { j, val in
                                let xStep = geo.size.width / CGFloat(max(pts.count - 1, 1))
                                let x = CGFloat(j) * xStep
                                let y = yPosition(for: val, in: geo.size.height)
                                Circle()
                                    .fill(colors[safe: i] ?? Theme.textMuted)
                                    .frame(width: 5, height: 5)
                                    .position(x: x, y: y)
                            }
                        }
                    }
                }
                .frame(height: 180)
            }
            .frame(height: 180)

            HStack(spacing: 0) {
                Spacer().frame(width: 48)
                HStack {
                    ForEach(Array(xLabels.enumerated()), id: \.offset) { i, label in
                        Text(label)
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textFaint)
                        if i < xLabels.count - 1 { Spacer() }
                    }
                }
            }

            HStack(spacing: 16) {
                Spacer()
                ForEach(Array(names.enumerated()), id: \.offset) { i, name in
                    HStack(spacing: 5) {
                        Circle()
                            .fill(colors[safe: i] ?? Theme.textMuted)
                            .frame(width: 7, height: 7)
                        Text(name)
                            .font(.system(size: 13))
                            .foregroundColor(Theme.textMuted)
                    }
                }
            }
            .padding(.top, 6)
        }
        .padding(.vertical, 8)
    }

    // MARK: - Waking Life Arc Section

    var wakingLifeSection: some View {
        VStack(spacing: 0) {
            SectionTitle(text: "waking life consumed")
            let columns = [GridItem(.flexible()), GridItem(.flexible())]
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(Array(names.enumerated()), id: \.offset) { i, name in
                    wakingArcCard(index: i, name: name)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    func wakingArcCard(index i: Int, name: String) -> some View {
        let pts    = histories[safe: i] ?? []
        let avg    = avgMins(pts)
        let pct    = wakingPct(avg)
        let days   = daysPerYear(avg)
        let color  = colors[safe: i] ?? Theme.textMuted
        let uid    = uids[safe: i] ?? ""
        let daysOk = pts.filter { $0 > 0 && $0 <= goalMinutes }.count
        let total  = pts.filter { $0 > 0 }.count
        let arcPct = min(CGFloat(pct) / 100.0 * 0.75, 0.75)

        return VStack(spacing: 12) {
            ZStack {
                // Background arc (270°)
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(Theme.bgWarm, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(135))

                // Filled arc — member color
                Circle()
                    .trim(from: 0, to: arcPct)
                    .stroke(color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(135))

                // Center avatar
                if let img = avatarCache[uid] {
                    Image(uiImage: img)
                        .resizable().scaledToFill()
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                } else {
                    ZStack {
                        Circle().fill(Theme.bgCard).frame(width: 44, height: 44)
                        Text(String(name.prefix(1)).uppercased())
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(color)
                    }
                }
            }
            .frame(width: 96, height: 96)

            VStack(spacing: 3) {
                Text("\(pct)%")
                    .font(.system(size: 34, weight: .black))
                    .foregroundColor(color)
                Text(L10n.t("pct_waking"))
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textFaint)
                if days > 0 {
                    Text("\(days) days/year")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.textMuted)
                }
                if total > 0 {
                    Text("\(daysOk)/\(total) under goal")
                        .font(.system(size: 13))
                        .foregroundColor(daysOk == total ? Theme.green : Theme.textFaint)
                }
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)

            Text(name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Theme.textMuted)
        }
        .padding(.vertical, 8)
    }

    // MARK: - Race Section

    var raceSection: some View {
        VStack(spacing: 0) {
            SectionTitle(text: "screen time race")
            let maxAvg = names.indices.map { avgMins(histories[safe: $0] ?? []) }.max() ?? 1
            VStack(spacing: 10) {
                ForEach(Array(names.enumerated()), id: \.offset) { i, name in
                    raceBar(index: i, name: name, maxAvg: maxAvg)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    func raceBar(index i: Int, name: String, maxAvg: Int) -> some View {
        let pts      = histories[safe: i] ?? []
        let avg      = avgMins(pts)
        let color    = colors[safe: i] ?? Theme.textMuted
        let uid      = uids[safe: i] ?? ""
        let over    = avg > goalMinutes
        let fillPct = maxAvg > 0 ? CGFloat(avg) / CGFloat(maxAvg) : 0

        return HStack(spacing: 12) {
            ZStack {
                Circle().fill(Theme.bgWarm).frame(width: 38, height: 38)
                if let img = avatarCache[uid] {
                    Image(uiImage: img).resizable().scaledToFill()
                        .frame(width: 38, height: 38).clipShape(Circle())
                } else {
                    Text(String(name.prefix(1)).uppercased())
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(color)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Theme.text)
                    Spacer()
                    Text(avg > 0 ? formatTime(avg) : "--")
                        .font(.system(size: 16, weight: .black))
                        .foregroundColor(color)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.bgWarm).frame(height: 6)
                        Capsule()
                            .fill(color)
                            .frame(width: geo.size.width * fillPct, height: 6)
                        // Goal marker
                        let goalX = maxAvg > 0 ? geo.size.width * CGFloat(goalMinutes) / CGFloat(maxAvg) : 0
                        Rectangle()
                            .fill(Theme.textMuted.opacity(0.5))
                            .frame(width: 1.5, height: 12)
                            .offset(x: goalX - 0.75, y: -3)
                    }
                }
                .frame(height: 6)
                if over {
                    Text("+\(formatTime(avg - goalMinutes)) over limit")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.textFaint)
                }
            }
        }
        .padding(.vertical, 14)
    }

    // MARK: - Worst Moment

    var worstMomentSection: some View {
        let worst = findWorstDay()
        return VStack(spacing: 0) {
            SectionTitle(text: "worst moment")
            if let (name, day, mins, _) = worst {
                VStack(spacing: 14) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(name)
                                .font(.system(size: 14))
                                .foregroundColor(Theme.textFaint)
                            Text(formatTime(mins))
                                .font(.system(size: 48, weight: .bold))
                                .foregroundColor(Theme.red)
                            Text(day)
                                .font(.system(size: 14))
                                .foregroundColor(Theme.textFaint)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("\(wakingPct(mins))%")
                                .font(.system(size: 42, weight: .black))
                                .foregroundColor(Theme.red)
                            Text(L10n.t("pct_waking"))
                                .font(.system(size: 13))
                                .foregroundColor(Theme.textFaint)
                            Text("+\(formatTime(mins - goalMinutes))")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(Theme.red)
                            Text("over goal")
                                .font(.system(size: 13))
                                .foregroundColor(Theme.textFaint)
                        }
                    }

                    // Alarming bar
                    GeometryReader { geo in
                        let totalW = geo.size.width
                        let goalX  = maxV > 0 ? totalW * CGFloat(goalMinutes) / CGFloat(maxV) : 0
                        let fillW  = maxV > 0 ? totalW * min(CGFloat(mins) / CGFloat(maxV), 1) : 0
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.bgWarm).frame(height: 8)
                            Capsule()
                                .fill(Theme.red)
                                .frame(width: fillW, height: 8)
                            Rectangle()
                                .fill(Theme.text)
                                .frame(width: 2, height: 18)
                                .offset(x: goalX - 1, y: -5)
                            Text(L10n.t("goal"))
                                .font(.system(size: 12))
                                .foregroundColor(Theme.textMuted)
                                .offset(x: max(goalX - 10, 0), y: 10)
                        }
                    }
                    .frame(height: 24)

                    Text("that's \(daysPerYear(mins)) full days per year at this pace")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
    }

    private func findWorstDay() -> (String, String, Int, Color)? {
        var result: (String, String, Int, Color)? = nil
        for (i, pts) in histories.enumerated() {
            let name  = names[safe: i] ?? "?"
            let color = colors[safe: i] ?? Theme.textMuted
            for (j, val) in pts.enumerated() {
                if val > goalMinutes {
                    if val > (result?.2 ?? 0) {
                        result = (name, xLabels[safe: j] ?? "?", val, color)
                    }
                }
            }
        }
        return result
    }

    // MARK: - Avatar loading

    func loadAvatars() {
        for uid in uids where !uid.isEmpty {
            Task {
                if let img = await AuthManager.shared.fetchProfilePhoto(uid: uid) {
                    await MainActor.run { avatarCache[uid] = img }
                }
            }
        }
    }
}
