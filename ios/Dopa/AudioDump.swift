import SwiftUI
import Speech
import AVFoundation

/// Spracherkennung auf Deutsch: live mitgeschrieben (Apples Server-Erkennung) und gleichzeitig als
/// WAV aufgenommen – beim Stopp hört Gemini die Aufnahme nochmal genau (Feedback #30).
@MainActor
final class DumpRecorder: ObservableObject {
    @Published private(set) var transcript = ""
    @Published private(set) var recording = false
    @Published private(set) var seconds = 0
    @Published private(set) var error: String?
    @Published private(set) var limitReached = false

    static let maxSeconds = 180                 // passt sicher durch den Server (WAV, 16 kHz)
    var hints: [String] = []                    // Wörter, die vorkommen könnten (Aufgaben, Einkauf …)

    private var file: AVAudioFile?
    private var fileURL: URL?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "de-DE"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var timer: Timer?
    private var finished = ""           // Text aus früheren Aufnahme-Abschnitten

    func toggle() {
        if recording {
            stop()
        } else {
            Task { await start() }
        }
    }

    private func start() async {
        error = nil
        let speech = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        guard speech == .authorized else {
            error = "Spracherkennung ist nicht erlaubt (Einstellungen → Dopa)."
            return
        }
        let mic = await withCheckedContinuation { cont in
            AVAudioSession.sharedInstance().requestRecordPermission { cont.resume(returning: $0) }
        }
        guard mic else {
            error = "Mikrofon ist nicht erlaubt (Einstellungen → Dopa)."
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            error = "Spracherkennung ist gerade nicht verfügbar."
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            // Apples Server-Erkennung ist für Deutsch deutlich genauer als die auf dem Gerät
            request.requiresOnDeviceRecognition = false
            request.taskHint = .dictation
            request.addsPunctuation = true
            request.contextualStrings = Array(hints.prefix(100))
            self.request = request

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            // zusätzlich als WAV (16 kHz, mono) für Gemini mitschreiben
            let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("dopa-dump-\(UUID().uuidString).wav")
            let writer = target.flatMap { try? AVAudioFile(forWriting: url, settings: $0.settings,
                                                           commonFormat: .pcmFormatInt16, interleaved: true) }
            let converter = target.flatMap { AVAudioConverter(from: format, to: $0) }
            file = writer
            fileURL = writer == nil ? nil : url
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
                guard let writer, let converter, let target else { return }
                let capacity = AVAudioFrameCount(Double(buffer.frameLength) * target.sampleRate / format.sampleRate) + 32
                guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
                var fed = false
                var conversionError: NSError?
                converter.convert(to: out, error: &conversionError) { _, status in
                    if fed {
                        status.pointee = .noDataNow
                        return nil
                    }
                    fed = true
                    status.pointee = .haveData
                    return buffer
                }
                if conversionError == nil && out.frameLength > 0 { try? writer.write(from: out) }
            }
            engine.prepare()
            try engine.start()

            finished = transcript
            task = recognizer.recognitionTask(with: request) { [weak self] result, err in
                Task { @MainActor in
                    guard let self else { return }
                    if let result {
                        let spoken = result.bestTranscription.formattedString
                        self.transcript = self.finished.isEmpty ? spoken : self.finished + " " + spoken
                    }
                    if err != nil && self.recording { self.stop() }
                }
            }
            recording = true
            limitReached = false
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.seconds += 1
                    if self.seconds >= Self.maxSeconds && self.recording { self.limitReached = true }
                }
            }
        } catch {
            self.error = "Aufnahme ließ sich nicht starten."
            stop()
        }
    }

    func stop() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.finish()
        request = nil
        task = nil
        timer?.invalidate()
        timer = nil
        recording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func edit(_ text: String) { transcript = text }

    /// Die Aufnahme seit dem letzten Start als WAV (Datei wird dabei geschlossen).
    func takeAudio() -> Data? {
        file = nil                                  // schließen = WAV-Kopf fertig schreiben
        guard let url = fileURL else { return nil }
        fileURL = nil
        defer { try? FileManager.default.removeItem(at: url) }
        guard let data = try? Data(contentsOf: url), data.count > 8_000, data.count < 7_000_000 else { return nil }
        return data
    }

    /// Geminis genauere Abschrift ersetzt das, was Apple live in diesem Abschnitt geschrieben hat.
    func applyBetterTranscript(_ text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        transcript = finished.isEmpty ? clean : finished + " " + clean
    }
}

