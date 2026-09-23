import SwiftUI

struct RootView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView {
            VoiceNoteView()
                .tabItem { Label("Voice", systemImage: "mic") }
            MeetingsView()
                .tabItem { Label("Meetings", systemImage: "list.bullet") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
