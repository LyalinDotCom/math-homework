import SwiftUI

/// One page's extracted work: compare against the scan, fix anything the OCR
/// misread, and override grades with a swipe. Corrections regrade locally on
/// save, exactly like the desktop app.
struct ReviewView: View {
    @Environment(AppModel.self) private var model
    let sessionId: String
    let page: SessionPage

    @State private var review: Review
    @State private var savedReview: Review
    @State private var showsSaved = false
    @State private var showsZoom = false
    @State private var thumbnail: UIImage?
    @State private var saveError: String?
    @FocusState private var focusedField: String?

    init(sessionId: String, page: SessionPage) {
        self.sessionId = sessionId
        self.page = page
        _review = State(initialValue: page.review)
        _savedReview = State(initialValue: page.review)
    }

    private var isDirty: Bool { review != savedReview }

    var body: some View {
        List {
            Section {
                header
            }

            Section {
                if review.problems.isEmpty {
                    Text("No readable math problems were found on this page.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(review.problems.indices, id: \.self) { index in
                        problemRow(index: index)
                    }
                }
            } header: {
                Text("Extracted work")
            } footer: {
                if !review.problems.isEmpty {
                    Text("Compare with the scan and correct anything the OCR misread. Swipe a problem to override its grade.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            if isDirty || showsSaved {
                saveBar
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = nil }
            }
        }
        .fullScreenCover(isPresented: $showsZoom) {
            ZoomableImageScreen(imageURL: page.imageURL)
        }
        .alert(
            "Could not save changes",
            isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
        .task(id: page.id) {
            let url = page.imageURL
            thumbnail = await Task.detached(priority: .utility) {
                Thumbnailer.thumbnail(from: url, maxPixel: 480)
            }.value
        }
    }

    // MARK: - Header

    private var header: some View {
        let correct = review.problems.filter(\.isCorrect).count
        let needsConfirmation = review.problems.filter {
            $0.handwritingVerified != true
        }.count
        return Button {
            showsZoom = true
        } label: {
            HStack(spacing: 14) {
                PageThumbnail(image: thumbnail)
                    .frame(width: 56, height: 74)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(correct) of \(review.problems.count) correct")
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                    if needsConfirmation > 0 {
                        Label(
                            "\(needsConfirmation) to confirm",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                    }
                    Label("Tap to view the scan", systemImage: "plus.magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Problem rows

    private func answerBinding(_ index: Int) -> Binding<String> {
        Binding {
            review.problems[index].studentAnswer
        } set: { newValue in
            guard review.problems[index].studentAnswer != newValue else { return }
            review.problems[index].studentAnswer = newValue
            review.problems[index].handwritingVerified = true
            review.problems[index].verificationNote = "Confirmed manually."
        }
    }

    private func problemRow(index: Int) -> some View {
        let problem = review.problems[index]
        return HStack(alignment: .top, spacing: 12) {
            Text(problem.number.isEmpty ? "\(index + 1)" : problem.number)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 24, minHeight: 24)
                .background(Color(.tertiarySystemFill), in: Circle())

            VStack(alignment: .leading, spacing: 6) {
                TextField(
                    "Expression",
                    text: Binding(
                        get: { review.problems[index].expression },
                        set: { review.problems[index].expression = $0 }
                    )
                )
                .font(.body.weight(.semibold).monospacedDigit())
                .keyboardType(.numbersAndPunctuation)
                .autocorrectionDisabled()
                .focused($focusedField, equals: "expression-\(index)")

                HStack(spacing: 6) {
                    Text("Answer")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextField("Blank", text: answerBinding(index))
                        .font(.body.monospacedDigit())
                        .keyboardType(.numbersAndPunctuation)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: "answer-\(index)")
                }

                if problem.handwritingVerified == true {
                    Label("Second OCR pass agreed", systemImage: "checkmark.seal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Label(
                        problem.verificationNote.flatMap {
                            $0.isEmpty ? nil : "Confirm the handwriting — \($0)"
                        } ?? "Confirm the handwriting",
                        systemImage: "text.magnifyingglass"
                    )
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
                }

                if !problem.isCorrect {
                    (Text("Correct answer ")
                        .foregroundStyle(.secondary)
                        + Text(problem.correctAnswer).bold())
                        .font(.subheadline)
                }
            }

            Spacer(minLength: 4)

            gradeMenu(index: index)
        }
        .padding(.vertical, 4)
        .listRowBackground(
            (problem.isCorrect ? Color.green : Color.red)
                .opacity(0.08)
                .background(Color(.secondarySystemGroupedBackground))
        )
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                override(index: index, manual: true)
            } label: {
                Label("Correct", systemImage: "checkmark")
            }
            .tint(.green)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                override(index: index, manual: false)
            } label: {
                Label("Wrong", systemImage: "xmark")
            }
            .tint(.red)
            if problem.manualIsCorrect != nil {
                Button {
                    override(index: index, manual: nil)
                } label: {
                    Label("Auto", systemImage: "arrow.uturn.backward")
                }
            }
        }
    }

    private func gradeMenu(index: Int) -> some View {
        let problem = review.problems[index]
        return Menu {
            Button {
                override(index: index, manual: true)
            } label: {
                Label("Mark Correct", systemImage: "checkmark.circle")
            }
            Button {
                override(index: index, manual: false)
            } label: {
                Label("Mark Wrong", systemImage: "xmark.circle")
            }
            Button {
                override(index: index, manual: nil)
            } label: {
                Label("Use Automatic Grade", systemImage: "arrow.uturn.backward")
            }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: problem.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(problem.isCorrect ? Color.green : Color.red)
                if problem.manualIsCorrect != nil {
                    Text("manual")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func override(index: Int, manual: Bool?) {
        review.problems[index].manualIsCorrect = manual
        review.problems[index].isCorrect =
            manual ?? (review.problems[index].calculatedIsCorrect ?? false)
        Haptics.tap()
    }

    // MARK: - Save

    private var saveBar: some View {
        HStack(spacing: 12) {
            Text("Corrections are regraded on this iPhone.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                save()
            } label: {
                if showsSaved {
                    Label("Saved", systemImage: "checkmark")
                        .font(.headline)
                } else {
                    Text("Save")
                        .font(.headline)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isDirty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.bar)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func save() {
        focusedField = nil
        do {
            let saved = try model.saveReview(sessionId: sessionId, pageId: page.id, review: review)
            review = saved
            savedReview = saved
            Haptics.success()
            withAnimation { showsSaved = true }
            Task {
                try? await Task.sleep(nanoseconds: 1_600_000_000)
                withAnimation { showsSaved = false }
            }
        } catch {
            saveError = error.localizedDescription
        }
    }
}
