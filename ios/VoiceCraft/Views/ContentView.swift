import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: RecorderModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var settings = false
    @State private var library = false
    private let mint = Color(red: 0.63, green: 0.96, blue: 0.78)
    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("VOICECRAFT").font(.caption.weight(.bold)).tracking(3).foregroundStyle(mint)
                        Text("Every word, captured.").font(.title2.weight(.semibold))
                    }
                    Spacer()
                    Button { settings = true } label: { Image(systemName: "slider.horizontal.3").font(.title3) }
                        .accessibilityLabel("Settings").disabled(model.busy)
                }
                Picker("Speech engine", selection: $model.engine) {
                    ForEach(SpeechEngine.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).disabled(model.busy)
                HStack(spacing: 7) {
                    Circle().fill(model.state == .recording ? mint : .gray).frame(width: 6, height: 6)
                    Text(model.status).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("ENGLISH").font(.caption2.weight(.bold)).tracking(1.4).foregroundStyle(.secondary)
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            if model.transcript.isEmpty {
                                Text(model.state == .recording ? "Listening…" : "A little space for\nyour next big thought.")
                                    .font(.system(size: 28, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
                                Text(model.state == .recording ? "Your words will appear here as you speak." : "Tap record and speak in English. Your audio and transcript stay together.")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            } else {
                                Text(model.transcript).font(.system(size: 23, weight: .regular, design: .rounded))
                                    .lineSpacing(8).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                            }
                            Color.clear.frame(height: 1).id("bottom")
                        }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                    }.background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 24))
                        .onChange(of: model.transcript) { _, _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
                }
                if model.state == .preparing {
                    ProgressView(value: model.progress).tint(mint)
                    Text("The first Whisper setup needs internet and may take a few minutes.").font(.caption).foregroundStyle(.secondary)
                }
                VStack(spacing: 15) {
                    TimelineView(.animation(minimumInterval: 0.08, paused: model.state != .recording)) { context in
                        HStack(alignment: .center, spacing: 4) {
                            ForEach(0..<35) { index in
                                let wave = abs(sin(context.date.timeIntervalSinceReferenceDate * 4 + Double(index) * 0.8))
                                Capsule().fill(mint.opacity(model.state == .recording ? 0.9 : 0.25))
                                    .frame(width: 4, height: 4 + CGFloat(wave) * CGFloat(model.level) * 42)
                            }
                        }.frame(height: 48)
                    }.accessibilityHidden(true)
                    Text(model.formattedTime).font(.system(.title2, design: .monospaced).weight(.medium))
                    Button {
                        Task { if model.state == .recording { await model.stop() } else { await model.start() } }
                    } label: {
                        HStack(spacing: 10) {
                            if model.state == .finishing || model.state == .preparing { ProgressView().tint(.black) }
                            else { Image(systemName: model.state == .recording ? "stop.fill" : "mic.fill") }
                            Text(model.state == .recording ? "Stop & Save" : model.state == .finishing ? "Saving…" : model.state == .preparing ? "Preparing…" : "Start Recording")
                                .fontWeight(.semibold)
                        }.frame(maxWidth: .infinity).padding(.vertical, 20)
                            .foregroundStyle(.black).background(mint, in: RoundedRectangle(cornerRadius: 20))
                    }.disabled(model.state == .preparing || model.state == .finishing || model.pendingSave)
                    if model.pendingSave { Button("Retry Save") { model.retrySave() }.tint(mint) }
                    Button { library = true } label: {
                        Label("Recordings · \(model.recordings.count)", systemImage: "waveform.path").font(.subheadline)
                    }.disabled(model.busy).padding(.bottom, 4)
                }
            }.padding(22).background(Color(red: 0.045, green: 0.065, blue: 0.065).ignoresSafeArea())
                .toolbar(.hidden, for: .navigationBar)
                .sheet(isPresented: $settings) { SettingsView() }
                .sheet(isPresented: $library) { RecordingsView() }
                .alert("VoiceCraft", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
                    Button("OK") { model.errorMessage = nil }
                } message: { Text(model.errorMessage ?? "") }
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active, model.state == .recording { Task { await model.stop() } }
                }
        }.tint(mint)
    }
}
