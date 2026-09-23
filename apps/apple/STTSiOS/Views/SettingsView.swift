import SwiftUI
import STTSCore

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            Section {
                TextField("Server URL", text: $appState.serverURLString)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Worker server URL")
                    .listRowBackground(Color.sttsSurfaceRaised)
                    .listRowSeparatorTint(Color.sttsHairline)
                if appState.usesInsecureTransport {
                    Text("Insecure HTTP")
                        .font(.sttsCaption)
                        .foregroundStyle(Color.sttsAlert)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            } header: {
                sectionHeader("Server")
            }
            Section {
                NavigationLink {
                    CredentialSetupView()
                } label: {
                    HStack {
                        Text("Access credentials")
                            .font(.sttsBody)
                            .foregroundStyle(Color.sttsInk)
                        Spacer()
                        Text(appState.credentialConfigured ? "Saved" : "None")
                            .font(.sttsCaption)
                            .foregroundStyle(Color.sttsInkMuted)
                    }
                }
                .accessibilityLabel(
                    "Access credentials, \(appState.credentialConfigured ? "saved" : "none")"
                )
                .listRowBackground(Color.sttsSurface)
                .listRowSeparatorTint(Color.sttsHairline)
            } header: {
                sectionHeader("Access")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.sttsVoid.ignoresSafeArea())
        .navigationTitle("Settings")
    }
}

struct CredentialSetupView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var clientID = ""
    @State private var secret = ""
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                TextField("Client ID", text: $clientID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Access service token client ID")
                    .listRowBackground(Color.sttsSurfaceRaised)
                    .listRowSeparatorTint(Color.sttsHairline)
                SecureField("Secret", text: $secret)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Access service token secret")
                    .listRowBackground(Color.sttsSurfaceRaised)
                    .listRowSeparator(.hidden)
            } header: {
                sectionHeader("Cloudflare Access")
            }
            Section {
                Button("Save") {
                    save()
                }
                .disabled(clientID.isEmpty || secret.isEmpty)
                .foregroundStyle(Color.sttsInk)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                if appState.credentialConfigured {
                    Button("Remove", role: .destructive) {
                        appState.removeCredential()
                        dismiss()
                    }
                    .foregroundStyle(Color.sttsAlert)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.sttsCaption)
                        .foregroundStyle(Color.sttsAlert)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.sttsVoid.ignoresSafeArea())
        .navigationTitle("Access credentials")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func save() {
        let trimmedID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSecret = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty, !trimmedSecret.isEmpty else {
            errorMessage = "Client ID and secret required"
            return
        }
        do {
            try appState.storeCredential(Credential(clientID: trimmedID, clientSecret: trimmedSecret))
            dismiss()
        } catch {
            errorMessage = "Save failed"
        }
    }
}

private func sectionHeader(_ title: String) -> some View {
    Text(title)
        .font(.sttsCaption)
        .foregroundStyle(Color.sttsInkMuted)
        .textCase(nil)
}
