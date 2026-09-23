import CarPlay
import Foundation
import STTSCore

/// CarPlay scene delegate for the "voice-based conversational app" category.
///
/// Scope is deliberately narrow: a voice note in, a spoken reply out. CarPlay
/// requires a voice-first surface, so this scene has no transcript browser and
/// no meeting controls.
///
/// The scene is declared in the app's `Info.plist` under
/// `CPTemplateApplicationSceneSessionRoleApplication`. Without Apple's granted
/// `com.apple.developer.carplay-voice-based-conversation` entitlement the scene
/// is simply never instantiated; nothing else in the app depends on it.
///
/// VERIFY against the CarPlay Developer Guide before the first device build:
/// the template construction in `CarPlayVoiceSession` uses API names that could
/// not be compiled or checked in this environment.
final class CarPlaySceneDelegate: NSObject, CPTemplateApplicationSceneDelegate {
    private let session = CarPlayVoiceSession()

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        Task { @MainActor in
            self.session.attach(interfaceController: interfaceController)
        }
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        Task { @MainActor in
            self.session.detach()
        }
    }
}
