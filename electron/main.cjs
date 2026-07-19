const { app, BrowserWindow, ipcMain, shell, session } = require('electron');
const path = require('node:path');
const fs = require('node:fs/promises');
const { gradeLocally } = require('./math.cjs');
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });

const MODEL = 'gemini-3.5-flash';
let mainWindow;
let activeSessionId = null;

const transcriptionSchema = {
  type: 'object',
  properties: {
    worksheetTitle: { type: 'string', description: 'Visible worksheet title, level, set, or page number. Empty if none.' },
    problems: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          number: { type: 'string', description: 'Printed problem number or sequential number.' },
          expression: { type: 'string', description: 'Exact printed math problem, excluding the student answer.' },
          studentAnswer: { type: 'string', description: 'Exact handwritten or entered student answer. Empty if blank.' },
          confidence: { type: 'number', description: 'OCR confidence from 0 to 1.' }
        },
        required: ['number', 'expression', 'studentAnswer', 'confidence']
      }
    }
  },
  required: ['worksheetTitle', 'problems']
};

const handwritingVerificationSchema = {
  type: 'object',
  properties: {
    problems: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          index: { type: 'integer', description: 'Zero-based index from the supplied first-pass result.' },
          studentAnswer: { type: 'string', description: 'Only marks physically handwritten by the student in the answer area. Never include printed characters.' },
          confidence: { type: 'number', description: 'Confidence in the handwriting reading from 0 to 1.' },
          needsConfirmation: { type: 'boolean', description: 'True if handwriting is unclear or this reading differs from the supplied first pass.' },
          verificationNote: { type: 'string', description: 'Short plain-language reason when confirmation is needed; otherwise empty.' }
        },
        required: ['index', 'studentAnswer', 'confidence', 'needsConfirmation', 'verificationNote']
      }
    }
  },
  required: ['problems']
};

function dataRoot() {
  return path.join(app.getPath('documents'), 'Math Homework', 'meta');
}

function safeId(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}-\d{3}Z$/.test(value)) throw new Error('Invalid session identifier');
  return value;
}

function sessionPath(id) { return path.join(dataRoot(), safeId(id)); }
function timestampId() { return new Date().toISOString().replace(/:/g, '-').replace(/\./g, '-'); }
async function readJson(file) { return JSON.parse(await fs.readFile(file, 'utf8')); }
async function writeJson(file, value) { await fs.writeFile(file, JSON.stringify(value, null, 2)); }

async function loadSession(id, includeImages = false) {
  const dir = sessionPath(id);
  const meta = await readJson(path.join(dir, 'session.json'));
  const pages = [];
  for (const page of meta.pages || []) {
    const review = await readJson(path.join(dir, page.reviewFile));
    let imageDataUrl;
    if (includeImages) {
      const bytes = await fs.readFile(path.join(dir, page.imageFile));
      imageDataUrl = `data:image/jpeg;base64,${bytes.toString('base64')}`;
    }
    pages.push({ ...page, review, imageDataUrl });
  }
  return { ...meta, pages };
}

async function createSession() {
  const id = timestampId();
  const dir = sessionPath(id);
  await fs.mkdir(path.join(dir, 'pages'), { recursive: true });
  const meta = { id, startedAt: new Date().toISOString(), endedAt: null, pages: [] };
  await writeJson(path.join(dir, 'session.json'), meta);
  activeSessionId = id;
  return meta;
}