/// „Audio-Dump“: erzählen statt sortieren → Plan für eine Aufgabe, den Tag oder die Woche.
struct AudioDumpSheet: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @StateObject private var recorder = DumpRecorder()
    @State private var dump: Server.Dump?
    @State private var picked: Set<String> = []
    @State private var busy = false
    @State private var listening = false             // Gemini hört die Aufnahme nochmal
    @State private var error: String?

    private var time: String { String(format: "%02d:%02d", recorder.seconds / 60, recorder.seconds % 60) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Audio-Dump").font(.system(size: 13, weight: .medium)).foregroundStyle(DS.muted).padding(.bottom, 7)
                    Text("Erzähl einfach drauflos.").font(.system(size: 24, weight: .bold)).tracking(-0.7).foregroundStyle(DS.ink)
                    Text("Dopa sortiert selbst: Aufgaben, Termine, Einkauf, Merken. „Plane meinen Morgen …“ macht einen Zeitplan mit Erinnerungen.")
                        .font(.system(size: 13)).foregroundStyle(DS.muted).padding(.top, 8).padding(.bottom, 16)

                    recorderBox.padding(.top, 12)

                    if true {
                        TextField("", text: Binding(get: { recorder.transcript }, set: { recorder.edit($0) }),
                                  prompt: Text("Hier erscheint, was du sagst …").foregroundColor(Color(hex: 0x68606D)),
                                  axis: .vertical)
                            .lineLimit(3...10)
                            .font(.system(size: 14))
                            .foregroundStyle(DS.ink)
                            .padding(14)
                            .background(Color(hex: 0x0F0D11), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(Color(hex: 0x39323E)))
                            .padding(.top, 12)
                    }

                    if listening {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("\(store.dotName) hört nochmal genau hin …").font(.system(size: 13)).foregroundStyle(DS.muted)
                        }
                        .padding(.top, 10)
                    }

                    if let message = recorder.error ?? error {
                        Text(message).font(.system(size: 12)).foregroundStyle(DS.muted).padding(.top, 10)
                    }

                    Button {
                        makePlan()
                    } label: {
                        HStack(spacing: 8) {
                            if busy { ProgressView().tint(.white) }
                            Text(dump == nil ? "Einsortieren" : "Nochmal")
                        }
                    }
                    .buttonStyle(SolidButtonStyle())
                    .disabled(busy || (!recorder.recording && recorder.transcript.trimmingCharacters(in: .whitespaces).count < 5))
                    .padding(.top, 14)

                    if let dump {
                        DumpResultView(dump: dump, picked: $picked)
                        Button("\(picked.count) übernehmen") {
                            store.applyDump(dump, picked: picked)
                            dismiss()
                        }
                        .buttonStyle(SolidButtonStyle())
                        .disabled(picked.isEmpty)
                        .padding(.top, 16)
                    }
                }
                .padding(.horizontal, 19)
                .padding(.top, 20)
                .padding(.bottom, 30)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(DS.raised.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { recorder.stop(); dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Übernehmen") {
                        if let dump { store.applyDump(dump, picked: picked) }
                        dismiss()
                    }
                    .disabled(picked.isEmpty)
                }
            }
        }
        .onAppear {
            // Wörter aus deinem Alltag helfen beim Verstehen (Namen, Läden, Aufgaben)
            recorder.hints = store.openTasks.prefix(40).map(\.title)
                + store.shopOpen.map(\.name) + store.data.habits.map(\.title)
                + store.data.shopPlaces.map(\.name)
        }
        .onChange(of: recorder.limitReached) { reached in
            if reached { makePlan() }
        }
        .onDisappear { recorder.stop() }
    }

    private var recorderBox: some View {
        VStack(spacing: 0) {
            Waveform(active: recorder.recording).padding(.bottom, 15)
            Text(time).font(.system(size: 26, weight: .semibold)).monospacedDigit().tracking(-0.5).foregroundStyle(DS.ink)
            Text(recorder.recording ? "Tippen zum Aufhören – dann macht Dopa den Plan (max. 3 Min)" : recorder.transcript.isEmpty ? "Tippen und losreden" : "Nochmal tippen zum Weiterreden")
                .font(.system(size: 12)).foregroundStyle(DS.muted).padding(.top, 4)
            Button {
                if recorder.recording {
                    makePlan()          // Stopp = gleich planen
                } else {
                    recorder.toggle()
                }
            } label: {
                Group {
                    if recorder.recording {
                        RoundedRectangle(cornerRadius: 3).fill(.white).frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "mic.fill").font(.system(size: 22)).foregroundStyle(.white)
                    }
                }
                .frame(width: 56, height: 56)
                .background(recorder.recording ? Color(hex: 0xD15464) : store.theme.accent, in: Circle())
            }
            .buttonStyle(.plain)
            .padding(.top, 18)
            .accessibilityLabel(recorder.recording ? "Aufnahme beenden" : "Aufnahme starten")
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .background(Color(hex: 0x111216), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(DS.line))
    }

    private func makePlan() {
        busy = true
        error = nil
        let wasRecording = recorder.recording
        if wasRecording { recorder.stop() }
        Task {
            // Nach dem Stopp kommt das letzte Stück Text noch kurz nach
            if wasRecording { try? await Task.sleep(nanoseconds: 800_000_000) }
            // Gemini hört die Aufnahme selbst – viel genauer als das Live-Diktat
            if wasRecording, Server.shared.isConnected, Server.shared.aiAvailable, let wav = recorder.takeAudio() {
                listening = true
                if let better = try? await Server.shared.transcribe(wav: wav, hints: recorder.hints) {
                    recorder.applyBetterTranscript(better)
                }
                listening = false
            }
            guard recorder.transcript.trimmingCharacters(in: .whitespaces).count >= 5 else {
                error = "Ich hab nichts verstanden. Nochmal sprechen oder oben reinschreiben."
                busy = false
                return
            }
            do {
                let result = try await Server.shared.dump(recorder.transcript)
                dump = result
                picked = DumpKey.all(result)
            } catch {
                self.error = error.localizedDescription
            }
            busy = false
        }
    }
}

/// Balken, die beim Aufnehmen atmen.
private struct Waveform: View {
    let active: Bool
    @State private var phase = false
    @ObservedObject private var store = Store.shared

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<19, id: \.self) { i in
                let base: CGFloat = i % 5 == 0 ? 30 : i % 4 == 0 ? 22 : i % 3 == 0 ? 13 : 5
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(active ? DS.purpleMuted : Color(hex: 0x4D4752))
                    .frame(width: 3, height: active && phase ? max(4, base * 0.35) : base)
                    .animation(active ? .easeInOut(duration: 0.45).repeatForever().delay(Double(i % 3) * 0.15) : .default,
                               value: phase)
            }
        }
        .frame(height: 35)
        .onChange(of: active) { on in phase = on }
    }
}
