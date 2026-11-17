import SwiftUI
import AVFoundation

struct RecordingsView: View {
    @EnvironmentObject private var model: RecorderModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Group {
                if model.recordings.isEmpty {
                    ContentUnavailableView("Your words belong here", systemImage: "waveform", description: Text("Your saved recordings will appear here."))
                } else {
                    List {
                        ForEach(model.recordings) { recording in
                            NavigationLink {
                                RecordingDetailView(recording: recording)
                            } label: {
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(recording.title).font(.headline).lineLimit(2)
                                    Text("\(recording.date.formatted(date: .abbreviated, time: .shortened)) · \(Int(recording.duration))s · \(recording.engine.rawValue)")
                                        .font(.caption).foregroundStyle(.secondary)
                                    if recording.incomplete { Label("Transcript incomplete · audio saved", systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange) }
                                }.padding(.vertical, 6)
                            }.swipeActions { Button("Delete", role: .destructive) { model.delete(recording) } }
                        }
                    }
                }
            }.navigationTitle("Recordings").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

struct RecordingDetailView: View {
    let recording: Recording
    @EnvironmentObject private var model: RecorderModel
    @State private var player: AVAudioPlayer?
    @State private var error: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text(recording.date.formatted(date: .long, time: .shortened)).font(.subheadline).foregroundStyle(.secondary)
                HStack {
                    Button { play() } label: { Label("Play audio", systemImage: "play.fill") }.buttonStyle(.borderedProminent)
                    Button { player?.stop(); player = nil } label: { Image(systemName: "stop.fill") }.buttonStyle(.bordered).accessibilityLabel("Stop playback")
                    Spacer()
                    ShareLink(item: model.store.audioURL(recording.audioFilename)) { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("Share audio")
                }
                if recording.incomplete { Text("Transcription was interrupted. The captured audio is available above.").foregroundStyle(.orange) }
                Text(recording.transcript.isEmpty ? "No speech was transcribed." : recording.transcript)
                    .font(.title3).lineSpacing(7).textSelection(.enabled)
                ShareLink(item: recording.transcript) { Label("Share transcript", systemImage: "doc.text") }.buttonStyle(.bordered)
            }.padding(24)
        }.navigationTitle("Recording").navigationBarTitleDisplayMode(.inline)
            .onDisappear { player?.stop(); player = nil; try? AVAudioSession.sharedInstance().setActive(false) }
            .alert("Playback", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
    }
    private func play() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            player = try AVAudioPlayer(contentsOf: model.store.audioURL(recording.audioFilename))
            guard player?.play() == true else { throw VoiceCraftError.message("Could not play this recording.") }
        } catch { self.error = error.localizedDescription }
    }
}
