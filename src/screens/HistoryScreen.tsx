import {
  ArrowLeft,
  Camera,
  Check,
  ChevronRight,
  Clock3,
  FolderOpen,
  History,
  LoaderCircle,
  X,
} from "lucide-react";
import type { Page, Review, Session } from "../types";
import { Logo } from "../components/Logo";

const formatDate = (value: string) =>
  new Intl.DateTimeFormat(undefined, {
    month: "short",
    day: "numeric",
    year: "numeric",
  }).format(new Date(value));
const formatTime = (value: string) =>
  new Intl.DateTimeFormat(undefined, {
    hour: "numeric",
    minute: "2-digit",
  }).format(new Date(value));

export function HistoryScreen({
  sessions,
  selected,
  page,
  review,
  busy,
  error,
  onBack,
  onBackToList,
  onOpen,
  onSelectPage,
  onResume,
  onReveal,
}: {
  sessions: Session[];
  selected: Session | null;
  page: Page | null;
  review: Review | null;
  busy: boolean;
  error: string;
  onBack(): void;
  onBackToList(): void;
  onOpen(id: string): void;
  onSelectPage(page: Page): void;
  onResume(id: string): void;
  onReveal(): void;
}) {
  if (selected)
    return (
      <div className="history-shell">
        <header className="topbar">
          <button className="brand" onClick={onBack}>
            <Logo />
            <span>Math Homework</span>
          </button>
          <button className="quiet-button" onClick={onBack}>
            <X size={14} /> Close
          </button>
        </header>
        <main className="history-detail">
          <button className="text-back" onClick={onBackToList}>
            <ArrowLeft size={14} /> All Sessions
          </button>
          <div className="detail-title">
            <div>
              <span>Session</span>
              <h2>
                {formatDate(selected.startedAt)} at{" "}
                {formatTime(selected.startedAt)}
              </h2>
            </div>
            <div className="detail-actions">
              <p>
                {selected.pages.length}{" "}
                {selected.pages.length === 1 ? "page" : "pages"} reviewed
              </p>
              <button
                className="resume-button"
                disabled={busy}
                onClick={() => onResume(selected.id)}
              >
                <Camera size={14} />
                {busy ? "Opening Camera…" : "Resume Session"}
              </button>
            </div>
          </div>
          {error && (
            <div className="error-banner">
              <X size={14} />
              {error}
            </div>
          )}
          <div className="history-page-tabs">
            {selected.pages.map((item) => (
              <button
                className={item.id === page?.id ? "active" : ""}
                onClick={() => onSelectPage(item)}
                key={item.id}
              >
                Page {item.number}
              </button>
            ))}
          </div>
          {page && review && (
            <div className="review-grid compact">
              <section className="panel scan-panel">
                <div className="panel-title">
                  <span>Original scan</span>
                </div>
                <div className="scan-paper">
                  <img
                    src={page.imageDataUrl}
                    alt={`Worksheet page ${page.number}`}
                  />
                </div>
              </section>
              <section className="panel results-panel">
                <div className="panel-title">
                  <span>{review.worksheetTitle || "Extracted work"}</span>
                  <div className="score">
                    <b>
                      {
                        review.problems.filter((problem) => problem.isCorrect)
                          .length
                      }
                    </b>{" "}
                    of {review.problems.length} correct
                  </div>
                </div>
                <div className="problem-list read-only">
                  {review.problems.map((problem, index) => (
                    <div
                      className={`problem-row ${problem.isCorrect ? "correct" : "wrong"}`}
                      key={index}
                    >
                      <div className="problem-number">
                        {problem.number || index + 1}
                      </div>
                      <div className="problem-copy">
                        <strong>{problem.expression}</strong>
                        <div className="answer-line">
                          <span>Student answer</span>
                          <b>{problem.studentAnswer || "Blank"}</b>
                        </div>
                        {!problem.isCorrect && (
                          <div className="correct-answer">
                            Correct answer{" "}
                            <strong>{problem.correctAnswer}</strong>
                          </div>
                        )}
                      </div>
                      <div
                        className={`result-icon ${problem.isCorrect ? "green" : "red"}`}
                      >
                        {problem.isCorrect ? <Check /> : <X />}
                      </div>
                    </div>
                  ))}
                </div>
              </section>
            </div>
          )}
        </main>
      </div>
    );

  return (
    <div className="history-shell">
      <header className="topbar">
        <button className="brand" onClick={onBack}>
          <Logo />
          <span>Math Homework</span>
        </button>
        <div className="top-actions">
          <button className="quiet-button" onClick={onReveal}>
            <FolderOpen size={14} /> Show Files
          </button>
          <button className="quiet-button" onClick={onBack}>
            <X size={14} /> Close
          </button>
        </div>
      </header>
      <main className="history-list">
        <div className="history-hero">
          <h1>History</h1>
          <p>Every scan and review, saved on this Mac.</p>
        </div>
        {error && (
          <div className="error-banner">
            <X size={14} />
            {error}
          </div>
        )}
        {busy ? (
          <LoaderCircle className="spin history-loader" />
        ) : sessions.length ? (
          <div className="session-list">
            {sessions.map((item) => {
              const total = item.pages.reduce(
                (sum, currentPage) => sum + currentPage.review.problems.length,
                0,
              );
              const correct = item.pages.reduce(
                (sum, currentPage) =>
                  sum +
                  currentPage.review.problems.filter(
                    (problem) => problem.isCorrect,
                  ).length,
                0,
              );
              return (
                <button
                  className="session-card"
                  key={item.id}
                  onClick={() => onOpen(item.id)}
                >
                  <div className="date-tile">
                    <b>{new Date(item.startedAt).getDate()}</b>
                    <span>
                      {new Intl.DateTimeFormat(undefined, { month: "short" })
                        .format(new Date(item.startedAt))
                        .toUpperCase()}
                    </span>
                  </div>
                  <div className="session-info">
                    <h3>{formatDate(item.startedAt)}</h3>
                    <p>
                      <Clock3 size={12} />
                      {formatTime(item.startedAt)} · {item.pages.length}{" "}
                      {item.pages.length === 1 ? "page" : "pages"}
                    </p>
                  </div>
                  <div className="session-score">
                    <strong>
                      {total ? Math.round((correct / total) * 100) : 0}%
                    </strong>
                    <span>
                      {correct} of {total} correct
                    </span>
                  </div>
                  <ChevronRight />
                </button>
              );
            })}
          </div>
        ) : (
          <div className="empty-history">
            <History />
            <h3>No sessions yet</h3>
            <p>Your completed reviews will appear here.</p>
          </div>
        )}
      </main>
    </div>
  );
}