async function callGemini(imageBytes) {
  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) throw new Error('GEMINI_API_KEY is missing from .env');
  const { GoogleGenAI } = await import('@google/genai');
  const client = new GoogleGenAI({ apiKey });
  const image = { type: 'image', data: imageBytes.toString('base64'), mime_type: 'image/jpeg' };
  const interaction = await client.interactions.create({
    model: MODEL,
    store: false,
    input: [
      {
        type: 'text',
        text: `Transcribe this single structured math homework worksheet page. Read every visible printed math problem and the student's handwritten answer in reading order.

DO NOT SOLVE, CHECK, GRADE, OR EVEN MENTALLY COMPLETE ANY PROBLEM. The expected mathematical answer must not influence what you see. Your job in this pass is visual transcription only.

CRITICAL HANDWRITING RULES:
- studentAnswer contains ONLY marks physically handwritten by the student in the answer area.
- Never copy a printed equals sign, printed digit, problem number, operator, carry mark, or neighboring problem into studentAnswer.
- First identify the printed problem completely; then inspect the answer area separately.
- For example, if the page has a printed "=" followed by a handwritten "7", studentAnswer is "7", never "= 7", "17", or "= 17".
- Use an empty string for a blank answer. Do not guess an unclear digit; lower confidence instead.

Preserve fractions, decimals, negative signs, operators, and grouping exactly. Use an empty string for a blank answer. Do not invent cropped or unreadable problems. Return only the requested structured result.`
      },
      image
    ],
    response_format: { type: 'text', mime_type: 'application/json', schema: transcriptionSchema }
  });
  if (interaction.model && interaction.model !== MODEL) throw new Error(`Model mismatch: expected ${MODEL}, received ${interaction.model}`);
  if (!interaction.output_text) throw new Error('Gemini returned no review text');
  const result = JSON.parse(interaction.output_text);
  if (!Array.isArray(result.problems) || result.problems.length === 0) {
    throw new Error('No worksheet page was found. Hold the page inside the guide and try again.');
  }

  const verification = await client.interactions.create({
    model: MODEL,
    store: false,
    input: [
      {
        type: 'text',
        text: `Act as a strict, independent handwriting verifier for this worksheet image. The first-pass transcription JSON is supplied below. Re-inspect the original pixels for every problem in the same array order.

The most important task is separating pre-printed worksheet content from the student's pencil or pen marks. A printed equals sign or printed digit is never part of studentAnswer. Pay special attention to accidental additions such as reading a handwritten "7" as "17" because a nearby printed vertical stroke was included.

YOU ARE FORBIDDEN TO SOLVE OR GRADE THE MATH. Do not infer a digit because it would make the equation correct. Treat the mathematically expected answer as unknown. For example, for printed "13 + 4 =" followed by a single handwritten "7", the visual transcription is "7" even though that makes the work wrong.

Return one verification entry for every supplied problem. Set needsConfirmation=true whenever your studentAnswer differs from the first pass, confidence is below 0.85, the writing overlaps printing, or the mark is genuinely ambiguous. Do not preserve a first-pass reading merely to agree with it.

FIRST PASS JSON:
${JSON.stringify(result)}`
      },
      image
    ],
    response_format: { type: 'text', mime_type: 'application/json', schema: handwritingVerificationSchema }
  });
  if (verification.model && verification.model !== MODEL) throw new Error(`Model mismatch: expected ${MODEL}, received ${verification.model}`);
  if (!verification.output_text) throw new Error('Gemini returned no handwriting verification');
  const verified = JSON.parse(verification.output_text);
  const byIndex = new Map((verified.problems || []).map((problem) => [problem.index, problem]));
  result.problems = result.problems.map((problem, index) => {
    const check = byIndex.get(index);
    if (!check) return { ...problem, initialStudentAnswer: problem.studentAnswer, handwritingVerified: false, verificationNote: 'Could not complete the second handwriting check.' };
    return {
      ...problem,
      initialStudentAnswer: problem.studentAnswer,
      studentAnswer: check.studentAnswer,
      confidence: check.confidence,
      handwritingVerified: !check.needsConfirmation && check.confidence >= 0.85,
      verificationNote: check.verificationNote
    };
  });

  result.problems = result.problems.map((problem) => ({ ...problem, ...gradeLocally(problem.expression, problem.studentAnswer) }));
  const correctCount = result.problems.filter((problem) => problem.isCorrect).length;
  result.summary = `${correctCount} of ${result.problems.length} answers correct.`;
  result.model = MODEL;
  result.verificationPasses = 2;
  result.gradingMethod = 'local-arithmetic';
  result.reviewedAt = new Date().toISOString();
  return result;
}

async function reprocessSession(id, onProgress = () => {}) {
  const dir = sessionPath(id);
  const meta = await readJson(path.join(dir, 'session.json'));
  const completed = [];
  for (const page of meta.pages || []) {
    const imagePath = path.join(dir, page.imageFile);
    const reviewPath = path.join(dir, page.reviewFile);
    const backupPath = reviewPath.replace(/\.json$/, '.pre-ocr-fix.json');
    await fs.access(imagePath);
    if (!(await fs.stat(backupPath).then(() => true).catch(() => false))) {
      await fs.copyFile(reviewPath, backupPath);
    }
    onProgress(`Rechecking ${page.id}…`);
    const review = await callGemini(await fs.readFile(imagePath));
    review.reprocessedAt = new Date().toISOString();
    await writeJson(reviewPath, review);
    completed.push({ pageId: page.id, problems: review.problems.length });
    onProgress(`Updated ${page.id}`);
  }
  return completed;
}

async function createWindow() {
  session.defaultSession.setPermissionRequestHandler((_webContents, permission, callback) => callback(permission === 'media'));
  mainWindow = new BrowserWindow({
    width: 1440,
    height: 920,
    minWidth: 1040,
    minHeight: 700,
    backgroundColor: '#f7f5ef',
    titleBarStyle: 'hiddenInset',
    trafficLightPosition: { x: 18, y: 18 },
    webPreferences: { preload: path.join(__dirname, 'preload.cjs'), contextIsolation: true, nodeIntegration: false }
  });
  if (process.env.VITE_DEV_SERVER_URL) await mainWindow.loadURL(process.env.VITE_DEV_SERVER_URL);
  else await mainWindow.loadFile(path.join(__dirname, '..', 'dist', 'index.html'));
}

