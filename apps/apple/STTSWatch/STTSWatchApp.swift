import SwiftUI

@main
struct STTSWatchApp: App {
    @StateObject private var link = PhoneLink()
    @StateObject private var recorder = WatchVoiceNoteRecorder()

    var body: some Scene {
        WindowGroup {
            TabView {
                WatchVoiceNoteView()
                WatchMeetingControlView()
            }
            .background(Color.sttsVoid.ignoresSafeArea())
            .environmentObject(link)
            .environmentObject(recorder)
            .onAppear {
                link.activate()
            }
        }
    }
}
