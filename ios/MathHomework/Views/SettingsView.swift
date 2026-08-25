import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var keyDraft = ""
    @State private var justSaved = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if model.hasAPIKey {
                        Label {
                            Text("Gemini is configured")
                        } icon: {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                    TextField(
                        model.hasAPIKey ? "Replace API key" : "Paste your API key",
                        text: $keyDraft
                    )
                    .font(.callout.monospaced())
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .textContentType(.password)
                    Button(justSaved ? "Saved" : "Save Key") {
                        model.saveAPIKey(keyDraft)
                        keyDraft = ""
                        justSaved = true
                        Haptics.success()
                        Task {
                            try? await Task.sleep(nanoseconds: 1_600_000_000)
                            justSaved = false
                        }
                    }
                    .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                } header: {
                    Text("Gemini API key")
                } footer: {
                    Text("Required only for scanning new pages — history works without it. The key is kept in the iOS Keychain. Get a free key at aistudio.google.com/apikey.")
                }

                Section {
                    Button {
                        openInFiles()
                    } label: {
                        Label("Open Archive in Files", systemImage: "folder")
                    }
                } header: {
                    Text("Your data")
                } footer: {
                    Text("Each session is a folder of ordinary JPEG and JSON files in the Files app under On My iPhone › Math Homework. Copy or back them up without special software.")
                }

                Section {
                    LabeledContent("OCR model", value: WorksheetOCR.geminiModel)
                    LabeledContent("Grading", value: "On this iPhone")
                } header: {
                    Text("About")
                } footer: {
                    Text("Pages are sent to Google's Gemini API for transcription with interaction storage disabled. Gemini never decides whether the math is right — answers are computed and compared locally.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .bold()
                }
            }
        }
    }

    private func openInFiles() {
        var components = URLComponents()
        components.scheme = "shareddocuments"
        components.path = model.repository.root.path
        guard let url = components.url else { return }
        UIApplication.shared.open(url)
    }
}
