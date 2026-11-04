import SwiftUI

// MARK: - Card

/// Flache Inhaltsfläche. Keine Schatten, keine Kontur – Hierarchie entsteht über
/// Fläche, Abstand und Typografie.
struct Card<Content: View>: View {
    var padding: CGFloat = Theme.Space.m
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }
}

/// Kopfzeile einer Karte mit optionalem Symbol und Zusatz rechts.
struct CardHeader<Trailing: View>: View {
    let title: String
    var symbol: String? = nil
    var tint: Color = .secondary
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(.cardTitle)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            trailing
        }
    }
}

extension CardHeader where Trailing == EmptyView {
    init(title: String, symbol: String? = nil, tint: Color = .secondary) {
        self.title = title
        self.symbol = symbol
        self.tint = tint
        self.trailing = EmptyView()
    }
}

// MARK: - Section title

struct SectionTitle: View {
    let title: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.weight(.semibold))
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.medium))
            }
        }
        .padding(.horizontal, Theme.Space.xxs)
        .padding(.top, Theme.Space.xs)
    }
}

// MARK: - Meter

/// Flacher, linearer Fortschrittsbalken.
struct LinearMeter: View {
    var progress: Double
    var tint: Color = Theme.accent
    var height: CGFloat = 6
    /// Wird der Zielwert überschritten, wird der Überschuss dezent markiert.
    var showsOverflow: Bool = true

    var body: some View {
        GeometryReader { proxy in
            let clamped = min(max(progress, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.fill)
                Capsule()
                    .fill(progress > 1 && showsOverflow ? Theme.warning : tint)
                    .frame(width: max(clamped * proxy.size.width, clamped > 0 ? height : 0))
            }
        }
        .frame(height: height)
        .animation(.smooth(duration: 0.45), value: progress)
        .accessibilityElement()
        .accessibilityValue(Text("\(Int((progress * 100).rounded())) Prozent"))
    }
}

/// Flacher Ring – nur für einzelne, zentrale Kennzahlen.
struct RingMeter: View {
    var progress: Double
    var tint: Color = Theme.accent
    var lineWidth: CGFloat = 8

    var body: some View {
        ZStack {
            Circle().stroke(Theme.fill, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(progress > 1 ? Theme.warning : tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(.smooth(duration: 0.5), value: progress)
        .accessibilityElement()
        .accessibilityValue(Text("\(Int((progress * 100).rounded())) Prozent"))
    }
}

/// Zeile mit Bezeichnung, Ist/Soll und Balken (z. B. Makronährstoff).
struct MetricRow: View {
    let label: String
    let value: Double
    let target: Double
    var unit: String = "g"
    var tint: Color = Theme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.subheadline)
                Spacer()
                Text("\(Fmt.number(value)) / \(Fmt.number(target)) \(unit)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            LinearMeter(progress: target > 0 ? value / target : 0, tint: tint)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Kennzahl mit Einheit und Beschriftung.
struct StatValue: View {
    let value: String
    var unit: String? = nil
    let label: String
    var valueFont: Font = .metricSmall
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(valueFont)
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .contentTransition(.numericText())
                if let unit {
                    Text(unit)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Chips

/// Auswahl-Chip für Mehrfach- oder Einfachauswahl.
struct ChoiceChip: View {
    let title: String
    var symbol: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol {
                    Image(systemName: symbol).font(.footnote.weight(.semibold))
                }
                Text(title).font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background(isSelected ? Theme.accent : Theme.fill, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Einfache, umbrechende Anordnung für Chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Badges & Hinweise

struct Badge: View {
    let text: String
    var tint: Color = .secondary

    var body: some View {
        Text(text)
            .font(.caption2Strong)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(tint)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

struct QualityBadge: View {
    let quality: DataQuality

    var body: some View {
        Label(quality.title, systemImage: quality.symbol)
            .font(.caption2Strong)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(quality.tint)
            .background(quality.tint.opacity(0.12), in: Capsule())
            .accessibilityLabel("Datenqualität: \(quality.title)")
    }
}

/// Dezenter Hinweis, z. B. für Schätzungen oder Sicherheitsregeln.
struct InfoNote: View {
    let text: String
    var symbol: String = "info.circle"
    var tint: Color = .secondary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol)
                .font(.footnote)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
    }
}

// MARK: - Glas-Steuerelemente

/// Runder, schwebender Glas-Button für die Steuerungsebene.
struct GlassIconButton: View {
    let systemImage: String
    var accessibilityLabel: String
    var size: CGFloat = 48
    var tint: Color? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.38, weight: .semibold))
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(tint.map { Glass.regular.tint($0).interactive() } ?? Glass.regular.interactive(), in: .circle)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// Primäre, breite Aktion (z. B. „Weiter“) im Liquid-Glass-Stil.
struct PrimaryActionButton: View {
    let title: String
    var systemImage: String? = nil
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                if let systemImage { Image(systemName: systemImage) }
            }
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .disabled(!isEnabled)
    }
}

// MARK: - Zeilen

/// Navigations- oder Aktionszeile in Listen-Optik, aber innerhalb von Cards nutzbar.
struct RowLabel: View {
    let title: String
    var subtitle: String? = nil
    let symbol: String
    var tint: Color = Theme.accent
    var value: String? = nil

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            Image(systemName: symbol)
                .font(.body.weight(.medium))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.body)
                if let subtitle {
                    Text(subtitle).font(.footnote).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }
}

/// Numerisches Eingabefeld mit Einheit, für Formulare.
struct NumberField: View {
    let title: String
    @Binding var value: Double?
    var unit: String
    var fractionDigits: Int = 1

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("–", value: $value, format: .number.precision(.fractionLength(0...fractionDigits)))
                .keyboardType(fractionDigits > 0 ? .decimalPad : .numberPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 110)
                .monospacedDigit()
            Text(unit)
                .foregroundStyle(.secondary)
                .frame(minWidth: 28, alignment: .leading)
        }
    }
}

// MARK: - Screen-Container

extension View {
    /// Standard-Hintergrund und Scroll-Verhalten für Inhaltsbildschirme.
    func screenBackground() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Theme.background)
    }
}
