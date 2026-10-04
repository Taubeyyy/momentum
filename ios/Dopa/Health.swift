import Foundation
import HealthKit

/// Apple Watch über Health: Schlaf (letzte Nacht + Schnitt 7 Nächte, Bett/Aufwachen), Schritte und
/// Bewegungsminuten von heute. Nur lesen, bleibt auf dem Handy – Dot bekommt nur die Zahlen als eine Zeile.
/// Gefragt wird erst, wenn du es in den Einstellungen einschaltest – nie von allein.
@MainActor
final class Health: ObservableObject {
    static let shared = Health()

    private let store = HKHealthStore()
    @Published private(set) var sleepLastNight: TimeInterval?
    @Published private(set) var sleepAverage: TimeInterval?
    @Published private(set) var bedAt: Date?
    @Published private(set) var wokeAt: Date?
    @Published private(set) var stepsToday: Int?
    @Published private(set) var exerciseToday: Int?
    @Published private(set) var lastNight: SleepNight?                       // Phasen der letzten Nacht
    @Published private(set) var week: [(day: Date, seconds: TimeInterval)] = [] // 7 Nächte, älteste zuerst

    var available: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Eine Zeile für Dot (Chat, Tagestexte). Nil, wenn nichts da ist.
    var line: String? {
        Timing.healthLine(sleep: sleepLastNight, average: sleepAverage, bed: bedAt, woke: wokeAt,
                          steps: stepsToday, exercise: exerciseToday)
    }

    /// Einmal fragen. Health verrät nicht, ob du „Nein“ gesagt hast – dann kommen einfach keine Daten.
    func requestAccess() async -> Bool {
        guard available,
              let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis),
              let steps = HKObjectType.quantityType(forIdentifier: .stepCount),
              let exercise = HKObjectType.quantityType(forIdentifier: .appleExerciseTime) else { return false }
        do {
            try await store.requestAuthorization(toShare: [], read: [sleep, steps, exercise])
            return true
        } catch {
            return false
        }
    }

    /// `all` = Schlaf + Bewegung (für Dot), `steps` = nur Schritte (für Gewohnheiten mit Schrittziel).
    func refresh(all: Bool, steps: Bool) async {
        if all { await loadSleep() }
        if all || steps { stepsToday = await sum(.stepCount, unit: HKUnit.count()) }
        if all { exerciseToday = await sum(.appleExerciseTime, unit: HKUnit.minute()) }
    }

    /// Schlaf der letzten 7 Nächte; Uhr und Handy überlappen oft – zählt nur einmal.
    private func loadSleep() async {
        guard available, let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return }
        let cal = Calendar.current
        let now = Date()
        let today = cal.startOfDay(for: now)
        let start = cal.date(byAdding: .hour, value: -7 * 24 - 6, to: today) ?? today
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now)
        let asleep: Set<Int> = Set(HKCategoryValueSleepAnalysis.allAsleepValues.map { $0.rawValue })
        let health = store
        let samples: [HKCategorySample] = await withCheckedContinuation { (cont: CheckedContinuation<[HKCategorySample], Never>) in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit,
                                      sortDescriptors: nil) { _, results, _ in
                cont.resume(returning: (results as? [HKCategorySample]) ?? [])
            }
            health.execute(query)
        }
        let parts: [(start: Date, end: Date)] = samples
            .filter { asleep.contains($0.value) }
            .map { (start: $0.startDate, end: $0.endDate) }
        let nights = Timing.nightly(parts)
        let lastKey = cal.date(byAdding: .day, value: -1, to: today) ?? today
        let last = nights[lastKey] ?? 0
        sleepLastNight = last > 0 ? last : nil
        sleepAverage = Timing.average(nights)
        let lastParts = parts.filter { cal.startOfDay(for: $0.end.addingTimeInterval(-12 * 3600)) == lastKey }
        bedAt = lastParts.map(\.start).min()
        wokeAt = lastParts.map(\.end).max()

        // Phasen (inkl. Wachphasen) der letzten Nacht
        let staged: [SleepSegment] = samples.compactMap { sample in
            guard let stage = SleepStage(healthValue: sample.value),
                  cal.startOfDay(for: sample.endDate.addingTimeInterval(-12 * 3600)) == lastKey else { return nil }
            return SleepSegment(stage: stage, start: sample.startDate, end: sample.endDate)
        }
        lastNight = SleepNight.build(staged)

        // 7 Nächte für die Balken
        var list: [(day: Date, seconds: TimeInterval)] = []
        for offset in stride(from: 7, through: 1, by: -1) {
            let key = cal.date(byAdding: .day, value: -offset, to: today) ?? today
            list.append((day: key, seconds: nights[key] ?? 0))
        }
        week = list
    }

    /// Summe von heute (Schritte, Bewegungsminuten).
    private func sum(_ id: HKQuantityTypeIdentifier, unit: HKUnit) async -> Int? {
        guard available, let type = HKQuantityType.quantityType(forIdentifier: id) else { return nil }
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        let health = store
        return await withCheckedContinuation { (cont: CheckedContinuation<Int?, Never>) in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate,
                                          options: .cumulativeSum) { _, stats, _ in
                let value: Double? = stats?.sumQuantity()?.doubleValue(for: unit)
                cont.resume(returning: value.map { Int($0) })
            }
            health.execute(query)
        }
    }
}
