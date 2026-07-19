function parseArithmetic(source) {
  const normalized = String(source)
    .replace(/[=？?].*$/, '')
    .replace(/[×xX·]/g, '*')
    .replace(/÷/g, '/')
    .replace(/[−–—]/g, '-')
    .replace(/,/g, '')
    .replace(/\s+/g, '');
  const tokens = normalized.match(/(?:\d+(?:\.\d+)?|\.\d+)|[()+\-*/]/g) || [];
  if (!tokens.length || tokens.join('') !== normalized) throw new Error('Unsupported math expression');
  let position = 0;
  const primary = () => {
    const token = tokens[position++];
    if (token === '+') return primary();
    if (token === '-') return -primary();
    if (token === '(') {
      const value = expression();
      if (tokens[position++] !== ')') throw new Error('Unclosed parenthesis');
      return value;
    }
    const value = Number(token);
    if (!Number.isFinite(value)) throw new Error('Invalid number');
    return value;
  };
  const term = () => {
    let value = primary();
    while (tokens[position] === '*' || tokens[position] === '/') {
      const operator = tokens[position++];
      const right = primary();
      if (operator === '/' && right === 0) throw new Error('Division by zero');
      value = operator === '*' ? value * right : value / right;
    }
    return value;
  };
  const expression = () => {
    let value = term();
    while (tokens[position] === '+' || tokens[position] === '-') {
      const operator = tokens[position++];
      const right = term();
      value = operator === '+' ? value + right : value - right;
    }
    return value;
  };
  const value = expression();
  if (position !== tokens.length || !Number.isFinite(value)) throw new Error('Invalid math expression');
  return value;
}

function formatAnswer(value) {
  if (Number.isInteger(value)) return String(value);
  return String(Number(value.toFixed(10)));
}

function gradeLocally(expression, studentAnswer) {
  try {
    const correctValue = parseArithmetic(expression);
    const studentValue = String(studentAnswer).trim() === '' ? null : parseArithmetic(studentAnswer);
    return {
      correctAnswer: formatAnswer(correctValue),
      isCorrect: studentValue !== null && Math.abs(studentValue - correctValue) < 1e-9,
      gradingMethod: 'local-arithmetic'
    };
  } catch {
    return { correctAnswer: 'Check manually', isCorrect: false, gradingMethod: 'manual-required' };
  }
}

module.exports = { parseArithmetic, gradeLocally };
