import type { RefObject } from "react";
import { Camera, ImagePlus, LoaderCircle, X } from "lucide-react";

export function CameraScreen({
  videoRef,
  busy,
  onReview,
  onChooseImage,
  error,
}: {
  videoRef: RefObject<HTMLVideoElement | null>;
  busy: boolean;
  onReview(): void;
  onChooseImage(): void;
  error: string;
}) {
  return (
    <div className="camera-stage">
      <div className="camera-copy">
        <h2>Position the worksheet</h2>
        <p>
          Keep all four corners inside the guides. The camera stays on between
          pages.
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
          <X size={14} />
          <span>{error}</span>
          <button onClick={onReview}>Retry</button>
        </div>
      )}
      <button className="capture-button" disabled={busy} onClick={onReview}>
        <Camera size={15} />
        {busy ? "Reviewing…" : "Capture Page"}
        <kbd>Space</kbd>
      </button>
      <button
        className="choose-image-button"
        disabled={busy}
        onClick={onChooseImage}
      >
        <ImagePlus size={14} /> Choose Photo…
      </button>
    </div>
  );
}
