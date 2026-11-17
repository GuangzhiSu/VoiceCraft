import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: RecorderModel
    @Environment(\.dismiss) private var dismiss
    @State private var token = KeychainStore.read()
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("Recognition") {
                    LabeledContent("Language", value: "English (US)")
                    Text("Apple Speech updates while you speak and uses on-device recognition when supported. Otherwise Apple may process audio online.")
                    Text("Whisper tiny.en runs on your iPhone after a one-time model download. Text updates roughly every 4 seconds plus processing time. Keep the app open while recording.")
                }
                Section("Whisper processing") {
                    Toggle("Use my Whisper server", isOn: $model.useRemoteWhisper)
                    if model.useRemoteWhisper {
                        TextField("https://whisper.example.com", text: $model.serverURL)
                            .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        SecureField("Server access token", text: $token).textInputAutocapitalization(.never)
                        Text("Your audio chunks are sent to this server. Only use a server you trust. The token is saved in the iOS Keychain.")
                    } else { Text("On-device · no API key or backend required").foregroundStyle(.secondary) }
                }
                Section("Your recordings") {
                    Text("Audio and transcripts are saved in this app's Documents folder. Deleting a recording removes both. Uninstalling the app removes its local data. Device backups may include recordings.")
                    Text("Transcription does not identify speakers or label different voices. Check the transcript before relying on it.")
                }
            }.navigationTitle("Settings").toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        do {
                            if model.useRemoteWhisper { _ = try RemoteWhisperService.validate(model.serverURL.trimmingCharacters(in: .whitespacesAndNewlines)) }
                            try KeychainStore.save(token); dismiss()
                        } catch { self.error = error.localizedDescription }
                    }
                }
            }.alert("Settings", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
        }
    }
}
