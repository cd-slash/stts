import SwiftUI

struct RootView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView {
            NavigationStack {
                VoiceNoteView()
            }
            .tabItem { Label("Voice", systemImage: "mic") }
            NavigationStack {
                MeetingsView()
            }
            .tabItem { Label("Meetings", systemImage: "list.bullet") }
            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(Color.sttsInk)
        .preferredColorScheme(.dark)
        .toolbarBackground(Color.sttsVoid, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .task {
            await appState.recoverAfterLaunch()
        }
    }
}
