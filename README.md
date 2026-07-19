# Math Homework

A camera-first Electron app that transcribes worksheet pages with Gemini and
grades supported arithmetic locally. Every scan and result is stored as an
ordinary JPEG or formatted JSON file on the Mac.

## How a page moves through the app

1. React requests camera video and captures the worksheet as a JPEG.
2. The sandboxed preload exposes a narrow IPC API; it does not expose Node.js.
3. The Electron main process validates the JPEG data URL and writes the original
   image before making a remote request.
4. Gemini 3.5 Flash performs two OCR-only passes: structured transcription, then
   an independent handwriting check. Both responses must match strict Zod
   schemas and are saved separately.
5. `mathjs` parses only a restricted arithmetic AST (`+`, `-`, `*`, `/`, and a
   bounded integer exponent). It computes the correct answer and compares the
   transcribed student answer. Gemini never decides whether the math is right.
6. The UI shows the scan and result together. A person can correct OCR text and
   explicitly override a grade; saving runs local grading again while preserving
   that manual override.

## Project structure

```text
electron/
  gemini/       OCR prompts, retries, response validation, OCR-to-grade boundary
  grading/      restricted mathjs evaluator and local grade calculation
  ipc/          validated renderer/main-process operations
  storage/      atomic, human-readable session repository
  main.ts       process lifecycle and dependency wiring
  preload.ts    narrow renderer bridge
  window.ts     sandbox, navigation, popup, and video permission policy
shared/
  contracts.ts  Zod runtime schemas and their inferred TypeScript types
src/
  components/   shared visual components
  hooks/        camera lifecycle
  screens/      home, camera, review, and history UI
  App.tsx       screen orchestration only
tests/          unit, storage, OCR-boundary, and saved-archive regressions
```

## Storage

The default root is:

```text
~/Documents/Math Homework/meta/
```

Each session is a timestamped folder:

```text
2026-07-19T12-34-56-789Z/
  session.json
  pages/
    page-001.jpg
    page-001.json
    page-001.transcription.json
    page-001.verification.json
```

`page-001.jpg` is the original capture. `page-001.json` is the editable final
review and local grade. The other JSON files preserve the two raw OCR stages.
Older sessions with only the JPEG and final JSON remain supported. JSON writes
are atomic, all paths are derived from validated IDs, and metadata cannot point
outside its session folder.

For an isolated test archive, set `MATH_HOMEWORK_DATA_ROOT` to an absolute or
relative folder. `MATH_HOMEWORK_REPROCESS_SESSION` is a main-process-only
maintenance option: it backs up each prior review before running Gemini again.

## Configuration and commands

Copy `.env.example` to `.env` and add the Gemini API key. History and local
archive browsing work without a key; scanning reports a clear configuration
error until one is present.

```bash
npm install
npm run dev
```

Quality gates:

```bash
npm run typecheck
npm run lint
npm test
npm run build
npm run format:check
npm audit
```

The archive regression reads `MATH_HOMEWORK_REGRESSION_ARCHIVE` when set. In
this workspace it defaults to the verified pre-hardening backup. It validates
every indexed JPEG and JSON file and checks that every previously supported
local grade and formatted correct answer is unchanged.

An opt-in real API check uses one saved image and makes both Gemini calls:

```bash
RUN_GEMINI_INTEGRATION=1 npx vitest run tests/gemini-live.test.ts
```

## Important dependencies

- `@google/genai`: the official Gemini SDK, used only from Electron's main process.
- `mathjs`: mature expression parsing and exact fraction arithmetic.
- `zod`: one source of truth for IPC, disk, and model-response validation.
- `write-file-atomic`: crash-resistant JSON replacement.
- `electron`, `react`, and `vite`: desktop shell, UI, and build pipeline.
- `vitest`, TypeScript, ESLint, and Prettier: regression, static, and style checks.

The dependency lockfile is committed. Images are sent to Google's Gemini API for
OCR with interaction storage disabled; the local archive itself is not uploaded
or synchronized by this app.
