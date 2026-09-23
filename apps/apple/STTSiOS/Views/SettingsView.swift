import SwiftUI
import STTSCore

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            Section("Server") {
                TextField("Server URL", text: $appState.serverURLString)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Worker server URL")
                if appState.usesInsecureTransport {
                    Text("Insecure HTTP")
                        .foregroundStyle(.red)
                }
            }
            Section("Access") {
                NavigationLink {
                    CredentialSetupView()
                } label: {
                    HStack {
                        Text("Access credentials")
                        Spacer()
                        Text(appState.credentialConfigured ? "Saved" : "None")
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityLabel(
                    "Access credentials, \(appState.credentialConfigured ? "saved" : "none")"
                )
            }
        }
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
            Section("Cloudflare Access") {
                TextField("Client ID", text: $clientID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Access service token client ID")
                SecureField("Secret", text: $secret)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Access service token secret")
            }
            Section {
                Button("Save") {
                    save()
                }
                .disabled(clientID.isEmpty || secret.isEmpty)
                if appState.credentialConfigured {
                    Button("Remove", role: .destructive) {
                        appState.removeCredential()
                        dismiss()
                    }
                }
            }
            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Access credentials")
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
