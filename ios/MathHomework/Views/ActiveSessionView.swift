import SwiftUI
import PhotosUI

/// The scanning workspace: scan or import pages, watch them move through OCR,
/// and dive into each page's review — all one-handed from the bottom bar.
struct ActiveSessionView: View {
    @Environment(AppModel.self) private var model
    @State private var showsScanner = false
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var confirmsEarlyDone = false
    @State private var autoOpenedScanner = false

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
                        if model.isQueueBusy {
                            confirmsEarlyDone = true
                        } else {
                            finish()
                        }
                    } label: {
                        Text("Done").bold()
                    }
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
                model.enqueue(images: images)
            } onCancel: {
                showsScanner = false
            }
            .ignoresSafeArea()
        }
        .confirmationDialog(
            "Some pages are still being read.",
            isPresented: $confirmsEarlyDone,
            titleVisibility: .visible
        ) {
            Button("Finish Anyway", role: .destructive) { finish() }
            Button("Keep Scanning", role: .cancel) {}
        } message: {
            Text("Unfinished pages will be discarded.")
        }
        .onAppear {
            guard !autoOpenedScanner else { return }
            autoOpenedScanner = true
            if let session, session.pages.isEmpty, model.scanQueue.isEmpty,
               DocumentScannerView.isSupported {
                showsScanner = true
            }
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
        if session.pages.isEmpty && model.scanQueue.isEmpty {
            ContentUnavailableView {
                Label("Scan the first page", systemImage: "doc.viewfinder")
            } description: {
                Text(
                    DocumentScannerView.isSupported
                        ? "Hold your iPhone over the worksheet. Pages are captured automatically and checked one by one."
                        : "This device has no camera scanner — add worksheet photos from your library instead."
                )
            }
        } else {
            List {
                if !session.pages.isEmpty {
                    Section("Checked pages") {
                        ForEach(session.pages) { page in
                            NavigationLink(value: page.id) {
                                PageRow(page: page)
                            }
                        }
                    }
                }
                if !model.scanQueue.isEmpty {
                    Section("Reading") {
                        ForEach(model.scanQueue) { item in
                            ScanQueueRow(item: item)
                        }
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

private struct PageRow: View {
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
                .lineLimit(1)
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
    @State private var thumbnail: UIImage?

    var body: some View {
        HStack(spacing: 12) {
            PageThumbnail(image: thumbnail)
            switch item.status {
            case .waiting:
                Text("Waiting…")
                    .foregroundStyle(.secondary)
            case .processing:
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reading the page")
                        .font(.body.weight(.medium))
                    Text("Transcribing and checking each answer…")
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
                        Button("Remove", role: .destructive) {
                            model.discard(itemId: item.id)
                        }
                        .font(.subheadline)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .task(id: item.id) {
            guard !item.jpegData.isEmpty else { return }
            let data = item.jpegData
            thumbnail = await Task.detached(priority: .utility) {
                Thumbnailer.thumbnail(from: data, maxPixel: 160)
            }.value
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
