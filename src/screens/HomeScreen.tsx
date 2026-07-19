import { Aperture, Camera, Check, Clock3, ScanLine, X } from "lucide-react";

export function HomeScreen({
  onScan,
  onHistory,
  error,
}: {
  onScan(): void;
  onHistory(): void;
  error: string;
}) {
  return (
    <main className="home">
      <div className="eyebrow">
        <span>LOCAL WORKSHEET REVIEW</span>
      </div>
      <h1>
        Check the work.
        <br />
        <em>Keep the momentum.</em>
      </h1>
      <p className="lede">
        Point the camera at a math worksheet, capture a page, and review every
        answer—without interrupting the session.
      </p>
      <div className="home-actions">
        <button className="primary-button" onClick={onScan}>
          <ScanLine size={20} /> Activate scan <span>⌘ ↵</span>
        </button>
        <button className="secondary-button" onClick={onHistory}>
          <Clock3 size={19} /> View history
        </button>
      </div>
      {error && (
        <div className="error-banner">
          <X size={16} />
          {error}
        </div>
      )}
      <div className="steps">
        <div>
          <b>01</b>
          <Camera />
          <h3>Position</h3>
          <p>Hold one page flat in the camera frame.</p>
        </div>
        <div>
          <b>02</b>
          <Aperture />
          <h3>Capture</h3>
          <p>Press review when the page is sharp and clear.</p>
        </div>
        <div>
          <b>03</b>
          <Check />
          <h3>Confirm</h3>
          <p>Compare the scan and extracted work side by side.</p>
        </div>
      </div>
      <div className="privacy-note">
        Archive saved on this Mac · Images processed by Gemini 3.5 Flash
      </div>
    </main>
  );
}
