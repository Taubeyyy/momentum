import SwiftUI

// Feedback #14: Morgen- und Abendroutine besser erreichbar und auch früher oder später machbar.

/// „Heute andere Zeit“: früher, später oder ganz ohne Uhr – nur für heute, der Plan bleibt.
struct TodayTimeSheet: View {
    let title: String
    let isOverride: Bool
    let onSet: (Int?) -> Void           // Minuten; -1 = ohne Uhr; nil = zurück zum Plan
    @State var minutes: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    DatePicker(title,
                               selection: Binding(get: { ClockTime.date(minutes) },
                                                  set: { minutes = ClockTime.minutes(of: $0) }),
                               displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                    Button("Für heute übernehmen") {
                        onSet(minutes)
                        dismiss()
                    }
                } footer: {
                    Text("Gilt nur heute. Morgen ist wieder dein normaler Plan dran.")
                }
                .dopaRow()

                Section {
                    Button("Heute ohne Uhr – nur abhaken") {
                        onSet(-1)
                        dismiss()
                    }
                    if isOverride {
                        Button("Zurück zum normalen Plan") {
                            onSet(nil)
                            dismiss()
                        }
                    }
                }
                .dopaRow()
            }
            .dopaBackground()
            .navigationTitle("Heute andere Zeit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
