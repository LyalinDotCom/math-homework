import SwiftUI
import PhotosUI

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var showsSettings = false
    @State private var photoSelection: [PhotosPickerItem] = []

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            List {
                if !model.hasAPIKey {
                    Section {
                        Button {
                            showsSettings = true
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Add your Gemini API key")
                                        .font(.headline)
                                    Text("Required only for scanning new pages. History works without it.")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "key.fill")
                                    .foregroundStyle(.tint)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                if model.history.isEmpty {
                    Section {
                        emptyStateSteps
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                } else {
                    Section("Recent") {
                        ForEach(model.history.prefix(5)) { session in
                            NavigationLink(value: session.id) {
                                SessionRow(session: session)
                            }
                        }
                        if model.history.count > 5 {
                            NavigationLink("All Sessions") {
                                HistoryView()
                            }
                        }
                    }
                }

                Section {
                } footer: {
                    Text("Saved on this iPhone · Graded locally · OCR by Gemini 3.5 Flash")
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Math Homework")
            .navigationDestination(for: String.self) { sessionId in
                SessionDetailView(sessionId: sessionId)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        HistoryView()
                    } label: {
                        Label("History", systemImage: "clock.arrow.circlepath")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showsSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                scanActions
            }
        }
        .task { model.refreshHistory() }
        .sheet(isPresented: $showsSettings) {
            SettingsView()
        }
        .fullScreenCover(item: $model.activeSession) { _ in
            ActiveSessionView()
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { model.lastError != nil },
                set: { if !$0 { model.lastError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.lastError ?? "")
        }
    }

    private var emptyStateSteps: some View {
        VStack(spacing: 28) {
            Image(systemName: "checkmark.rectangle.stack")
                .font(.system(size: 56, weight: .medium))
                .foregroundStyle(.tint)
                .padding(.top, 24)
            VStack(spacing: 20) {
                homeStep(
                    icon: "camera.viewfinder",
                    title: "Scan each page",
                    detail: "Hold your iPhone over the worksheet — pages snap automatically."
                )
                homeStep(
                    icon: "text.viewfinder",
                    title: "The work is read twice",
                    detail: "Two independent OCR passes transcribe the problems and handwriting."
                )
                homeStep(
                    icon: "checkmark.seal",
                    title: "Every answer checked",
                    detail: "Arithmetic is graded on this iPhone, never by the model."
                )
            }
            .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity)
    }

    private func homeStep(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var scanActions: some View {
        VStack(spacing: 10) {
            Button {
                Haptics.tap()
                model.startSession()
            } label: {
                Label("Scan Homework", systemImage: "doc.viewfinder")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.hasAPIKey)

            PhotosPicker(
                selection: $photoSelection,
                maxSelectionCount: 20,
                matching: .images
            ) {
                Label("Import from Photos", systemImage: "photo.on.rectangle")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!model.hasAPIKey)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(.bar)
        .onChange(of: photoSelection) { _, items in
            guard !items.isEmpty else { return }
            Task {
                let images = await PhotoImport.loadImages(from: items)
                photoSelection = []
                guard !images.isEmpty else { return }
                model.startSession()
                model.enqueue(images: images)
            }
        }
    }
}

struct SessionRow: View {
    let session: Session

    var body: some View {
        let totals = session.pages.reduce(into: (correct: 0, total: 0)) { sums, page in
            sums.correct += page.review.problems.filter(\.isCorrect).count
            sums.total += page.review.problems.count
        }
        let startedAt = Timestamps.parseISO(session.metadata.startedAt) ?? Date()
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                Text(startedAt, format: .dateTime.day())
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                Text(startedAt, format: .dateTime.month(.abbreviated))
                    .font(.caption2.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 44, height: 44)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(startedAt, format: .dateTime.month(.wide).day().year())
                    .font(.body.weight(.medium))
                Text(
                    "\(startedAt, format: .dateTime.hour().minute()) · \(session.pages.count) \(session.pages.count == 1 ? "page" : "pages")"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(
                    totals.total == 0
                        ? "—"
                        : "\(Int((Double(totals.correct) / Double(totals.total) * 100).rounded()))%"
                )
                .font(.body.weight(.semibold))
                .monospacedDigit()
                Text("\(totals.correct) of \(totals.total)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 2)
    }
}

enum PhotoImport {
    static func loadImages(from items: [PhotosPickerItem]) async -> [UIImage] {
        var images: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                images.append(image)
            }
        }
        return images
    }
}
