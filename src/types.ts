export type Problem = {
  number: string;
  expression: string;
  studentAnswer: string;
  correctAnswer: string;
  isCorrect: boolean;
  confidence: number;
  initialStudentAnswer?: string;
  handwritingVerified?: boolean;
  verificationNote?: string;
  gradingMethod?: 'local-arithmetic' | 'manual-required';
};

export type Review = {
  worksheetTitle: string;
  summary: string;
  problems: Problem[];
  model?: string;
  reviewedAt?: string;
  editedAt?: string;
  verificationPasses?: number;
  gradingMethod?: 'local-arithmetic';
};

export type Page = {
  id: string;
  number: number;
  capturedAt: string;
  imageFile: string;
  reviewFile: string;
  review: Review;
  imageDataUrl?: string;
  sessionId?: string;
};

export type Session = {
  id: string;
  startedAt: string;
  endedAt: string | null;
  resumedAt?: string[];
  pages: Page[];
};

declare global {
  interface Window {
    mathHomework: {
      startSession(): Promise<Session>;
      resumeSession(sessionId: string): Promise<Session>;
      endSession(): Promise<Session | null>;
      reviewPage(imageDataUrl: string): Promise<Page & { sessionId: string }>;
      updatePage(sessionId: string, pageId: string, review: Review): Promise<Review>;
      listSessions(): Promise<Session[]>;
      getSession(sessionId: string): Promise<Session>;
      reprocessSession(sessionId: string): Promise<Array<{ pageId: string; problems: number }>>;
      revealData(): Promise<string>;
    };
  }
}
