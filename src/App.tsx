import { useEffect, useRef, useState } from "react";
import { Check, History } from "lucide-react";
import { Logo } from "./components/Logo";
import { useCamera } from "./hooks/useCamera";
import { CameraScreen } from "./screens/CameraScreen";
import { HistoryScreen } from "./screens/HistoryScreen";
import { HomeScreen } from "./screens/HomeScreen";
import { ReviewScreen } from "./screens/ReviewScreen";
import type { Page, Problem, Review, Session } from "./types";

type View = "home" | "scan" | "history";

function errorMessage(cause: unknown, fallback: string) {
  return cause instanceof Error ? cause.message : fallback;
}

export default function App() {
  const camera = useCamera();
  const attachCamera = camera.attach;
  const [view, setView] = useState<View>("home");
  const [session, setSession] = useState<Session | null>(null);
  const [page, setPage] = useState<Page | null>(null);
  const [review, setReview] = useState<Review | null>(null);
  const [sessions, setSessions] = useState<Session[]>([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [saved, setSaved] = useState(false);
  const [dirty, setDirty] = useState(false);

  // Slow IPC responses must never clobber state the user has navigated away
  // from: every operation takes a token, and stale completions are dropped.
  const opToken = useRef(0);
  const sessionIdRef = useRef<string | null>(null);
  const pageIdRef = useRef<string | null>(null);
  useEffect(() => {
    sessionIdRef.current = session?.id ?? null;
  }, [session]);
  useEffect(() => {
    pageIdRef.current = page?.id ?? null;
  }, [page]);

  useEffect(() => {
    attachCamera();
  }, [attachCamera, view, page]);
  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      const interactiveTarget =
        event.target instanceof HTMLInputElement ||
        event.target instanceof HTMLButtonElement;
      if (
        (event.metaKey || event.ctrlKey) &&
        event.key === "Enter" &&
        view === "home"
      ) {
        event.preventDefault();
        void activateScan();
      }
      if (
        event.code === "Space" &&
        view === "scan" &&
        !page &&
        !busy &&
        !interactiveTarget
      ) {
        event.preventDefault();
        void captureAndReview();
      }
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  });

  function beginOp() {
    const token = ++opToken.current;
    setBusy(true);
    setError("");
    return {
      isCurrent: () => opToken.current === token,
      end: () => {
        if (opToken.current === token) setBusy(false);
      },
    };
  }

  function confirmDiscard() {
    return (
      !dirty || window.confirm("Discard unsaved corrections on this page?")
    );
  }

  async function activateScan() {
    if (busy) return;
    const op = beginOp();
    try {
      await camera.open();
      const next = await window.mathHomework.startSession();
      setSession(next);
      setPage(null);
      setReview(null);
      setDirty(false);
      setView("scan");
      requestAnimationFrame(camera.attach);
    } catch (cause) {
      camera.stop();
      setError(errorMessage(cause, "Camera access failed."));
    } finally {
      op.end();
    }
  }

  async function captureAndReview() {
    const video = camera.videoRef.current;
    if (!video || !video.videoWidth || busy) return;
    const op = beginOp();
    try {
      const canvas = document.createElement("canvas");
      const sourceX = Math.round(video.videoWidth * 0.08);
      const sourceY = Math.round(video.videoHeight * 0.07);
      const sourceWidth = Math.round(video.videoWidth * 0.84);
      const sourceHeight = Math.round(video.videoHeight * 0.86);
      canvas.width = sourceWidth;
      canvas.height = sourceHeight;
      const context = canvas.getContext("2d");
      if (!context) throw new Error("Could not prepare the camera image.");
      context.drawImage(
        video,
        sourceX,
        sourceY,
        sourceWidth,
        sourceHeight,
        0,
        0,
        sourceWidth,
        sourceHeight,
      );
      await reviewImage(canvas.toDataURL("image/jpeg", 0.92), op.isCurrent);
    } catch (cause) {
      if (op.isCurrent()) setError(errorMessage(cause, "Review failed."));
    } finally {
      op.end();
    }
  }

  async function chooseImageAndReview() {
    if (busy) return;
    const op = beginOp();
    try {
      const imageDataUrl = await window.mathHomework.chooseImage();
      if (imageDataUrl) await reviewImage(imageDataUrl, op.isCurrent);
    } catch (cause) {
      if (op.isCurrent())
        setError(errorMessage(cause, "Could not use the selected image."));
    } finally {
      op.end();
    }
  }

  async function reviewImage(imageDataUrl: string, isCurrent: () => boolean) {
    const result = await window.mathHomework.reviewPage(imageDataUrl);
    // The session may have been ended or replaced while OCR ran; the page is
    // safely on disk in its own session, so just drop the stale UI update.
    if (!isCurrent() || sessionIdRef.current !== result.sessionId) return;
    setPage(result);
    setReview(result.review);
    setDirty(false);
    setSession((current) =>
      current && current.id === result.sessionId
        ? { ...current, pages: [...current.pages, result] }
        : current,
    );
  }

  async function hydratePage(sessionId: string, selectedPage: Page) {
    if (selectedPage.imageDataUrl) return selectedPage;
    const imageDataUrl = await window.mathHomework.getPageImage(
      sessionId,
      selectedPage.id,
    );
    return { ...selectedPage, sessionId, imageDataUrl };
  }

  async function selectPage(selectedPage: Page) {
    if (!session || busy) return;
    if (selectedPage.id === page?.id) return;
    if (!confirmDiscard()) return;
    const op = beginOp();
    try {
      const hydrated = await hydratePage(session.id, selectedPage);
      if (!op.isCurrent()) return;
      setPage(hydrated);
      setReview(hydrated.review);
      setDirty(false);
    } catch (cause) {
      if (op.isCurrent())
        setError(errorMessage(cause, "Could not load this page."));
    } finally {
      op.end();
    }
  }

  async function saveReview() {
    if (!page || !review || !session || busy) return;
    const targetSessionId = session.id;
    const targetPageId = page.id;
    const op = beginOp();
    try {
      const updated = await window.mathHomework.updatePage(
        targetSessionId,
        targetPageId,
        review,
      );
      setSession((current) =>
        current && current.id === targetSessionId
          ? {
              ...current,
              pages: current.pages.map((item) =>
                item.id === targetPageId ? { ...item, review: updated } : item,
              ),
            }
          : current,
      );
      // Only refresh the visible review if the user is still on that page.
      if (pageIdRef.current === targetPageId) {
        setPage((current) =>
          current ? { ...current, review: updated } : current,
        );
        setReview(updated);
        setDirty(false);
        setSaved(true);
        window.setTimeout(() => setSaved(false), 1_600);
      }
    } catch (cause) {
      if (op.isCurrent())
        setError(errorMessage(cause, "Could not save changes."));
    } finally {
      op.end();
    }
  }

  function updateProblem(index: number, patch: Partial<Problem>) {
    setDirty(true);
    setReview((current) =>
      current
        ? {
            ...current,
            problems: current.problems.map((problem, problemIndex) =>
              problemIndex === index ? { ...problem, ...patch } : problem,
            ),
          }
        : current,
    );
  }

  function nextPage() {
    if (!confirmDiscard()) return;
    setPage(null);
    setReview(null);
    setDirty(false);
    setError("");
  }

  async function finishSession() {
    if (!confirmDiscard()) return;
    opToken.current += 1; // any in-flight capture no longer owns the UI
    setBusy(false);
    setError("");
    try {
      await window.mathHomework.endSession();
    } catch (cause) {
      setError(errorMessage(cause, "Could not end the session."));
    } finally {
      // The main process always leaves the session inactive, so mirror that
      // here even when stamping endedAt failed.
      camera.stop();
      setSession(null);
      setPage(null);
      setReview(null);
      setDirty(false);
      setView("home");
    }
  }

  async function openHistory() {
    if (busy) return;
    const op = beginOp();
    try {
      const list = await window.mathHomework.listSessions();
      if (!op.isCurrent()) return;
      setSessions(list);
      setView("history");
    } catch (cause) {
      if (op.isCurrent())
        setError(errorMessage(cause, "Could not load history."));
    } finally {
      op.end();
    }
  }

  async function openPastSession(id: string) {
    if (busy) return;
    const op = beginOp();
    try {
      const item = await window.mathHomework.getSession(id);
      const firstPage = item.pages[0]
        ? await hydratePage(item.id, item.pages[0])
        : null;
      if (!op.isCurrent()) return;
      setSession(item);
      setPage(firstPage);
      setReview(firstPage?.review ?? null);
    } catch (cause) {
      if (op.isCurrent())
        setError(errorMessage(cause, "Could not open this session."));
    } finally {
      op.end();
    }
  }

  async function resumePastSession(id: string) {
    if (busy) return;
    const op = beginOp();
    try {
      await camera.open();
      const resumed = await window.mathHomework.resumeSession(id);
      setSession(resumed);
      setPage(null);
      setReview(null);
      setDirty(false);
      setView("scan");
      requestAnimationFrame(camera.attach);
    } catch (cause) {
      camera.stop();
      if (op.isCurrent())
        setError(errorMessage(cause, "Could not resume this session."));
    } finally {
      op.end();
    }
  }

  function backToSessionList() {
    setSession(null);
    setPage(null);
    setReview(null);
    setError("");
  }

  function closeHistory() {
    backToSessionList();
    setView("home");
  }

  if (view === "history") {
    return (
      <HistoryScreen
        sessions={sessions}
        selected={session}
        page={page}
        review={review}
        busy={busy}
        error={error}
        onBack={closeHistory}
        onBackToList={backToSessionList}
        onOpen={(id) => void openPastSession(id)}
        onSelectPage={(item) => void selectPage(item)}
        onResume={(id) => void resumePastSession(id)}
        onReveal={() => void window.mathHomework.revealData()}
      />
    );
  }

  return (
    <div className="app-shell">
      <header className="topbar">
        <button
          className="brand"
          onClick={() =>
            view === "home" || !session ? setView("home") : undefined
          }
        >
          <Logo />
          <span>Math Homework</span>
        </button>
        <div className="top-actions">
          {view === "scan" && session && (
            <div className="session-live">
              <i /> Recording{" "}
              <span>
                {session.pages.length}{" "}
                {session.pages.length === 1 ? "page" : "pages"}
              </span>
            </div>
          )}
          {view === "scan" && (
            <button
              className="done-button"
              onClick={() => void finishSession()}
            >
              <Check size={14} /> Done
            </button>
          )}
          {view === "home" && (
            <button
              className="quiet-button"
              disabled={busy}
              onClick={() => void openHistory()}
            >
              <History size={14} /> History
            </button>
          )}
        </div>
      </header>
      {view === "home" ? (
        <HomeScreen
          onScan={() => void activateScan()}
          onHistory={() => void openHistory()}
          busy={busy}
          error={error}
        />
      ) : (
        <main className="scanner">
          {!page ? (
            <CameraScreen
              videoRef={camera.videoRef}
              busy={busy}
              onReview={() => void captureAndReview()}
              onChooseImage={() => void chooseImageAndReview()}
              error={error}
            />
          ) : (
            <ReviewScreen
              videoRef={camera.videoRef}
              page={page}
              pages={session?.pages ?? []}
              review={review!}
              busy={busy}
              saved={saved}
              error={error}
              onNext={nextPage}
              onSelectPage={(item) => void selectPage(item)}
              onSave={() => void saveReview()}
              onUpdate={updateProblem}
            />
          )}
        </main>
      )}
    </div>
  );
}
