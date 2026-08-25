# Math Homework for iOS

The iPhone port of the desktop app: scan worksheet pages with the system
document camera, let Gemini 3.5 Flash transcribe them in two independent
OCR-only passes, and grade the arithmetic locally on the phone. Same archive
format, same prompts, same grading rules as the Mac app.

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
- **Pages OCR in the background** while you keep scanning; each page pops into
  the session list with its score the moment it's graded, with a haptic tap.
- **Review is built for thumbs**: swipe a problem right to mark it correct,
  left to mark it wrong or return it to the automatic grade; pinch or
  double-tap the original scan to zoom; swipe horizontally between pages of a
  session.
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

## Checks

```bash
# unit + UI tests (simulator)
xcodebuild -project MathHomework.xcodeproj -scheme MathHomework \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' test

# opt-in live Gemini check (mirrors tests/gemini-live.test.ts)
TEST_RUNNER_RUN_GEMINI_INTEGRATION=1 xcodebuild -project MathHomework.xcodeproj \
  -scheme MathHomework -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:MathHomeworkTests/GeminiLiveTests test
```

The Gemini wire protocol is the Interactions API
(`POST https://generativelanguage.googleapis.com/v1beta/interactions` with an
`x-goog-api-key` header), matching what `@google/genai` sends for the desktop
app, including the strict response schemas and the retry policy.
