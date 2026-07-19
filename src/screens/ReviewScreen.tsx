import type { RefObject } from "react";
import {
  ArrowLeft,
  Check,
  ChevronRight,
  RotateCcw,
  ScanLine,
  X,
} from "lucide-react";
import type { Page, Problem, Review } from "../types";

export function ReviewScreen({
  videoRef,
  page,
  pages,
  review,
  busy,
  saved,
  error,
  onNext,
  onSelectPage,
  onSave,
  onUpdate,
}: {
  videoRef: RefObject<HTMLVideoElement | null>;
  page: Page;
  pages: Page[];
  review: Review;
  busy: boolean;
  saved: boolean;
  error: string;
  onNext(): void;
  onSelectPage(page: Page): void;
  onSave(): void;
  onUpdate(index: number, patch: Partial<Problem>): void;
}) {
  const correct = review.problems.filter((item) => item.isCorrect).length;
  return (
    <div className="review-stage">
      <div className="review-heading">
        <div>
          <button className="text-back" onClick={onNext}>
            <ArrowLeft size={14} /> Camera
          </button>
          <h2>{review.worksheetTitle || `Page ${page.number}`}</h2>
          <p>{review.summary}</p>
        </div>
        <div className="review-heading-actions">
          <div className="mini-camera">
            <video ref={videoRef} autoPlay muted playsInline />
            <i />
          </div>
          <button className="next-button" onClick={onNext}>
            Next Page <ChevronRight size={15} />
          </button>
        </div>
      </div>
      <div className="session-pages">
        <span>This session</span>
        {pages.map((item) => (
          <button
            className={item.id === page.id ? "active" : ""}
            key={item.id}
            onClick={() => onSelectPage(item)}
          >
            Page {item.number}
          </button>
        ))}
        <button className="add-page" onClick={onNext}>
          + New Page
        </button>
      </div>
      {error && (
        <div className="error-banner">
          <X size={14} />
          {error}
        </div>
      )}
      <div className="review-grid">
        <section className="panel scan-panel">
          <div className="panel-title">
            <span>Original scan</span>
            <small>Page {page.number}</small>
          </div>
          <div className="scan-paper">
            <img
              src={page.imageDataUrl}
              alt={`Captured worksheet page ${page.number}`}
            />
          </div>
        </section>
        <section className="panel results-panel">
          <div className="panel-title">
            <span>Extracted work</span>
            <div className="score">
              <b>{correct}</b> of {review.problems.length} correct
            </div>
          </div>
          <div className="problem-list">
            {review.problems.map((problem, index) => (
              <div
                className={`problem-row ${problem.isCorrect ? "correct" : "wrong"}`}
                key={`${problem.number}-${index}`}
              >
                <div className="problem-number">
                  {problem.number || index + 1}
                </div>
                <div className="problem-copy">
                  <input
                    aria-label={`Problem ${index + 1}`}
                    value={problem.expression}
                    onChange={(event) =>
                      onUpdate(index, { expression: event.target.value })
                    }
                  />
                  <div className="answer-line">
                    <span>Student answer</span>
                    <input
                      value={problem.studentAnswer}
                      placeholder="Blank"
                      onChange={(event) =>
                        onUpdate(index, {
                          studentAnswer: event.target.value,
                          handwritingVerified: true,
                          verificationNote: "Confirmed manually.",
                        })
                      }
                    />
                  </div>
                  <div
                    className={`handwriting-status ${problem.handwritingVerified ? "verified" : "confirm"}`}
                  >
                    {problem.handwritingVerified ? (
                      <>
                        <Check size={12} /> Second OCR pass agreed
                      </>
                    ) : (
                      <>
                        <ScanLine size={12} /> Confirm the handwriting
                        {problem.verificationNote
                          ? ` — ${problem.verificationNote}`
                          : ""}
                      </>
                    )}
                  </div>
                  {!problem.isCorrect && (
                    <div className="correct-answer">
                      Correct answer <strong>{problem.correctAnswer}</strong>
                    </div>
                  )}
                </div>
                <div className="mark-toggle" aria-label="Manual grade override">
                  <button
                    className={
                      problem.manualIsCorrect === true ? "active green" : ""
                    }
                    title="Mark correct manually"
                    onClick={() =>
                      onUpdate(index, {
                        manualIsCorrect: true,
                        isCorrect: true,
                      })
                    }
                  >
                    <Check size={16} />
                  </button>
                  <button
                    className={
                      problem.manualIsCorrect === false ? "active red" : ""
                    }
                    title="Mark incorrect manually"
                    onClick={() =>
                      onUpdate(index, {
                        manualIsCorrect: false,
                        isCorrect: false,
                      })
                    }
                  >
                    <X size={16} />
                  </button>
                  <button
                    className={problem.manualIsCorrect == null ? "active" : ""}
                    title="Use the automatic grade"
                    onClick={() =>
                      onUpdate(index, {
                        manualIsCorrect: null,
                        isCorrect: problem.calculatedIsCorrect ?? false,
                      })
                    }
                  >
                    <RotateCcw size={14} />
                  </button>
                </div>
              </div>
            ))}
            {!review.problems.length && (
              <div className="empty-results">
                No readable math problems were found on this page.
              </div>
            )}
          </div>
          <div className="save-bar">
            <span>
              Compare the text with the scan and correct anything Gemini
              misread.
            </span>
            <button disabled={busy} onClick={onSave}>
              {saved ? (
                <>
                  <Check size={14} /> Saved
                </>
              ) : (
                "Save Corrections"
              )}
            </button>
          </div>
        </section>
      </div>
    </div>
  );
}
