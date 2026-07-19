import type { RefObject } from "react";
import { Aperture, LoaderCircle, X } from "lucide-react";

export function CameraScreen({
  videoRef,
  busy,
  onReview,
  error,
}: {
  videoRef: RefObject<HTMLVideoElement | null>;
  busy: boolean;
  onReview(): void;
  error: string;
}) {
  return (
    <div className="camera-stage">
      <div className="camera-copy">
        <span className="step-pill">PAGE READY</span>
        <h2>Line up the worksheet</h2>
        <p>
          Keep all four corners inside the guide. The camera stays active after
          every review.
        </p>
      </div>
      <div className="camera-frame">
        <video ref={videoRef} autoPlay muted playsInline />
        <div className="corner tl" />
        <div className="corner tr" />
        <div className="corner bl" />
        <div className="corner br" />
        {busy && (
          <div className="processing">
            <LoaderCircle className="spin" />
            <strong>Reviewing the page</strong>
            <span>Reading and checking each answer…</span>
          </div>
        )}
      </div>
      {error && (
        <div className="error-banner">
          <X size={16} />
          <span>{error}</span>
          <button onClick={onReview}>Retry page</button>
        </div>
      )}
      <button className="capture-button" disabled={busy} onClick={onReview}>
        <span>
          <Aperture size={25} />
        </span>
        {busy ? "Reviewing…" : "Capture & review"}
        <kbd>Space</kbd>
      </button>
    </div>
  );
}
