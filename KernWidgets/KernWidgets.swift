import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Bundle

@main
struct KernWidgetsBundle: WidgetBundle {
    var body: some Widget {
        CaloriesWidget()
        MacrosWidget()
        WaterWidget()
        NextWorkoutWidget()
        WeightTrendWidget()
        QuickMealWidget()
    }
}

// MARK: - Farben (lokal, die Extension sieht das App-Theme nicht)

enum WidgetPalette {
    static let accent = dynamic(light: 0x1E7F5C, dark: 0x4CC492)
    static let protein = dynamic(light: 0x3767D6, dark: 0x7AA2FF)
    static let carbs = dynamic(light: 0xC98A1B, dark: 0xF0B557)
    static let fat = dynamic(light: 0xB8507A, dark: 0xE88AAE)
    static let water = dynamic(light: 0x1F8FC7, dark: 0x5CC2EE)
    static let training = dynamic(light: 0xD45A2E, dark: 0xFF8A5C)
    static let weight = dynamic(light: 0x5A5AD6, dark: 0x9C9CFF)
    static let warning = dynamic(light: 0xC2410C, dark: 0xFB923C)
    static let track = Color(uiColor: .tertiarySystemFill)
    static let background = Color(uiColor: .systemBackground)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
}

// MARK: - Timeline

struct KernEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct KernProvider: TimelineProvider {
    func placeholder(in context: Context) -> KernEntry {
        KernEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (KernEntry) -> Void) {
        let snapshot = context.isPreview ? WidgetSnapshot.placeholder : (WidgetSnapshot.load() ?? .empty).normalizedForToday()
        completion(KernEntry(date: .now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<KernEntry>) -> Void) {
        let now = Date.now
        let snapshot = (WidgetSnapshot.load() ?? .empty).normalizedForToday(now: now)
        var entries = [KernEntry(date: now, snapshot: snapshot)]
        // Um Mitternacht auf einen leeren Tag wechseln.
        let midnight = Calendar.current.startOfDay(for: now.addingTimeInterval(86_400))
        entries.append(KernEntry(date: midnight, snapshot: snapshot.normalizedForToday(now: midnight)))
        let refresh = min(now.addingTimeInterval(30 * 60), midnight.addingTimeInterval(60))
        completion(Timeline(entries: entries, policy: .after(refresh)))
    }
}

// MARK: - Bausteine

private struct WidgetMeter: View {
    var progress: Double
    var tint: Color
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { proxy in
            let clamped = min(max(progress, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(WidgetPalette.track)
                Capsule()
                    .fill(progress > 1 ? WidgetPalette.warning : tint)
                    .frame(width: max(clamped * proxy.size.width, clamped > 0 ? height : 0))
            }
        }
        .frame(height: height)
    }
}

private struct WidgetRing: View {
    var progress: Double
    var tint: Color
    var lineWidth: CGFloat = 7

