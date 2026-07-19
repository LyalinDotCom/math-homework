import { useEffect, useState } from "react";
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

  useEffect(() => {
    attachCamera();
  }, [attachCamera, view, page]);
  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
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
        !(event.target instanceof HTMLInputElement)
      ) {
        event.preventDefault();
        void captureAndReview();
      }
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  });

  async function activateScan() {
    setError("");
    try {
      await camera.open();
      const next = await window.mathHomework.startSession();
      setSession(next);
      setPage(null);
      setReview(null);
      setView("scan");
      requestAnimationFrame(camera.attach);
    } catch (cause) {
      camera.stop();
      setError(errorMessage(cause, "Camera access failed."));
    }
  }

  async function captureAndReview() {
    const video = camera.videoRef.current;
    if (!video || !video.videoWidth || busy) return;
    setBusy(true);
    setError("");
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
      const result = await window.mathHomework.reviewPage(
        canvas.toDataURL("image/jpeg", 0.92),
      );
      setPage(result);
      setReview(result.review);
      setSession((current) =>
        current ? { ...current, pages: [...current.pages, result] } : current,
      );
    } catch (cause) {
      setError(errorMessage(cause, "Review failed."));
    } finally {
      setBusy(false);
    }
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
    if (!session) return;
    setBusy(true);
    setError("");
    try {
      const hydrated = await hydratePage(session.id, selectedPage);
      setPage(hydrated);
      setReview(hydrated.review);
    } catch (cause) {
      setError(errorMessage(cause, "Could not load this page."));
    } finally {
      setBusy(false);
    }
  }

  async function saveReview() {
    if (!page || !review || !session) return;
    setBusy(true);
    setError("");
    try {
      const updated = await window.mathHomework.updatePage(
        session.id,
        page.id,
        review,
      );
      setReview(updated);
      setPage((current) =>
        current ? { ...current, review: updated } : current,
      );
      setSession((current) =>
        current
          ? {
              ...current,
              pages: current.pages.map((item) =>
                item.id === page.id ? { ...item, review: updated } : item,
              ),
            }
          : current,
      );
      setSaved(true);
      window.setTimeout(() => setSaved(false), 1_600);
    } catch (cause) {
      setError(errorMessage(cause, "Could not save changes."));
    } finally {
      setBusy(false);
    }
  }

  function updateProblem(index: number, patch: Partial<Problem>) {
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

  async function finishSession() {
    setError("");
    try {
      await window.mathHomework.endSession();
      camera.stop();
      setSession(null);
      setPage(null);
      setReview(null);
      setView("home");
    } catch (cause) {
      setError(errorMessage(cause, "Could not end the session."));
    }
  }

  async function openHistory() {
    setBusy(true);
    setError("");
    try {
      setSessions(await window.mathHomework.listSessions());
      setView("history");
    } catch (cause) {
      setError(errorMessage(cause, "Could not load history."));
    } finally {
      setBusy(false);
    }
  }

  async function openPastSession(id: string) {
    setBusy(true);
    setError("");
    try {
      const item = await window.mathHomework.getSession(id);
      setSession(item);
      const firstPage = item.pages[0]
        ? await hydratePage(item.id, item.pages[0])
        : null;
      setPage(firstPage);
      setReview(firstPage?.review ?? null);
    } catch (cause) {
      setError(errorMessage(cause, "Could not open this session."));
    } finally {
      setBusy(false);
    }
  }

  async function resumePastSession(id: string) {
    setBusy(true);
    setError("");
    try {
      await camera.open();
      const resumed = await window.mathHomework.resumeSession(id);
      setSession(resumed);
      setPage(null);
      setReview(null);
      setView("scan");
      requestAnimationFrame(camera.attach);
    } catch (cause) {
      camera.stop();
      setError(errorMessage(cause, "Could not resume this session."));
    } finally {
      setBusy(false);
    }
  }

  function closeHistory() {
    setSession(null);
    setPage(null);
    setReview(null);
    setError("");
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
              <i /> Session live{" "}
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
              <Check size={17} /> Done
            </button>
          )}
          {view === "home" && (
            <button className="quiet-button" onClick={() => void openHistory()}>
              <History size={16} /> History
            </button>
          )}
        </div>
      </header>
      {view === "home" ? (
        <HomeScreen
          onScan={() => void activateScan()}
          onHistory={() => void openHistory()}
          error={error}
        />
      ) : (
        <main className="scanner">
          {!page ? (
            <CameraScreen
              videoRef={camera.videoRef}
              busy={busy}
              onReview={() => void captureAndReview()}
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
              onNext={() => {
                setPage(null);
                setReview(null);
                setError("");
              }}
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