ipcMain.handle('session:start', async () => {
  if (activeSessionId) return loadSession(activeSessionId);
  return createSession();
});

ipcMain.handle('session:resume', async (_event, id) => {
  const safeSessionId = safeId(id);
  const dir = sessionPath(safeSessionId);
  const metaFile = path.join(dir, 'session.json');
  const meta = await readJson(metaFile);
  meta.endedAt = null;
  meta.resumedAt = [...(meta.resumedAt || []), new Date().toISOString()];
  await writeJson(metaFile, meta);
  activeSessionId = safeSessionId;
  return loadSession(safeSessionId, true);
});

ipcMain.handle('session:end', async () => {
  if (!activeSessionId) return null;
  const dir = sessionPath(activeSessionId);
  const meta = await readJson(path.join(dir, 'session.json'));
  meta.endedAt = new Date().toISOString();
  await writeJson(path.join(dir, 'session.json'), meta);
  activeSessionId = null;
  return meta;
});

ipcMain.handle('page:review', async (_event, imageDataUrl) => {
  if (!activeSessionId) throw new Error('Activate a scan session first');
  if (typeof imageDataUrl !== 'string' || !imageDataUrl.startsWith('data:image/jpeg;base64,')) throw new Error('Invalid scan image');
  const bytes = Buffer.from(imageDataUrl.split(',')[1], 'base64');
  if (bytes.length < 1000 || bytes.length > 18 * 1024 * 1024) throw new Error('Scan image size is invalid');
  const dir = sessionPath(activeSessionId);
  const metaFile = path.join(dir, 'session.json');
  const meta = await readJson(metaFile);
  const number = (meta.pages?.length || 0) + 1;
  const pageId = `page-${String(number).padStart(3, '0')}`;
  const imageFile = `pages/${pageId}.jpg`;
  const reviewFile = `pages/${pageId}.json`;
  await fs.writeFile(path.join(dir, imageFile), bytes);
  try {
    const review = await callGemini(bytes);
    const page = { id: pageId, number, capturedAt: new Date().toISOString(), imageFile, reviewFile };
    await writeJson(path.join(dir, reviewFile), review);
    meta.pages = [...(meta.pages || []), page];
    await writeJson(metaFile, meta);
    return { sessionId: activeSessionId, ...page, review, imageDataUrl };
  } catch (error) {
    await fs.unlink(path.join(dir, imageFile)).catch(() => {});
    throw error;
  }
});

ipcMain.handle('page:update', async (_event, payload) => {
  const id = safeId(payload.sessionId);
  if (!/^page-\d{3}$/.test(payload.pageId)) throw new Error('Invalid page identifier');
  const sessionData = await loadSession(id);
  const page = sessionData.pages.find((entry) => entry.id === payload.pageId);
  if (!page) throw new Error('Page not found');
  const problems = payload.review.problems.map((problem) => ({ ...problem, ...gradeLocally(problem.expression, problem.studentAnswer) }));
  const correctCount = problems.filter((problem) => problem.isCorrect).length;
  const review = { ...payload.review, problems, summary: `${correctCount} of ${problems.length} answers correct.`, model: MODEL, gradingMethod: 'local-arithmetic', editedAt: new Date().toISOString() };
  await writeJson(path.join(sessionPath(id), page.reviewFile), review);
  return review;
});

ipcMain.handle('session:list', async () => {
  await fs.mkdir(dataRoot(), { recursive: true });
  const entries = await fs.readdir(dataRoot(), { withFileTypes: true });
  const sessions = [];
  for (const entry of entries.filter((item) => item.isDirectory()).sort((a, b) => b.name.localeCompare(a.name))) {
    try { sessions.push(await loadSession(entry.name)); } catch { /* Ignore incomplete folders. */ }
  }
  return sessions;
});

ipcMain.handle('session:get', (_event, id) => loadSession(id, true));
ipcMain.handle('session:reprocess', (_event, id) => reprocessSession(safeId(id)));
ipcMain.handle('data:reveal', async () => { await fs.mkdir(dataRoot(), { recursive: true }); shell.showItemInFolder(dataRoot()); return dataRoot(); });

app.whenReady().then(async () => {
  if (process.env.MATH_HOMEWORK_REPROCESS_SESSION) {
    try {
      const completed = await reprocessSession(safeId(process.env.MATH_HOMEWORK_REPROCESS_SESSION), (message) => console.log(message));
      console.log(`Reprocessed ${completed.length} saved pages.`);
      app.exit(0);
    } catch (error) {
      console.error(error);
      app.exit(1);
    }
    return;
  }
  await createWindow();
});
app.on('window-all-closed', () => { if (process.platform !== 'darwin') app.quit(); });
app.on('activate', () => { if (BrowserWindow.getAllWindows().length === 0) createWindow(); });