    var body: some View {
        ZStack {
            Circle().stroke(WidgetPalette.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(progress > 1 ? WidgetPalette.warning : tint,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

private struct WidgetLabel: View {
    let title: String
    let symbol: String
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tint)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

private func ratio(_ value: Double, _ target: Double) -> Double {
    target > 0 ? value / target : 0
}

// MARK: - Kalorien

struct CaloriesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "kern.calories", provider: KernProvider()) { entry in
            CaloriesWidgetView(snapshot: entry.snapshot)
                .containerBackground(for: .widget) { WidgetPalette.background }
                .widgetURL(URL(string: "kern://nutrition"))
        }
        .configurationDisplayName("Tageskalorien")
        .description("Verbleibendes Kalorienbudget für heute.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

private struct CaloriesWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: WidgetSnapshot

    private var remaining: Double { snapshot.kcalRemaining }
    private var progress: Double { ratio(snapshot.kcalConsumed, snapshot.kcalTarget) }
    private var unit: String { snapshot.energyUnit }

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: min(progress, 1)) {
                Image(systemName: "flame")
            } currentValueLabel: {
                Text(WidgetFormat.energy(max(remaining, 0), unit: unit))
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .minimumScaleFactor(0.6)
            }
            .gaugeStyle(.accessoryCircularCapacity)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label("Kalorien", systemImage: "flame")
                    .font(.caption.weight(.semibold))
                Text("\(WidgetFormat.energy(abs(remaining), unit: unit)) \(unit) \(remaining >= 0 ? "übrig" : "darüber")")
                    .font(.headline)
                    .monospacedDigit()
                Gauge(value: min(progress, 1)) { EmptyView() }
                    .gaugeStyle(.accessoryLinearCapacity)
            }
        case .accessoryInline:
            Text("\(WidgetFormat.energy(max(remaining, 0), unit: unit)) \(unit) übrig")
        case .systemMedium:
            HStack(spacing: 18) {
                ZStack {
                    WidgetRing(progress: progress, tint: WidgetPalette.accent, lineWidth: 9)
                    VStack(spacing: 0) {
                        Text(WidgetFormat.energy(abs(remaining), unit: unit))
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .minimumScaleFactor(0.6)
                        Text(remaining >= 0 ? "\(unit) übrig" : "\(unit) darüber")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                }
                .frame(width: 112, height: 112)
                VStack(alignment: .leading, spacing: 9) {
                    macroRow("Protein", snapshot.proteinConsumed, snapshot.proteinTarget, WidgetPalette.protein)
                    macroRow("Kohlenhydrate", snapshot.carbsConsumed, snapshot.carbsTarget, WidgetPalette.carbs)
                    macroRow("Fett", snapshot.fatConsumed, snapshot.fatTarget, WidgetPalette.fat)
                }
            }
        default:
            VStack(alignment: .leading, spacing: 6) {
                WidgetLabel(title: "Heute", symbol: "flame", tint: WidgetPalette.accent)
                Spacer(minLength: 0)
                Text(WidgetFormat.energy(abs(remaining), unit: unit))
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(remaining >= 0 ? "\(unit) übrig" : "\(unit) über dem Ziel")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                WidgetMeter(progress: progress, tint: WidgetPalette.accent)
                    .padding(.top, 2)
            }
        }
    }

    private func macroRow(_ title: String, _ value: Double, _ target: Double, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).font(.caption)
                Spacer()
                Text("\(WidgetFormat.number(value))/\(WidgetFormat.number(target)) g")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            WidgetMeter(progress: ratio(value, target), tint: tint, height: 4)
        }
    }
}

// MARK: - Makros / Protein

struct MacrosWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "kern.macros", provider: KernProvider()) { entry in
            MacrosWidgetView(snapshot: entry.snapshot)
                .containerBackground(for: .widget) { WidgetPalette.background }
                .widgetURL(URL(string: "kern://nutrition"))
        }
        .configurationDisplayName("Protein & Makros")
        .description("Fortschritt bei Protein, Kohlenhydraten und Fett.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

private struct MacrosWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: WidgetSnapshot

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: min(ratio(snapshot.proteinConsumed, snapshot.proteinTarget), 1)) {
                Text("P")
            } currentValueLabel: {
                Text(WidgetFormat.number(snapshot.proteinConsumed))
                    .font(.system(.caption, design: .rounded).weight(.semibold))
            }
            .gaugeStyle(.accessoryCircularCapacity)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label("Protein", systemImage: "chart.bar")
                    .font(.caption.weight(.semibold))
                Text("\(WidgetFormat.number(snapshot.proteinConsumed)) / \(WidgetFormat.number(snapshot.proteinTarget)) g")
                    .font(.headline)
                    .monospacedDigit()
                Gauge(value: min(ratio(snapshot.proteinConsumed, snapshot.proteinTarget), 1)) { EmptyView() }
                    .gaugeStyle(.accessoryLinearCapacity)
            }
        default:
            VStack(alignment: .leading, spacing: 8) {
                WidgetLabel(title: "Makros", symbol: "chart.bar", tint: WidgetPalette.protein)
                Spacer(minLength: 0)
                row("Protein", snapshot.proteinConsumed, snapshot.proteinTarget, WidgetPalette.protein)
                row("Kohlenhydrate", snapshot.carbsConsumed, snapshot.carbsTarget, WidgetPalette.carbs)
                row("Fett", snapshot.fatConsumed, snapshot.fatTarget, WidgetPalette.fat)
            }
        }
    }

    private func row(_ title: String, _ value: Double, _ target: Double, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.caption2)
                Spacer()
                Text("\(WidgetFormat.number(value)) g")
                    .font(.caption2.weight(.semibold).monospacedDigit())
            }
            WidgetMeter(progress: ratio(value, target), tint: tint, height: 4)
        }
    }
}

