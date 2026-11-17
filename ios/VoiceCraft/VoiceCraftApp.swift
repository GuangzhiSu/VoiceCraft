import SwiftUI

@main
struct VoiceCraftApp: App {
    @StateObject private var recorder = RecorderModel()
    var body: some Scene {
        WindowGroup { ContentView().environmentObject(recorder).preferredColorScheme(.dark) }
    }
}
