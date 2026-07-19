import { z } from "zod";

export const SESSION_SCHEMA_VERSION = 2;
export const SESSION_ID_PATTERN =
  /^\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}-\d{3}Z$/;
export const PAGE_ID_PATTERN = /^page-\d{3,6}$/;

const shortText = z.string().max(500);
const answerText = z.string().max(200);
const expressionText = z.string().min(1).max(500);
const timestamp = z.string().datetime({ offset: true });

export const TranscribedProblemSchema = z.object({
  number: shortText,
  expression: expressionText,
  studentAnswer: answerText,
  confidence: z.number().finite().min(0).max(1),
});

export const TranscriptionSchema = z.object({
  worksheetTitle: shortText,
  problems: z.array(TranscribedProblemSchema).min(1).max(500),
});

export const HandwritingVerificationItemSchema = z.object({
  index: z.number().int().min(0).max(499),
  studentAnswer: answerText,
  confidence: z.number().finite().min(0).max(1),
  needsConfirmation: z.boolean(),
  verificationNote: shortText,
});

export const HandwritingVerificationSchema = z.object({
  problems: z.array(HandwritingVerificationItemSchema).min(1).max(500),
});

export const ProblemSchema = TranscribedProblemSchema.extend({
  correctAnswer: answerText,
  isCorrect: z.boolean(),
  initialStudentAnswer: answerText.optional(),
  handwritingVerified: z.boolean().optional(),
  verificationNote: shortText.optional(),
  gradingMethod: z.enum(["local-arithmetic", "manual-required"]).optional(),
  calculatedIsCorrect: z.boolean().nullable().optional(),
  manualIsCorrect: z.boolean().nullable().optional(),
});

export const ReviewSchema = z.object({
  schemaVersion: z.number().int().positive().optional(),
  worksheetTitle: shortText,
  summary: shortText,
  problems: z.array(ProblemSchema).max(500),
  model: shortText.optional(),
  reviewedAt: timestamp.optional(),
  editedAt: timestamp.optional(),
  reprocessedAt: timestamp.optional(),
  ocrPasses: z.number().int().min(1).max(10).optional(),
  verificationPasses: z.number().int().min(1).max(10).optional(),
  gradingMethod: z.literal("local-arithmetic").optional(),
});

export const PageMetadataSchema = z.object({
  id: z.string().regex(PAGE_ID_PATTERN),
  number: z.number().int().positive().max(999_999),
  capturedAt: timestamp,
  imageFile: z.string().regex(/^pages\/page-\d{3,6}\.jpg$/),
  reviewFile: z.string().regex(/^pages\/page-\d{3,6}\.json$/),
  transcriptionFile: z
    .string()
    .regex(/^pages\/page-\d{3,6}\.transcription\.json$/)
    .optional(),
  verificationFile: z
    .string()
    .regex(/^pages\/page-\d{3,6}\.verification\.json$/)
    .optional(),
});

export const SessionMetadataSchema = z.object({
  schemaVersion: z.number().int().positive().optional(),
  id: z.string().regex(SESSION_ID_PATTERN),
  startedAt: timestamp,
  endedAt: timestamp.nullable(),
  resumedAt: z.array(timestamp).max(10_000).optional(),
  pages: z.array(PageMetadataSchema).max(999_999),
});

export const PageSchema = PageMetadataSchema.extend({
  review: ReviewSchema,
  imageDataUrl: z.string().optional(),
  sessionId: z.string().regex(SESSION_ID_PATTERN).optional(),
});

export const SessionSchema = SessionMetadataSchema.omit({ pages: true }).extend(
  {
    pages: z.array(PageSchema).max(999_999),
  },
);

export const UpdatePagePayloadSchema = z.object({
  sessionId: z.string().regex(SESSION_ID_PATTERN),
  pageId: z.string().regex(PAGE_ID_PATTERN),
  review: ReviewSchema,
});

export const ReviewImagePayloadSchema = z
  .string()
  .startsWith("data:image/jpeg;base64,")
  .max(24 * 1024 * 1024);

export function toGeminiJsonSchema(schema: z.ZodType) {
  const jsonSchema = z.toJSONSchema(schema, { target: "draft-07" }) as Record<
    string,
    unknown
  >;
  delete jsonSchema.$schema;

  // Gemini accepts a JSON Schema subset. Keep cardinality limits in the Zod
  // parser below the API boundary; Interactions rejects these two keywords.
  const supportedSubset = (value: unknown): unknown => {
    if (Array.isArray(value)) return value.map(supportedSubset);
    if (!value || typeof value !== "object") return value;
    return Object.fromEntries(
      Object.entries(value)
        .filter(([key]) => key !== "minItems" && key !== "maxItems")
        .map(([key, child]) => [key, supportedSubset(child)]),
    );
  };

  return supportedSubset(jsonSchema) as Record<string, unknown>;
}

export type Problem = z.infer<typeof ProblemSchema>;
export type Review = z.infer<typeof ReviewSchema>;
export type Page = z.infer<typeof PageSchema>;
export type Session = z.infer<typeof SessionSchema>;
export type PageMetadata = z.infer<typeof PageMetadataSchema>;
export type SessionMetadata = z.infer<typeof SessionMetadataSchema>;
export type Transcription = z.infer<typeof TranscriptionSchema>;
export type HandwritingVerification = z.infer<
  typeof HandwritingVerificationSchema
>;
