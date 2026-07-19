import { useCallback, useEffect, useRef, useState } from 'react';
import { Aperture, ArrowLeft, Camera, Check, ChevronRight, Clock3, FolderOpen, History, LoaderCircle, RotateCcw, ScanLine, Square, X } from 'lucide-react';
import type { Page, Problem, Review, Session } from './types';

const formatDate = (value: string) => new Intl.DateTimeFormat(undefined, { month: 'short', day: 'numeric', year: 'numeric' }).format(new Date(value));
const formatTime = (value: string) => new Intl.DateTimeFormat(undefined, { hour: 'numeric', minute: '2-digit' }).format(new Date(value));

function Logo() {
  return <div className="brand-mark" aria-hidden="true"><span /><span /><span /><span /></div>;
}

function App() {
  const videoRef = useRef<HTMLVideoElement>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const [view, setView] = useState<'home' | 'scan' | 'history'>('home');
  const [session, setSession] = useState<Session | null>(null);
  const [page, setPage] = useState<(Page & { sessionId?: string }) | null>(null);
  const [review, setReview] = useState<Review | null>(null);
  const [sessions, setSessions] = useState<Session[]>([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [saved, setSaved] = useState(false);

  const attachStream = useCallback(() => {
    if (videoRef.current && streamRef.current && videoRef.current.srcObject !== streamRef.current) {
      videoRef.current.srcObject = streamRef.current;
      videoRef.current.play().catch(() => undefined);
    }
  }, []);

  useEffect(attachStream, [attachStream, view, page]);
  useEffect(() => () => streamRef.current?.getTracks().forEach((track) => track.stop()), []);
  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if ((event.metaKey || event.ctrlKey) && event.key === 'Enter' && view === 'home') { event.preventDefault(); activateScan(); }
      if (event.code === 'Space' && view === 'scan' && !page && !busy && !(event.target instanceof HTMLInputElement)) { event.preventDefault(); captureAndReview(); }
    };
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  });

  async function activateScan() {
    setError('');
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: 'environment', width: { ideal: 2560 }, height: { ideal: 1440 } }, audio: false });
      streamRef.current = stream;
      const next = await window.mathHomework.startSession();
      setSession(next);
      setPage(null);
      setReview(null);
      setView('scan');
      requestAnimationFrame(attachStream);
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Camera access failed.');
    }
  }

  async function captureAndReview() {
    const video = videoRef.current;
    if (!video || !video.videoWidth || busy) return;
    setBusy(true);
    setError('');
    try {
      const canvas = document.createElement('canvas');
      const sourceX = Math.round(video.videoWidth * 0.08);
      const sourceY = Math.round(video.videoHeight * 0.07);
      const sourceWidth = Math.round(video.videoWidth * 0.84);
      const sourceHeight = Math.round(video.videoHeight * 0.86);
      canvas.width = sourceWidth;
      canvas.height = sourceHeight;
      canvas.getContext('2d')!.drawImage(video, sourceX, sourceY, sourceWidth, sourceHeight, 0, 0, sourceWidth, sourceHeight);
      const result = await window.mathHomework.reviewPage(canvas.toDataURL('image/jpeg', 0.92));
      setPage(result);
      setReview(result.review);
      setSession((current) => current ? { ...current, pages: [...current.pages, result] } : current);
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Review failed.');
    } finally { setBusy(false); }
  }

  async function saveReview(nextReview = review) {
    if (!page || !nextReview) return;
    setBusy(true);
    try {
      const updated = await window.mathHomework.updatePage(page.sessionId || session!.id, page.id, nextReview);
      setReview(updated);
      setSaved(true);
      window.setTimeout(() => setSaved(false), 1600);
    } catch (cause) { setError(cause instanceof Error ? cause.message : 'Could not save changes.'); }
    finally { setBusy(false); }
  }

  function updateProblem(index: number, patch: Partial<Problem>) {
    if (!review) return;
    const next = { ...review, problems: review.problems.map((problem, i) => i === index ? { ...problem, ...patch } : problem) };
    setReview(next);
  }

  async function finishSession() {
    await window.mathHomework.endSession();
    streamRef.current?.getTracks().forEach((track) => track.stop());
    streamRef.current = null;
    setSession(null); setPage(null); setReview(null); setView('home');
  }

  async function openHistory() {
    setBusy(true); setError('');
    try { setSessions(await window.mathHomework.listSessions()); setView('history'); }
    catch (cause) { setError(cause instanceof Error ? cause.message : 'Could not load history.'); }
    finally { setBusy(false); }
  }

  async function openPastSession(id: string) {
    setBusy(true);
    try {
      const item = await window.mathHomework.getSession(id);
      setSession(item); setPage(item.pages[0] || null); setReview(item.pages[0]?.review || null);
    } finally { setBusy(false); }
  }

  async function resumePastSession(id: string) {
    setBusy(true); setError('');
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: 'environment', width: { ideal: 2560 }, height: { ideal: 1440 } }, audio: false });
      streamRef.current = stream;
      const resumed = await window.mathHomework.resumeSession(id);
      setSession(resumed); setPage(null); setReview(null); setView('scan');
      requestAnimationFrame(attachStream);
    } catch (cause) {
      streamRef.current?.getTracks().forEach((track) => track.stop());
      streamRef.current = null;
      setError(cause instanceof Error ? cause.message : 'Could not resume this session.');
    } finally { setBusy(false); }
  }

  if (view === 'history') {
    return <HistoryView sessions={sessions} selected={session && !streamRef.current ? session : null} page={page} review={review} busy={busy}
      onBack={() => { setSession(null); setPage(null); setReview(null); setView('home'); }} onOpen={openPastSession}
      onSelectPage={(item) => { setPage(item); setReview(item.review); }} onResume={resumePastSession} onReveal={() => window.mathHomework.revealData()} />;
  }

  return <div className="app-shell">
    <header className="topbar">
      <button className="brand" onClick={() => view === 'home' || !session ? setView('home') : undefined}><Logo /><span>Math Homework</span></button>
      <div className="top-actions">
        {view === 'scan' && session && <div className="session-live"><i /> Session live <span>{session.pages.length} {session.pages.length === 1 ? 'page' : 'pages'}</span></div>}
        {view === 'scan' && <button className="done-button" onClick={finishSession}><Check size={17} /> Done</button>}
        {view === 'home' && <button className="quiet-button" onClick={openHistory}><History size={16} /> History</button>}
      </div>
    </header>

    {view === 'home' ? <main className="home">
      <div className="eyebrow"><span>LOCAL WORKSHEET REVIEW</span></div>
      <h1>Check the work.<br /><em>Keep the momentum.</em></h1>
      <p className="lede">Point the camera at a math worksheet, capture a page, and review every answer—without interrupting the session.</p>
      <div className="home-actions">
        <button className="primary-button" onClick={activateScan}><ScanLine size={20} /> Activate scan <span>⌘ ↵</span></button>
        <button className="secondary-button" onClick={openHistory}><Clock3 size={19} /> View history</button>
      </div>
      {error && <div className="error-banner"><X size={16} />{error}</div>}
      <div className="steps">
        <div><b>01</b><Camera /><h3>Position</h3><p>Hold one page flat in the camera frame.</p></div>
        <div><b>02</b><Aperture /><h3>Capture</h3><p>Press review when the page is sharp and clear.</p></div>
        <div><b>03</b><Check /><h3>Confirm</h3><p>Compare the scan and extracted work side by side.</p></div>
      </div>
      <div className="privacy-note">Saved privately on this Mac · Reviewed with Gemini 3.5 Flash</div>
    </main> :
    <main className="scanner">
      {!page ? <CameraStage videoRef={videoRef} busy={busy} onReview={captureAndReview} error={error} /> :
        <ReviewStage videoRef={videoRef} page={page} pages={session?.pages || []} review={review!} busy={busy} saved={saved} error={error}
          onNext={() => { setPage(null); setReview(null); setError(''); }}
          onSelectPage={(item) => { setPage(item); setReview(item.review); setError(''); }}
          onSave={() => saveReview()} onUpdate={updateProblem} />}
    </main>}
  </div>;
}

