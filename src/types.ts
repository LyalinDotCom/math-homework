export type { Page, Problem, Review, Session } from "../shared/contracts";

declare global {
  interface Window {
    mathHomework: {
      startSession(): Promise<import("../shared/contracts").Session>;
      resumeSession(
        sessionId: string,
      ): Promise<import("../shared/contracts").Session>;
      endSession(): Promise<import("../shared/contracts").Session | null>;
      chooseImage(): Promise<string | null>;
      reviewPage(
        imageDataUrl: string,
      ): Promise<import("../shared/contracts").Page & { sessionId: string }>;
      updatePage(
        sessionId: string,
        pageId: string,
        review: import("../shared/contracts").Review,
      ): Promise<import("../shared/contracts").Review>;
      listSessions(): Promise<import("../shared/contracts").Session[]>;
      getSession(
        sessionId: string,
      ): Promise<import("../shared/contracts").Session>;
      getPageImage(sessionId: string, pageId: string): Promise<string>;
      revealData(): Promise<string>;
    };
  }
}
