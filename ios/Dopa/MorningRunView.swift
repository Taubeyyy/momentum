import SwiftUI

/// Die laufende Morgen-Checkliste: Zeitbalken bis zur Abfahrt und
/// „Wo solltest du gerade ungefähr sein?“ – gegen das Zeitgefühl, das morgens fehlt.
struct MorningRunView: View {
    @EnvironmentObject private var store: Store
    @State private var celebrated = false
    @State private var showTime = false

    var body: some View {
        let m = store.morning
        let leave = store.morningLeaveDate
        let start = m.startedAt ?? Date()

        List {
            Section {
                TimelineView(.periodic(from: .now, by: 5)) { context in
                    header(m, start: start, leave: leave, now: context.date)
                }
                .accentCard()
            }

            Section {
                ForEach(m.steps) { step in
                    let done = m.checked.contains(step.id)
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        store.toggleMorningStep(step.id)
                    } label: {
                        HStack(spacing: 12) {
                            RoundCheck(done: done)
                            Text(step.title)
                                .strikethrough(done)
                                .foregroundStyle(done ? Color.secondary : Color.primary)
                                .animation(.easeOut(duration: 0.2), value: done)
                            Spacer()
                            Text("\(step.minutes) Min")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
            .dopaRow()

            if !m.checked.isEmpty {
                Section {
                    Button("Von vorn", role: .destructive) { store.resetMorning() }
                }
                .dopaRow()
            }
        }
        .dopaBackground()
        .navigationTitle("Morgen")
        .toolbar(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showTime = true } label: { Image(systemName: "clock") }
                    .accessibilityLabel("Heute andere Zeit")
            }
        }
        .sheet(isPresented: $showTime) {
            TodayTimeSheet(title: "Heute los um", isOverride: m.todayLeave != nil,
                           onSet: { store.setMorningLeaveToday($0) }, minutes: m.leaveToday)
        }
        .onAppear { store.startMorningIfNeeded() }
        .onChange(of: m.checked.count) { count in
            if count == m.steps.count, count > 0, !celebrated {
                celebrated = true
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
    }

    @ViewBuilder
    private func header(_ m: Morning, start: Date, leave: Date, now: Date) -> some View {
        let allDone = !m.steps.isEmpty && m.checked.count == m.steps.count
        VStack(alignment: .leading, spacing: 10) {
            if allDone {
                Text("Fertig 🎉")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                Text(m.untimed ? "Ohne Uhr geschafft." : leave > now ? "\(Int(leave.timeIntervalSince(now) / 60)) Min Luft bis zur Abfahrt." : "Los geht's.")
                    .opacity(0.85)
            } else if m.untimed {
                Text("Heute ohne Uhr")
                    .font(.system(size: 28, weight: .bold))
                Text("\(m.checked.count) von \(m.steps.count) · kein Countdown, nur abhaken.")
                    .opacity(0.85)
            } else if now < leave {
                Text("Los um \(ClockTime.string(ClockTime.minutes(of: leave)))")
                    .font(.headline)
                Text(timerInterval: now...leave, countsDown: true)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .monospacedDigit()
                ProgressView(timerInterval: start...max(start, leave), countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .tint(.white)
                pace(m, start: start, now: now)
            } else {
                Text("Abfahrtszeit ist erreicht")
                    .font(.title2.bold())
                Text("Nur noch das Nötigste: Handy, Schlüssel, Schuhe.")
                    .opacity(0.85)
                Button("Heute später los?") { showTime = true }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DS.purpleMuted)
                    .buttonStyle(.plain)
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 6)
    }

    /// Plan-Minuten der erledigten Schritte vs. vergangene Minuten → vorne / im Plan / hinten.
    @ViewBuilder
    private func pace(_ m: Morning, start: Date, now: Date) -> some View {
        let elapsed = now.timeIntervalSince(start) / 60
        let planned = Double(m.steps.filter { m.checked.contains($0.id) }.reduce(0) { $0 + $1.minutes })
        let diff = Int((planned - elapsed).rounded())
        let expected = currentStep(m, elapsed: elapsed)

        HStack {
            if diff >= 1 {
                Label("\(diff) Min vorne", systemImage: "hare")
            } else if diff <= -2 {
                Label("\(-diff) Min hinten", systemImage: "tortoise")
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.orange.opacity(0.85), in: Capsule())
            } else {
                Label("Im Plan", systemImage: "checkmark")
            }
            Spacer()
        }
        .font(.subheadline.weight(.semibold))
        if let expected {
            Text("Jetzt ungefähr dran: \(expected.title)")
                .font(.footnote)
                .opacity(0.85)
        }
    }

    /// Welcher Schritt laut Plan gerade dran wäre.
    private func currentStep(_ m: Morning, elapsed: Double) -> RoutineStep? {
        var sum = 0.0
        for step in m.steps {
            sum += Double(step.minutes)
            if elapsed < sum { return step }
        }
        return m.steps.last
    }
}