// MARK: - Wasser (interaktiv)

struct WaterWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "kern.water", provider: KernProvider()) { entry in
            WaterWidgetView(snapshot: entry.snapshot)
                .containerBackground(for: .widget) { WidgetPalette.background }
                .widgetURL(URL(string: "kern://log/water"))
        }
        .configurationDisplayName("Wasser")
        .description("Trinkfortschritt – mit einem Tipp 250 ml hinzufügen.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

private struct WaterWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: WidgetSnapshot

    private var progress: Double { ratio(snapshot.waterMl, snapshot.waterTargetMl) }

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: min(progress, 1)) {
                Image(systemName: "drop")
            } currentValueLabel: {
                Text(WidgetFormat.number(snapshot.waterMl / 1000, digits: 1))
                    .font(.system(.caption, design: .rounded).weight(.semibold))
            }
            .gaugeStyle(.accessoryCircularCapacity)
        default:
            VStack(alignment: .leading, spacing: 6) {
                WidgetLabel(title: "Wasser", symbol: "drop", tint: WidgetPalette.water)
                Spacer(minLength: 0)
                Text(WidgetFormat.volume(snapshot.waterMl))
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("von \(WidgetFormat.volume(snapshot.waterTargetMl))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                WidgetMeter(progress: progress, tint: WidgetPalette.water)
                Button(intent: AddWaterIntent(ml: 250)) {
                    Label("250 ml", systemImage: "plus")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(WidgetPalette.water)
                .padding(.top, 2)
            }
        }
    }
}

// MARK: - Nächstes Training

struct NextWorkoutWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "kern.nextWorkout", provider: KernProvider()) { entry in
            NextWorkoutWidgetView(snapshot: entry.snapshot)
                .containerBackground(for: .widget) { WidgetPalette.background }
                .widgetURL(URL(string: "kern://training"))
        }
        .configurationDisplayName("Nächstes Training")
        .description("Die nächste Einheit aus deinem aktiven Plan.")
        .supportedFamilies([.systemSmall, .accessoryRectangular])
    }
}

private struct NextWorkoutWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: WidgetSnapshot

    var body: some View {
        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label("Nächstes Training", systemImage: "dumbbell")
                    .font(.caption.weight(.semibold))
                Text(snapshot.nextWorkoutName ?? "Kein aktiver Plan")
                    .font(.headline)
                    .lineLimit(1)
                if let detail = snapshot.nextWorkoutDetail {
                    Text(detail).font(.caption).lineLimit(1)
                }
            }
        default:
            VStack(alignment: .leading, spacing: 6) {
                WidgetLabel(title: "Training", symbol: "dumbbell", tint: WidgetPalette.training)
                Spacer(minLength: 0)
                if let name = snapshot.nextWorkoutName {
                    Text(name)
                        .font(.headline)
                        .lineLimit(2)
                    if let detail = snapshot.nextWorkoutDetail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                } else {
                    Text("Kein aktiver Plan")
                        .font(.headline)
                    Text("Erstelle einen Plan in Kern.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Gewichtstrend

struct WeightTrendWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "kern.weightTrend", provider: KernProvider()) { entry in
            WeightTrendWidgetView(snapshot: entry.snapshot)
                .containerBackground(for: .widget) { WidgetPalette.background }
                .widgetURL(URL(string: "kern://progress"))
        }
        .configurationDisplayName("Gewichtstrend")
        .description("Letzte Messung und geglätteter Wochentrend.")
        .supportedFamilies([.systemSmall, .accessoryRectangular])
    }
}

