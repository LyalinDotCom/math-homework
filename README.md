# Math Homework

A camera-first Electron app for reviewing one math worksheet page at a time. The camera remains active while a session is open, and each captured page is checked with the official Google GenAI SDK using only `gemini-3.5-flash`.

## Run it

The repository expects a `.env` file containing:

```text
GEMINI_API_KEY=your-key
```

Then run:

```bash
npm install
npm run dev
```

For a production-renderer smoke test:

```bash
npm run build
npm start
```

## Storage

Sessions are plain folders under `~/Documents/Math Homework/meta`. Each timestamped session folder contains `session.json` plus a `pages` folder with the original JPEG scan and structured JSON review for every page. The app's History screen has a **Show files** button that opens this location.

Pressing **Done** stamps the session end time and stops the camera. Failed or empty scans are not added to the session and can be retried immediately.
