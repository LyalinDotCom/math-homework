# Math Homework for iOS

The iPhone port of the desktop app: scan worksheet pages with the system
document camera, let Gemini 3.8 Flash transcribe them in two independent
OCR-only readings, and grade the arithmetic locally on the phone. The archive
remains compatible with the Mac app. The phone also grades single missing-number
equations and consistent arithmetic number sequences.

## Run it on your iPhone

1. Open `ios/MathHomework.xcodeproj` in Xcode.
2. Plug in your iPhone and pick it as the run destination.
3. Press Run. Signing is already set to your Apple Development team
   (`UYD6DYP53S`) with automatic management; the first device run may ask you
   to trust the developer profile on the phone
   (Settings › General › VPN & Device Management).
4. On first launch, paste your Gemini API key in Settings (gear icon). The key
   lives in the iOS Keychain.

Local debug builds can skip step 4: if `ios/MathHomework/Secrets.plist`
exists (gitignored) with a `GEMINI_API_KEY` string, it seeds the Keychain on
first launch. Create it from the repo root with:

```bash
KEY=$(grep '^GEMINI_API_KEY=' .env | cut -d= -f2 | tr -d '"' | tr -d "[:space:]") && /usr/libexec/PlistBuddy -c "Add :GEMINI_API_KEY string $KEY" ios/MathHomework/Secrets.plist
```

## How the phone version uses the phone

- **Scanning is the system document camera** (VisionKit): hold the phone over
  the worksheet and pages are detected, de-skewed, and captured automatically —
  scan a whole stack in one pass, like the Notes scanner.
- **Three pages run concurrently**, with two independent readings per page
  (at most six API requests). Readers never see each other's answer. Results
  match by printed problem number, not by the model's column-reading order.
  OCR uses `generation_config.thinking_level=low`; grading remains local.
- **Every captured page is saved before network work.** The system scanner
  delivers its batch when you tap Save. Normalization saves each page as it
  finishes, then schedules OCR without waiting for the rest of the batch.
- **Interrupted work survives reopening.** Per-session `pending/*.json` files
  retain failures and quality warnings; `pages/*.reading-1.json` and
  `*.reading-2.json` checkpoint completed readings. Retry skips completed work.
  Done preserves unfinished scans. The home screen offers Resume; individual
  pages offer Retry, Retake, and Remove, plus Retry All for failures.
- **Switching apps requests limited iOS background time.** When time expires,
  requests pause and work resumes in the foreground. Force-quitting cannot
  continue processing; saved scans resume after reopening. Network recovery
  retries transient failures, with bounded backoff and `Retry-After` handling.
- **Poor-image warnings run locally before Gemini.** Vision text detection and
  normalized sharpness measurements hold blank, very blurry, or low-resolution
  captures for Retake or Read Anyway. This is a conservative warning, not a
  guarantee that faint pencil or every cropped problem is legible.
- **Review is built for thumbs**: swipe a problem right to mark it correct,
  left to mark it wrong or return it to the automatic grade; pinch or
  double-tap the original scan to zoom; swipe horizontally between pages of a
  session.
- **Read Again** rereads a completed page while keeping its previous result
  until a replacement succeeds. Disagreements about printed operands require
  confirmation; unsupported forms remain explicitly marked for manual review.
- **The archive is in the Files app** (On My iPhone › Math Homework): the same
  session folders of plain JPEG + JSON the Mac app writes, so folders can be
  copied between devices and open in either app.

## Project layout

```text
project.yml            xcodegen spec — `xcodegen generate` rebuilds the .xcodeproj
MathHomework/
  App/                 @main entry point
  Models/              Codable port of shared/contracts.ts (schemaVersion 2)
  Grading/             exact-fraction parser + grader (port of grade-problem.ts)
  Gemini/              prompts, JSON schemas, Interactions REST client, 2-pass OCR
  Storage/             archive repository (port of session-repository.ts), Keychain
  State/               AppModel: session lifecycle + scan queue
  Views/               SwiftUI screens
  Support/             image normalization, thumbnails, haptics
MathHomeworkTests/     grading parity tests (mirror of tests/grading.test.ts),
                       buildReview + repository round-trips, opt-in live Gemini test
MathHomeworkUITests/   screenshot walkthrough of the main flows
```

Request timings, status/error codes, page/stage identifiers, and quality metrics
are recorded in `Library/Application Support/Diagnostics/ocr.jsonl` with bounded
rotation. Logs contain no API key, image bytes, or worksheet text. Historical
reviews are regraded on load, preserving manual overrides and original archive
files until an explicit save.

## Checks

```bash
# unit + UI tests (simulator)
xcodebuild -project MathHomework.xcodeproj -scheme MathHomework \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' test

# optional local phone-example corpus (no live API calls)
TEST_RUNNER_WORKSHEET_ARCHIVE_ROOT=/absolute/path/to/copied/Documents \
  xcodebuild -project MathHomework.xcodeproj -scheme MathHomework \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:MathHomeworkTests test

# opt-in live Gemini check (mirrors tests/gemini-live.test.ts)
TEST_RUNNER_RUN_GEMINI_INTEGRATION=1 xcodebuild -project MathHomework.xcodeproj \
  -scheme MathHomework -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:MathHomeworkTests/GeminiLiveTests test
```

The Gemini wire protocol is the Interactions API
(`POST https://generativelanguage.googleapis.com/v1beta/interactions` with an
`x-goog-api-key` header), matching what `@google/genai` sends for the desktop
app, including the strict response schemas and the retry policy.
