import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import math from '../electron/math.cjs';

const main = readFileSync(new URL('../electron/main.cjs', import.meta.url), 'utf8');
const preload = readFileSync(new URL('../electron/preload.cjs', import.meta.url), 'utf8');

describe('application contracts', () => {
  it('locks all worksheet reviews to Gemini 3.5 Flash', () => {
    expect(main).toContain("const MODEL = 'gemini-3.5-flash'");
    expect(main).toContain('model: MODEL');
    expect(main).not.toMatch(/gemini-(?!3\.5-flash)[\w.-]+/);
  });

  it('keeps the API key out of the renderer bridge', () => {
    expect(preload).not.toContain('GEMINI_API_KEY');
    expect(preload).not.toContain('process.env');
  });

  it('exposes the complete local session workflow', () => {
    for (const method of ['startSession', 'resumeSession', 'endSession', 'reviewPage', 'updatePage', 'listSessions', 'getSession', 'revealData']) {
      expect(preload).toContain(method);
    }
  });
});

describe('local arithmetic grading', () => {
  it('keeps OCR text separate from the calculated answer', () => {
    expect(math.gradeLocally('13 + 4', '7')).toEqual({ correctAnswer: '17', isCorrect: false, gradingMethod: 'local-arithmetic' });
    expect(math.gradeLocally('13 + 4', '17')).toEqual({ correctAnswer: '17', isCorrect: true, gradingMethod: 'local-arithmetic' });
  });

  it('handles common worksheet operators without AI', () => {
    expect(math.parseArithmetic('12 × 3')).toBe(36);
    expect(math.parseArithmetic('(20 - 8) ÷ 3')).toBe(4);
  });
});
