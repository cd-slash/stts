import AVFoundation
import CarPlay
import Combine
import Foundation
import STTSCore
import UIKit

/// Drives the CarPlay voice conversation: one voice note in, one spoken reply
/// out, with the CarPlay Voice Control template showing state.
///
/// CarPlay guidance for this category:
/// - launch straight into voice interaction;
/// - avoid text-heavy or image-heavy surfaces;
/// - no custom wake word;
/// - the audio session uses `.playAndRecord` with mixing disabled.
///
/// The session reuses the same recorder and conversation controller as the
/// phone UI rather than duplicating capture logic.
@MainActor
final class CarPlayVoiceSession {
    private weak var interfaceController: CPInterfaceController?
    private var template: CPVoiceControlTemplate?
    private var cancellables = Set<AnyCancellable>()

    /// Prompt strings are the only text CarPlay shows, so they stay short,
    /// factual, and state-only.
    private enum Prompt {
        static let ready = "Ready"
        static let listening = "Listening"
        static let working = "Working"
        static let failed = "Unavailable"
    }

    // MARK: Scene lifecycle

    func attach(interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
        configureAudioSession()
        let template = makeTemplate(prompt: Prompt.ready)
        self.template = template
        interfaceController.setRootTemplate(template, animated: false, completion: nil)
        observeConversation()
    }

    func detach() {
        cancellables = []
        interfaceController = nil
        template = nil
        appState?.voiceNotes.discard()
        appState?.conversation.stopPlayback()
    }

    // MARK: Controls

    func toggleVoiceNote() {
        guard let voiceNotes = appState?.voiceNotes else { return }
        if voiceNotes.capturePhase == .recording {
            update(prompt: Prompt.working)
            voiceNotes.stop()
            return
        }
        appState?.conversation.stopPlayback()
        voiceNotes.start()
        if voiceNotes.capturePhase == .recording {
            update(prompt: Prompt.listening)
        } else {
            update(prompt: Prompt.failed)
        }
    }

    func replay() {
        guard let conversation = appState?.conversation, conversation.canPlayReply else { return }
        Task { await conversation.playReply() }
    }

    func stop() {
        appState?.conversation.stopWork()
        appState?.voiceNotes.discard()
        update(prompt: Prompt.ready)
    }

    // MARK: State

    private var appState: AppState? {
        AppState.current
    }

    private func observeConversation() {
        guard let conversation = appState?.conversation else { return }
        // `phase` and `replyText` are the only conversation signals CarPlay
        // needs; both are published by the existing controller.
        conversation.$replyText
            .sink { [weak self] _ in
                Task { @MainActor in self?.update(prompt: Prompt.ready) }
            }
            .store(in: &cancellables)
        conversation.$phase
            .sink { [weak self] _ in
                Task { @MainActor in self?.refreshFromPhase() }
            }
            .store(in: &cancellables)
    }

    private func refreshFromPhase() {
        guard let phase = appState?.conversation.phase else { return }
        switch phase {
        case .transcribing, .submitting:
            update(prompt: Prompt.working)
        case .failed:
            update(prompt: Prompt.failed)
        case .awaitingInput:
            // Approvals and clarifications must not be answered while driving.
            update(prompt: Prompt.failed)
        case .idle:
            update(prompt: Prompt.ready)
        }
    }

    private func update(prompt: String) {
        guard let template else { return }
        template.activateVoiceControlState(withIdentifier: prompt)
    }

    // MARK: CarPlay framework

    /// A voice control state per prompt. `repeats` is false so the animation
    /// does not loop indefinitely and become a distraction.
    private func makeTemplate(prompt: String) -> CPVoiceControlTemplate {
        let states = [Prompt.ready, Prompt.listening, Prompt.working, Prompt.failed].map { value in
            CPVoiceControlState(
                identifier: value,
                titleVariants: [value],
                image: nil,
                repeats: false
            )
        }
        let template = CPVoiceControlTemplate(voiceControlStates: states)
        template.activateVoiceControlState(withIdentifier: prompt)
        return template
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            // CarPlay guidance: play and record, default mode, no mixing.
            try session.setCategory(.playAndRecord, mode: .default, options: [.allowBluetooth])
            try session.setActive(true)
        } catch {
            // A failed audio session surfaces as `failed` on the first attempt.
        }
    }
}