function CameraStage({ videoRef, busy, onReview, error }: { videoRef: React.RefObject<HTMLVideoElement | null>; busy: boolean; onReview(): void; error: string }) {
  return <div className="camera-stage">
    <div className="camera-copy"><span className="step-pill">PAGE READY</span><h2>Line up the worksheet</h2><p>Keep all four corners inside the guide. The camera stays active after every review.</p></div>
    <div className="camera-frame">
      <video ref={videoRef} autoPlay muted playsInline />
      <div className="corner tl"/><div className="corner tr"/><div className="corner bl"/><div className="corner br"/>
      {busy && <div className="processing"><LoaderCircle className="spin" /><strong>Reviewing the page</strong><span>Reading and checking each answer…</span></div>}
    </div>
    {error && <div className="error-banner"><X size={16}/><span>{error}</span><button onClick={onReview}>Retry page</button></div>}
    <button className="capture-button" disabled={busy} onClick={onReview}><span><Aperture size={25}/></span>{busy ? 'Reviewing…' : 'Capture & review'}<kbd>Space</kbd></button>
  </div>;
}

function ReviewStage({ videoRef, page, pages, review, busy, saved, error, onNext, onSelectPage, onSave, onUpdate }: { videoRef: React.RefObject<HTMLVideoElement | null>; page: Page; pages: Page[]; review: Review; busy: boolean; saved: boolean; error: string; onNext(): void; onSelectPage(page: Page): void; onSave(): void; onUpdate(index: number, patch: Partial<Problem>): void }) {
  const correct = review.problems.filter((item) => item.isCorrect).length;
  return <div className="review-stage">
    <div className="review-heading">
      <div><button className="text-back" onClick={onNext}><ArrowLeft size={15}/> Camera</button><h2>{review.worksheetTitle || `Page ${page.number}`}</h2><p>{review.summary}</p></div>
      <div className="review-heading-actions"><div className="mini-camera"><video ref={videoRef} autoPlay muted playsInline/><i/></div><button className="next-button" onClick={onNext}>Next page <ChevronRight size={17}/></button></div>
    </div>
    <div className="session-pages"><span>THIS SESSION</span>{pages.map((item) => <button className={item.id === page.id ? 'active' : ''} key={item.id} onClick={() => onSelectPage(item)}>Page {item.number}</button>)}<button className="add-page" onClick={onNext}>+ New page</button></div>
    {error && <div className="error-banner"><X size={16}/>{error}</div>}
    <div className="review-grid">
      <section className="panel scan-panel"><div className="panel-title"><span>ORIGINAL SCAN</span><small>Page {page.number}</small></div><div className="scan-paper"><img src={page.imageDataUrl} alt={`Captured worksheet page ${page.number}`}/></div></section>
      <section className="panel results-panel">
        <div className="panel-title"><span>EXTRACTED WORK</span><div className="score"><b>{correct}</b> / {review.problems.length} correct</div></div>
        <div className="problem-list">
          {review.problems.map((problem, index) => <div className={`problem-row ${problem.isCorrect ? 'correct' : 'wrong'}`} key={`${problem.number}-${index}`}>
            <div className="problem-number">{problem.number || index + 1}</div>
            <div className="problem-copy">
              <input aria-label={`Problem ${index + 1}`} value={problem.expression} onChange={(e) => onUpdate(index, { expression: e.target.value })}/>
              <div className="answer-line"><span>Student answer</span><input value={problem.studentAnswer} placeholder="Blank" onChange={(e) => onUpdate(index, { studentAnswer: e.target.value, handwritingVerified: true, verificationNote: 'Confirmed manually.' })}/></div>
              <div className={`handwriting-status ${problem.handwritingVerified ? 'verified' : 'confirm'}`}>{problem.handwritingVerified ? <><Check size={12}/> Handwriting checked twice</> : <><ScanLine size={12}/> Please confirm handwriting{problem.verificationNote ? ` — ${problem.verificationNote}` : ''}</>}</div>
              {!problem.isCorrect && <div className="correct-answer">Correct answer <strong>{problem.correctAnswer}</strong></div>}
            </div>
            <div className="mark-toggle" aria-label="Mark answer">
              <button className={problem.isCorrect ? 'active green' : ''} title="Correct" onClick={() => onUpdate(index, { isCorrect: true })}><Check size={16}/></button>
              <button className={!problem.isCorrect ? 'active red' : ''} title="Incorrect" onClick={() => onUpdate(index, { isCorrect: false })}><X size={16}/></button>
            </div>
          </div>)}
          {!review.problems.length && <div className="empty-results">No readable math problems were found on this page.</div>}
        </div>
        <div className="save-bar"><span>Compare the text with the scan and correct anything Gemini misread.</span><button disabled={busy} onClick={onSave}>{saved ? <><Check size={15}/> Saved</> : 'Save corrections'}</button></div>
      </section>
    </div>
  </div>;
}

