import { useCallback, useEffect, useRef } from "react";

export function useCamera() {
  const videoRef = useRef<HTMLVideoElement>(null);
  const streamRef = useRef<MediaStream | null>(null);

  const attach = useCallback(() => {
    if (
      videoRef.current &&
      streamRef.current &&
      videoRef.current.srcObject !== streamRef.current
    ) {
      videoRef.current.srcObject = streamRef.current;
      videoRef.current.play().catch(() => undefined);
    }
  }, []);

  const stop = useCallback(() => {
    streamRef.current?.getTracks().forEach((track) => track.stop());
    streamRef.current = null;
    if (videoRef.current) videoRef.current.srcObject = null;
  }, []);

  const open = useCallback(async () => {
    stop();
    const stream = await navigator.mediaDevices.getUserMedia({
      video: {
        facingMode: "environment",
        width: { ideal: 2560 },
        height: { ideal: 1440 },
      },
      audio: false,
    });
    if (streamRef.current && streamRef.current !== stream) {
      // A concurrent open() finished first; discard this stream so the
      // camera is not left recording with no reference to it.
      stream.getTracks().forEach((track) => track.stop());
      return streamRef.current;
    }
    streamRef.current = stream;
    return stream;
  }, [stop]);

  useEffect(() => stop, [stop]);

  return { videoRef, streamRef, attach, open, stop };
}
