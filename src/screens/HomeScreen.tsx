import { Aperture, Camera, Check, X } from "lucide-react";
import { Logo } from "../components/Logo";

export function HomeScreen({
  onScan,
  onHistory,
  busy,
  error,
}: {
  onScan(): void;
  onHistory(): void;
  busy: boolean;
  error: string;
}) {
  return (
    <main className="home">
      <Logo large />
      <h1>Math Homework</h1>
      <p className="lede">
        Point the camera at a worksheet, capture each page, and check every
        answer side by side. Graded locally, saved on this Mac.
      </p>
      <div className="home-actions">
        <button className="primary-button" disabled={busy} onClick={onScan}>
          {busy ? "Opening Camera…" : "Start Scanning"} <kbd>⌘↩</kbd>
        </button>
        <button
          className="secondary-button"
          disabled={busy}
          onClick={onHistory}
        >
          View History
        </button>
      </div>
      {error && (
        <div className="error-banner">
          <X size={14} />
          {error}
        </div>
      )}
      <div className="steps">
        <div>
          <Camera />
          <h3>Position</h3>
          <p>Hold one page flat inside the frame.</p>
        </div>
        <div>
          <Aperture />
          <h3>Capture</h3>
          <p>Take the shot when the page is sharp.</p>
        </div>
        <div>
          <Check />
          <h3>Confirm</h3>
          <p>Compare the scan with the extracted work.</p>
        </div>
      </div>
      <div className="privacy-note">
        Saved on this Mac · OCR by Gemini 3.5 Flash
      </div>
    </main>
  );
}