function HistoryView({ sessions, selected, page, review, busy, onBack, onOpen, onSelectPage, onResume, onReveal }: { sessions: Session[]; selected: Session | null; page: Page | null; review: Review | null; busy: boolean; onBack(): void; onOpen(id: string): void; onSelectPage(page: Page): void; onResume(id: string): void; onReveal(): void }) {
  if (selected) return <div className="history-shell"><header className="topbar"><button className="brand" onClick={onBack}><Logo/><span>Math Homework</span></button><button className="quiet-button" onClick={onBack}><X size={16}/> Close history</button></header><main className="history-detail">
    <button className="text-back" onClick={onBack}><ArrowLeft size={15}/> All sessions</button><div className="detail-title"><div><span>SESSION</span><h2>{formatDate(selected.startedAt)} at {formatTime(selected.startedAt)}</h2></div><div className="detail-actions"><p>{selected.pages.length} pages reviewed</p><button className="resume-button" disabled={busy} onClick={() => onResume(selected.id)}><Camera size={16}/>{busy ? 'Opening camera…' : 'Resume session'}</button></div></div>
    <div className="history-page-tabs">{selected.pages.map((item) => <button className={item.id === page?.id ? 'active' : ''} onClick={() => onSelectPage(item)} key={item.id}>Page {item.number}</button>)}</div>
    {page && review && <div className="review-grid compact"><section className="panel scan-panel"><div className="panel-title"><span>ORIGINAL SCAN</span></div><div className="scan-paper"><img src={page.imageDataUrl}/></div></section><section className="panel results-panel"><div className="panel-title"><span>{review.worksheetTitle || 'EXTRACTED WORK'}</span><div className="score"><b>{review.problems.filter((p) => p.isCorrect).length}</b> / {review.problems.length} correct</div></div><div className="problem-list read-only">{review.problems.map((problem, i) => <div className={`problem-row ${problem.isCorrect ? 'correct' : 'wrong'}`} key={i}><div className="problem-number">{problem.number || i + 1}</div><div className="problem-copy"><strong>{problem.expression}</strong><div className="answer-line"><span>Student answer</span><b>{problem.studentAnswer || 'Blank'}</b></div>{!problem.isCorrect && <div className="correct-answer">Correct answer <strong>{problem.correctAnswer}</strong></div>}</div><div className={`result-icon ${problem.isCorrect ? 'green' : 'red'}`}>{problem.isCorrect ? <Check/> : <X/>}</div></div>)}</div></section></div>}
  </main></div>;
  return <div className="history-shell"><header className="topbar"><button className="brand" onClick={onBack}><Logo/><span>Math Homework</span></button><div className="top-actions"><button className="quiet-button" onClick={onReveal}><FolderOpen size={16}/> Show files</button><button className="quiet-button" onClick={onBack}><X size={16}/> Close</button></div></header><main className="history-list"><div className="history-hero"><span>REVIEW ARCHIVE</span><h1>Session history</h1><p>Every scan and answer review, saved locally on this Mac.</p></div>{busy ? <LoaderCircle className="spin history-loader"/> : sessions.length ? <div className="session-list">{sessions.map((item) => { const total = item.pages.reduce((sum, p) => sum + p.review.problems.length, 0); const correct = item.pages.reduce((sum, p) => sum + p.review.problems.filter((x) => x.isCorrect).length, 0); return <button className="session-card" key={item.id} onClick={() => onOpen(item.id)}><div className="date-tile"><b>{new Date(item.startedAt).getDate()}</b><span>{new Intl.DateTimeFormat(undefined, { month: 'short' }).format(new Date(item.startedAt)).toUpperCase()}</span></div><div className="session-info"><h3>{formatDate(item.startedAt)}</h3><p><Clock3 size={14}/>{formatTime(item.startedAt)} · {item.pages.length} {item.pages.length === 1 ? 'page' : 'pages'}</p></div><div className="session-score"><strong>{total ? Math.round(correct / total * 100) : 0}%</strong><span>{correct} of {total} correct</span></div><ChevronRight/></button>})}</div> : <div className="empty-history"><History/><h3>No sessions yet</h3><p>Your completed reviews will appear here.</p></div>}</main></div>;
}

export default App;
