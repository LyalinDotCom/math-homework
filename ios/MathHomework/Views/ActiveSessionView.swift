import SwiftUI
import PhotosUI

/// The scanning workspace: scan or import pages, watch them move through OCR,
/// and dive into each page's review — all one-handed from the bottom bar.
struct ActiveSessionView: View {
    @Environment(AppModel.self) private var model
    @State private var showsScanner = false
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var autoOpenedScanner = false
    @State private var retakingItemId: String?

    private var session: Session? { model.activeSession }

    var body: some View {
        NavigationStack {
            Group {
                if let session {
                    workspaceList(session)
                } else {
                    // Session ended from elsewhere; the cover is dismissing.
                    Color(.systemGroupedBackground).ignoresSafeArea()
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        finish()
                    } label: {
                        Text("Done").bold()
                    }
                    .disabled(model.importingCount > 0 || !photoSelection.isEmpty)
                }
            }
            .safeAreaInset(edge: .bottom) {
                captureBar
            }
            .navigationDestination(for: String.self) { pageId in
                if let session = model.activeSession,
                   let page = session.pages.first(where: { $0.id == pageId }) {
                    ReviewView(sessionId: session.id, page: page)
                        .navigationTitle(reviewTitle(for: page))
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
        .interactiveDismissDisabled()
        .fullScreenCover(isPresented: $showsScanner) {
            DocumentScannerView { images in
                showsScanner = false
                Haptics.tap()
                model.enqueue(images: images, replacing: retakingItemId)
                retakingItemId = nil
            } onCancel: {
                showsScanner = false
                retakingItemId = nil
            } onError: { message in
                showsScanner = false
                retakingItemId = nil
                model.lastError = message
            }
            .ignoresSafeArea()
        }
        .onAppear {
            guard !autoOpenedScanner else { return }
            autoOpenedScanner = true
            if let session, session.pages.isEmpty, model.currentQueue.isEmpty,
               DocumentScannerView.isSupported {
                showsScanner = true
            }
        }
        .alert("Could not complete the scan", isPresented: Binding(
            get: { model.lastError != nil },
            set: { if !$0 { model.lastError = nil } }
        )) {
            Button("OK", role: .cancel) { model.lastError = nil }
        } message: {
            Text(model.lastError ?? "")
        }
    }

    private var title: String {
        let count = session?.pages.count ?? 0
        return count == 0 ? "Scan Worksheet" : "\(count) \(count == 1 ? "Page" : "Pages")"
    }

    private func reviewTitle(for page: SessionPage) -> String {
        page.review.worksheetTitle.isEmpty
            ? "Page \(page.metadata.number)"
            : page.review.worksheetTitle
    }

    private func finish() {
        model.endSession()
    }

    @ViewBuilder
    private func workspaceList(_ session: Session) -> some View {
        if session.pages.isEmpty && model.currentQueue.isEmpty && model.importingCount == 0 {
            ContentUnavailableView {
                Label("Scan the first page", systemImage: "doc.viewfinder")
            } description: {
                Text(
                    DocumentScannerView.isSupported
                        ? "Hold your iPhone over the worksheet. Up to three pages are checked at once, with two independent readings per page."
                        : "This device has no camera scanner — add worksheet photos from your library instead."
                )
            }
        } else {
            List {
                if model.importingCount > 0 {
                    Label("Saving \(model.importingCount) captured pages…", systemImage: "square.and.arrow.down")
                }
                if !model.isConnected {
                    Label("Offline — scans are saved and resume when connected.", systemImage: "wifi.slash")
                }
                if !session.pages.isEmpty {
                    Section("Checked pages") {
                        ForEach(session.pages) { page in
                            NavigationLink(value: page.id) {
                                PageRow(page: page)
                            }
                        }
                    }
                }
                if !model.currentQueue.isEmpty {
                    Section {
                        ForEach(model.currentQueue) { item in
                            ScanQueueRow(item: item) { id in
                                retakingItemId = id
                                showsScanner = true
                            }
                        }
                        if model.currentQueue.contains(where: { if case .failed = $0.status { return true }; return false }) {
                            Button("Retry All Failed Pages") { model.retryFailed() }
                        }
                    } header: {
                        Text("Reading")
                    } footer: {
                        Text("Scans and completed readings are saved. You can tap Done or switch apps; unfinished work resumes when you return.")
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private var captureBar: some View {
        VStack(spacing: 10) {
            Button {
                Haptics.tap()
                showsScanner = true
            } label: {
                Label("Scan Pages", systemImage: "doc.viewfinder")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!DocumentScannerView.isSupported)

            PhotosPicker(
                selection: $photoSelection,
                maxSelectionCount: 20,
                matching: .images
            ) {
                Label("Add from Photos", systemImage: "photo.on.rectangle")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
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
                model.enqueue(images: images)
            }
        }
    }
}

struct PageRow: View {
    let page: SessionPage
    @State private var thumbnail: UIImage?

    var body: some View {
        let correct = page.review.problems.filter(\.isCorrect).count
        let total = page.review.problems.count
        HStack(spacing: 12) {
            PageThumbnail(image: thumbnail)
            VStack(alignment: .leading, spacing: 2) {
                Text(
                    page.review.worksheetTitle.isEmpty
                        ? "Page \(page.metadata.number)"
                        : page.review.worksheetTitle
                )
                .font(.body.weight(.medium))
                .lineLimit(2)
                Text("Page \(page.metadata.number) · \(correct) of \(total) correct")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
            if total > 0 {
                ScoreBadge(correct: correct, total: total)
            }
        }
        .task(id: page.id) {
            let url = page.imageURL
            thumbnail = await Task.detached(priority: .utility) {
                Thumbnailer.thumbnail(from: url, maxPixel: 160)
            }.value
        }
    }
}

private struct ScanQueueRow: View {
    @Environment(AppModel.self) private var model
    let item: ScanItem
    var retake: (String) -> Void
    @State private var thumbnail: UIImage?
    @State private var showsScan = false

    var body: some View {
        HStack(spacing: 12) {
            Button { showsScan = true } label: { PageThumbnail(image: thumbnail) }
                .buttonStyle(.borderless)
                .accessibilityLabel("View saved scan for page \(item.page.number)")
            switch item.status {
            case .waiting:
                Text(model.isConnected ? "Saved · Waiting…" : "Saved · Waiting for connection")
                    .foregroundStyle(.secondary)
            case .processing:
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reading page \(item.page.number)")
                        .font(.body.weight(.medium))
                    Text(item.completedReadings == 1 ? "One reading saved · finishing the double check…" : "Two independent readings in parallel…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                ProgressView()
            case .failed(let message):
                VStack(alignment: .leading, spacing: 4) {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .lineLimit(3)
                    HStack(spacing: 16) {
                        Button("Retry") { model.retry(itemId: item.id) }
                            .font(.subheadline.weight(.semibold))
                        if DocumentScannerView.isSupported { Button("Retake") { retake(item.id) } }
                        Button("Remove", role: .destructive) {
                            model.discard(itemId: item.id)
                        }
                        .font(.subheadline)
                    }
                    .buttonStyle(.borderless)
                }
            case .qualityWarning(let message):
                VStack(alignment: .leading, spacing: 6) {
                    Label("Check image quality", systemImage: "camera.metering.unknown")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                    Text(message).font(.subheadline).foregroundStyle(.secondary)
                    HStack(spacing: 16) {
                        if DocumentScannerView.isSupported { Button("Retake") { retake(item.id) } }
                        Button("Read Anyway") { model.retry(itemId: item.id, acceptQuality: true) }
                        Button("Remove", role: .destructive) { model.discard(itemId: item.id) }
                    }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.borderless)
                }
            }
        }
        .task(id: item.id) {
            guard let url = model.imageURL(for: item) else { return }
            thumbnail = await Task.detached(priority: .utility) {
                Thumbnailer.thumbnail(from: url, maxPixel: 160)
            }.value
        }
        .fullScreenCover(isPresented: $showsScan) {
            if let url = model.imageURL(for: item) { ZoomableImageScreen(imageURL: url) }
        }
    }
}

struct PageThumbnail: View {
    let image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "doc.text")
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: 44, height: 58)
        .background(Color(.tertiarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color(.separator), lineWidth: 0.5)
        )
    }
}

struct ScoreBadge: View {
    let correct: Int
    let total: Int

    var body: some View {
        let allCorrect = correct == total
        Text("\(correct)/\(total)")
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(allCorrect ? Color.green : Color.orange)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                (allCorrect ? Color.green : Color.orange).opacity(0.14),
                in: Capsule()
            )
    }
}
