import SwiftUI
import SwiftData

/// Schnellerfassung über den mittleren Tab: häufige Aktionen mit einem Tipp
/// und direkter Zugang zum Coach.
struct QuickAddSheet: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppPreferences.self) private var prefs
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var coachText = ""
    @State private var addedWater = 0
    @FocusState private var coachFocused: Bool

    private struct Action: Identifiable {
        let id: String
        let title: String
        let symbol: String
        let tint: Color
        let perform: () -> Void
    }

    private var actions: [Action] {
        var list: [Action] = []
        let meal = MealType.suggested()
        if prefs.isEnabled(.nutrition) {
            list.append(Action(id: "food", title: "Mahlzeit", symbol: "fork.knife", tint: Theme.accent) {
                router.present(.foodSearch(meal: meal, day: .now))
            })
            list.append(Action(id: "barcode", title: "Barcode", symbol: "barcode.viewfinder", tint: Theme.accent) {
                router.present(.barcode(meal: meal, day: .now))
            })
            list.append(Action(id: "photo", title: "Foto", symbol: "camera", tint: Theme.accent) {
                router.present(.photoFood(meal: meal, day: .now))
            })
        }
        if prefs.isEnabled(.water) {
            list.append(Action(id: "water", title: "Wasser", symbol: "drop", tint: Theme.water) {
                router.present(.water)
            })
        }
        list.append(Action(id: "weight", title: "Gewicht", symbol: "scalemass", tint: Theme.weight) {
            router.present(.weightEntry)
        })
        if prefs.isEnabled(.training) {
            list.append(Action(id: "training", title: "Training", symbol: "dumbbell", tint: Theme.training) {
                router.show(tab: .training)
            })
        }
        if prefs.isEnabled(.supplements) {
            list.append(Action(id: "supplements", title: "Supplement", symbol: "pills", tint: Theme.supplement) {
                router.open(.supplements)
            })
        }
        if prefs.isEnabled(.measurements) {
            list.append(Action(id: "measure", title: "Körpermasse", symbol: "ruler", tint: Theme.weight) {
                router.present(.measurementEntry)
            })
        }
        if prefs.isEnabled(.cycle) {
            list.append(Action(id: "cycle", title: "Zyklus", symbol: "circle.dashed", tint: Theme.cycle) {
                router.open(.cycle)
            })
        }
        return list
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    coachField

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                        ForEach(actions) { action in
                            Button(action: action.perform) {
                                VStack(spacing: 8) {
                                    Image(systemName: action.symbol)
                                        .font(.title2.weight(.medium))
                                        .foregroundStyle(action.tint)
                                        .frame(height: 30)
                                    Text(action.title)
                                        .font(.footnote.weight(.medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                }
                                .frame(maxWidth: .infinity, minHeight: 88)
                                .background(Theme.fill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if prefs.isEnabled(.water) {
                        VStack(alignment: .leading, spacing: Theme.Space.xs) {
                            Text("Schnell trinken")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                            HStack(spacing: 8) {
                                ForEach(prefs.waterQuickAmounts.prefix(3), id: \.self) { ml in
                                    Button {
                                        LogService.logWater(ml: Double(ml), source: .quickAdd, in: context)
                                        addedWater += ml
                                    } label: {
                                        Label("\(ml) ml", systemImage: "drop.fill")
                                            .font(.subheadline.weight(.semibold).monospacedDigit())
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(Theme.water)
                                }
                            }
                            if addedWater > 0 {
                                Text("\(Fmt.volume(Double(addedWater))) hinzugefügt")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .transition(.opacity)
                            }
                        }
                        .sensoryFeedback(.increase, trigger: addedWater)
                    }
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.bottom, Theme.Space.l)
                .animation(.smooth, value: addedWater)
            }
            .navigationTitle("Erfassen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Schliessen")
                }
            }
        }
    }

    private var coachField: some View {
        HStack(spacing: Theme.Space.xs) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .foregroundStyle(Theme.accent)
            TextField("Sag dem Coach, was du erfassen willst …", text: $coachText, axis: .vertical)
                .lineLimit(1...3)
                .focused($coachFocused)
                .submitLabel(.send)
                .onSubmit(sendToCoach)
            if !coachText.isEmpty {
                Button(action: sendToCoach) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("An Coach senden")
            }
        }
        .padding(.horizontal, Theme.Space.s)
        .padding(.vertical, 12)
        .background(Theme.fill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func sendToCoach() {
        let text = coachText.trimmingCharacters(in: .whitespacesAndNewlines)
        router.present(.coach(prefill: text.isEmpty ? nil : text))
    }
}