private struct WeightTrendWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: WidgetSnapshot

    private var trendText: String {
        guard let trend = snapshot.weightTrendKgPerWeek else { return "Trend: noch zu wenig Daten" }
        let value = snapshot.weightUnit == "lb" ? trend * 2.204_622_62 : trend
        let formatted = abs(value).formatted(.number.precision(.fractionLength(0...2)).locale(WidgetFormat.locale))
        if abs(value) < 0.05 { return "Stabil" }
        return "\(value > 0 ? "+" : "−")\(formatted) \(snapshot.weightUnit)/Woche"
    }

    private var trendSymbol: String {
        guard let trend = snapshot.weightTrendKgPerWeek, abs(trend) >= 0.05 else { return "arrow.right" }
        return trend > 0 ? "arrow.up.right" : "arrow.down.right"
    }

    var body: some View {
        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label("Gewicht", systemImage: "scalemass")
                    .font(.caption.weight(.semibold))
                if let kg = snapshot.latestWeightKg {
                    Text("\(WidgetFormat.weight(kg, unit: snapshot.weightUnit)) \(snapshot.weightUnit)")
                        .font(.headline)
                        .monospacedDigit()
                } else {
                    Text("Keine Messung").font(.headline)
                }
                Text(trendText).font(.caption)
            }
        default:
            VStack(alignment: .leading, spacing: 6) {
                WidgetLabel(title: "Gewicht", symbol: "scalemass", tint: WidgetPalette.weight)
                Spacer(minLength: 0)
                if let kg = snapshot.latestWeightKg {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(WidgetFormat.weight(kg, unit: snapshot.weightUnit))
                            .font(.system(size: 30, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .minimumScaleFactor(0.6)
                        Text(snapshot.weightUnit)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Keine Messung")
                        .font(.headline)
                }
                Label(trendText, systemImage: trendSymbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Schnellaktion Mahlzeit

struct QuickMealWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "kern.quickMeal", provider: KernProvider()) { entry in
            QuickMealWidgetView(snapshot: entry.snapshot)
                .containerBackground(for: .widget) { WidgetPalette.background }
                .widgetURL(URL(string: "kern://log/food"))
        }
        .configurationDisplayName("Mahlzeit erfassen")
        .description("Direkt zur Lebensmittelsuche oder zum Barcode-Scanner.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

private struct QuickMealWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: WidgetSnapshot

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "fork.knife")
                    .font(.title3.weight(.semibold))
            }
            .accessibilityLabel("Mahlzeit erfassen")
        default:
            VStack(alignment: .leading, spacing: 8) {
                WidgetLabel(title: "Erfassen", symbol: "plus.circle", tint: WidgetPalette.accent)
                Spacer(minLength: 0)
                Link(destination: URL(string: "kern://log/food")!) {
                    quickRow(title: "Mahlzeit", symbol: "fork.knife")
                }
                Link(destination: URL(string: "kern://log/barcode")!) {
                    quickRow(title: "Barcode", symbol: "barcode.viewfinder")
                }
            }
        }
    }

    private func quickRow(title: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(WidgetPalette.accent)
                .frame(width: 26, height: 26)
                .background(WidgetPalette.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            Text(title)
                .font(.subheadline.weight(.medium))
            Spacer(minLength: 0)
        }
    }
}
