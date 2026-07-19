import { GoogleGenAI } from "@google/genai";
import {
  HandwritingVerificationSchema,
  ReviewSchema,
  SESSION_SCHEMA_VERSION,
  TranscriptionSchema,
  toGeminiJsonSchema,
  type HandwritingVerification,
  type Review,
  type Transcription,
} from "../../shared/contracts";
import { gradeReview } from "../grading/grade-problem";
import { TRANSCRIPTION_PROMPT, verificationPrompt } from "./prompts";

export const GEMINI_MODEL = "gemini-3.5-flash";

const TRANSCRIPTION_JSON_SCHEMA = toGeminiJsonSchema(TranscriptionSchema);
const VERIFICATION_JSON_SCHEMA = toGeminiJsonSchema(
  HandwritingVerificationSchema,
);

type InteractionResult = {
  model?: string;
  output_text?: string;
};

function isRetriable(error: unknown) {
  if (!error || typeof error !== "object") return false;
  const candidate = error as {
    status?: number;
    code?: number | string;
    name?: string;
    message?: string;
  };
  // The only abort source is the local timeout watchdog, so treat it like the
  // SDK's own timeout error.
  if (candidate.name === "AbortError") return true;
  const status = Number(candidate.status ?? candidate.code);
  return (
    status === 408 ||
    status === 429 ||
    status >= 500 ||
    /timeout|temporar|unavailable|abort/i.test(candidate.message ?? "")
  );
}

async function createInteraction(
  client: GoogleGenAI,
  parameters: Parameters<GoogleGenAI["interactions"]["create"]>[0],
): Promise<InteractionResult> {
  let lastError: unknown;
  for (let attempt = 1; attempt <= 3; attempt += 1) {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 90_000);
    try {
      return (await client.interactions.create(parameters, {
        signal: controller.signal,
        timeout: 90_000,
        maxRetries: 0,
      })) as InteractionResult;
    } catch (error) {
      lastError = error;
      if (attempt === 3 || !isRetriable(error)) throw error;
      await new Promise((resolve) =>
        setTimeout(resolve, 400 * 2 ** (attempt - 1)),
      );
    } finally {
      clearTimeout(timeout);
    }
  }
  throw lastError;
}

function parseInteraction<T>(
  interaction: InteractionResult,
  model: string,
  parser: (value: unknown) => T,
  label: string,
) {
  if (interaction.model && interaction.model !== model) {
    throw new Error(
      `Model mismatch: expected ${model}, received ${interaction.model}`,
    );
  }
  if (!interaction.output_text) throw new Error(`Gemini returned no ${label}`);
  return parser(JSON.parse(interaction.output_text));
}

export function buildReview(
  transcription: Transcription,
  verification: HandwritingVerification,
  model: string,
  reviewedAt = new Date().toISOString(),
) {
  const byIndex = new Map(
    verification.problems.map((problem) => [problem.index, problem]),
  );
  if (byIndex.size !== transcription.problems.length) {
    throw new Error(
      "Gemini returned duplicate or missing handwriting verification entries",
    );
  }

  const problems = transcription.problems.map((problem, index) => {
    const check = byIndex.get(index);
    if (!check) throw new Error(`Gemini did not verify problem ${index + 1}`);
    return {
      ...problem,
      initialStudentAnswer: problem.studentAnswer,
      studentAnswer: check.studentAnswer,
      confidence: check.confidence,
      handwritingVerified: !check.needsConfirmation && check.confidence >= 0.85,
      verificationNote: check.verificationNote,
      correctAnswer: "",
      isCorrect: false,
    };
  });

  return ReviewSchema.parse(
    gradeReview({
      schemaVersion: SESSION_SCHEMA_VERSION,
      worksheetTitle: transcription.worksheetTitle,
      summary: "",
      problems,
      model,
      reviewedAt,
      ocrPasses: 2,
      verificationPasses: 2,
      gradingMethod: "local-arithmetic",
    }),
  );
}

export class WorksheetOcr {
  constructor(
    private readonly apiKey: string,
    readonly model: string,
  ) {}

  async review(imageBytes: Buffer): Promise<{
    review: Review;
    transcription: Transcription;
    verification: HandwritingVerification;
  }> {
    if (!this.apiKey) {
      throw new Error(
        "Gemini is not configured. Add GEMINI_API_KEY to the app's .env file.",
      );
    }
    const client = new GoogleGenAI({ apiKey: this.apiKey });
    const image = {
      type: "image" as const,
      data: imageBytes.toString("base64"),
      mime_type: "image/jpeg" as const,
    };
    const firstInteraction = await createInteraction(client, {
      model: this.model,
      store: false,
      input: [{ type: "text", text: TRANSCRIPTION_PROMPT }, image],
      response_format: {
        type: "text",
        mime_type: "application/json",
        schema: TRANSCRIPTION_JSON_SCHEMA,
      },
    });
    const transcription = parseInteraction(
      firstInteraction,
      this.model,
      (value) => TranscriptionSchema.parse(value),
      "transcription",
    );

    const verificationInteraction = await createInteraction(client, {
      model: this.model,
      store: false,
      input: [{ type: "text", text: verificationPrompt(transcription) }, image],
      response_format: {
        type: "text",
        mime_type: "application/json",
        schema: VERIFICATION_JSON_SCHEMA,
      },
    });
    const verification = parseInteraction(
      verificationInteraction,
      this.model,
      (value) => HandwritingVerificationSchema.parse(value),
      "handwriting verification",
    );

    const review = buildReview(transcription, verification, this.model);
    return { review, transcription, verification };
  }
}
