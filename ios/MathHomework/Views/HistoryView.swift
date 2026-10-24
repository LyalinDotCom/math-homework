import SwiftUI

struct HistoryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.history.isEmpty {
                ContentUnavailableView {
                    Label("No sessions yet", systemImage: "clock.arrow.circlepath")
                } description: {
                    Text("Your completed reviews will appear here.")
                }
            } else {
                List {
                    Section {
                        ForEach(model.history) { session in
                            NavigationLink(value: session.id) {
                                SessionRow(session: session)
                            }
                        }
                    } footer: {
                        Text("Every scan and review, saved on this iPhone. The files are yours — see them in the Files app under Math Homework.")
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("History")
        .task { model.refreshHistory() }
    }
}

struct SessionDetailView: View {
    @Environment(AppModel.self) private var model
    let sessionId: String
    @State private var pageSearch = ""

    private var session: Session? {
        model.history.first { $0.id == sessionId }
    }

    private var matchingPages: [SessionPage] {
        let query = pageSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        return (session?.pages ?? []).filter {
            query.isEmpty || $0.review.worksheetTitle.localizedCaseInsensitiveContains(query)
                || "Page \($0.metadata.number)".localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        Group {
            if let session, !session.pages.isEmpty {
                List {
                    Section {
                        if matchingPages.isEmpty {
                            ContentUnavailableView.search(text: pageSearch)
                        }
                        ForEach(matchingPages) { page in
                            NavigationLink {
                                SessionPageReviewView(sessionId: session.id, initialPageId: page.id)
                            } label: {
                                PageRow(page: page)
                            }
                        }
                    } header: {
                        Text("Worksheets")
                    } footer: {
                        Text("Tap a worksheet title to open that page.")
                    }
                }
                .listStyle(.insetGrouped)
            } else {
                ContentUnavailableView {
                    Label("No pages in this session", systemImage: "doc")
                } description: {
                    Text("Tap Add Pages to scan more worksheets into this session.")
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $pageSearch, placement: .navigationBarDrawer(displayMode: .always), prompt: "Find a worksheet title")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add Pages") {
                    Haptics.tap()
                    model.resumeSession(sessionId)
                }
            }
        }
    }

    private var title: String {
        guard let session, !session.pages.isEmpty else { return "Session" }
        return "\(session.pages.count) \(session.pages.count == 1 ? "Page" : "Pages")"
    }
}

/// Entered from a named worksheet row. Swiping remains available, while the
/// entire collection and its actions belong to the parent list screen.
struct SessionPageReviewView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let sessionId: String
    @State private var selectedPageId: String

    init(sessionId: String, initialPageId: String) {
        self.sessionId = sessionId
        _selectedPageId = State(initialValue: initialPageId)
    }

    private var session: Session? {
        model.history.first { $0.id == sessionId }
    }

    var body: some View {
        Group {
            if let session {
                TabView(selection: $selectedPageId) {
                    ForEach(session.pages) { page in
                        ReviewView(sessionId: session.id, page: page)
                            .tag(page.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: session.pages.count > 1 ? .always : .never))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Pages") { dismiss() }
            }
        }
    }

    private var title: String {
        guard let session,
              let index = session.pages.firstIndex(where: { $0.id == selectedPageId })
        else { return "Worksheet" }
        return "Page \(index + 1) of \(session.pages.count)"
    }
}
