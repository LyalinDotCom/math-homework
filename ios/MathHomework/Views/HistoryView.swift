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
    @State private var selectedPageIndex = 0

    private var session: Session? {
        model.history.first { $0.id == sessionId }
    }

    var body: some View {
        Group {
            if let session, !session.pages.isEmpty {
                TabView(selection: $selectedPageIndex) {
                    ForEach(Array(session.pages.enumerated()), id: \.element.id) { index, page in
                        ReviewView(sessionId: session.id, page: page)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: session.pages.count > 1 ? .always : .never))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
            } else {
                ContentUnavailableView {
                    Label("No pages in this session", systemImage: "doc")
                } description: {
                    Text("Resume the session to scan pages.")
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptics.tap()
                    model.resumeSession(sessionId)
                } label: {
                    Label("Resume", systemImage: "doc.viewfinder")
                }
            }
        }
    }

    private var title: String {
        guard let session,
              let startedAt = Timestamps.parseISO(session.metadata.startedAt)
        else { return "Session" }
        return startedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }
}
