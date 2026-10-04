import ActivityKit
import SwiftUI
import WidgetKit

/// Sperrbildschirm und Mitteilung: Dot, Aufgabe, nächster Schritt, Balken und Countdown.
/// Zählt von selbst runter – die App muss dafür nicht laufen.
struct TimerLiveActivity: Widget {
    private static let accent = Color(red: 0.65, green: 0.55, blue: 0.98)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DopaTimerAttributes.self) { context in
            let _ = LiveProbe.mark(LiveProbe.renderedKey, "Sperrbildschirm gezeichnet")
            LockScreenTimer(title: context.attributes.title, state: context.state)
                .activityBackgroundTint(Color(red: 0.07, green: 0.05, blue: 0.10))
                .activitySystemActionForegroundColor(Self.accent)
                .widgetURL(URL(string: "dopa://jetzt"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "timer").font(.title3).foregroundStyle(Self.accent)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    countdown(context.state)
                        .font(.title3.weight(.bold))
                        .frame(width: 80, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.title).font(.headline).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        if !context.state.step.isEmpty {
                            Text(context.state.step).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        }
                        progress(context.state)
                    }
                }
            } compactLeading: {
                Image(systemName: "timer").foregroundStyle(Self.accent)
            } compactTrailing: {
                countdown(context.state).frame(width: 46)
            } minimal: {
                Image(systemName: "timer").foregroundStyle(Self.accent)
            }
            .widgetURL(URL(string: "dopa://jetzt"))
            .keylineTint(Self.accent)
        }
    }

    private func countdown(_ state: DopaTimerAttributes.ContentState) -> some View {
        Text(timerInterval: state.start...max(state.start, state.end), countsDown: true)
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
    }

    private func progress(_ state: DopaTimerAttributes.ContentState) -> some View {
        ProgressView(timerInterval: state.start...max(state.start, state.end), countsDown: false) {
            EmptyView()
        } currentValueLabel: {
            EmptyView()
        }
        .tint(Self.accent)
    }
}

private struct LockScreenTimer: View {
    let title: String
    let state: DopaTimerAttributes.ContentState

    private let accent = Color(red: 0.65, green: 0.55, blue: 0.98)

    var body: some View {
        let range = state.start...max(state.start, state.end)
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(accent.opacity(0.22))
                Circle().stroke(accent.opacity(0.6), lineWidth: 1.5).padding(5)
                Circle().fill(accent).frame(width: 12, height: 12)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).foregroundStyle(.white).lineLimit(1)
                if !state.step.isEmpty {
                    Text(state.step).font(.subheadline).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                }
                ProgressView(timerInterval: range, countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .tint(accent)
            }

            Text(timerInterval: range, countsDown: true)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .multilineTextAlignment(.trailing)
                .frame(width: 100, alignment: .trailing)
        }
        .padding(16)
    }
}
