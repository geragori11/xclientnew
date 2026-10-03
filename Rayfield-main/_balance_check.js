const fs = require('fs');

function strip(src) {
  let out = '';
  let i = 0;
  const n = src.length;
  while (i < n) {
    const c = src[i];
    if (c === '-' && src.startsWith('--', i)) {
      const m = /^--\[(=*)\[/.exec(src.slice(i));
      if (m) {
        const close = ']' + m[1] + ']';
        const j = src.indexOf(close, i);
        i = j < 0 ? n : j + close.length;
        out += ' ';
        continue;
      }
      const j = src.indexOf('\n', i);
      if (j < 0) { i = n; } else { i = j; out += '\n'; }
      continue;
    }
    if (c === '[') {
      const m = /^\[(=*)\[/.exec(src.slice(i));
      if (m) {
        const close = ']' + m[1] + ']';
        const j = src.indexOf(close, i + m[0].length);
        i = j < 0 ? n : j + close.length;
        out += ' ';
        continue;
      }
    }
    if (c === '"' || c === "'") {
      const q = c;
      i++;
      while (i < n) {
        if (src[i] === '\\') { i += 2; continue; }
        if (src[i] === q) { i++; break; }
        if (src[i] === '\n') break;
        i++;
      }
      out += ' ';
      continue;
    }
    out += c;
    i++;
  }
  return out;
}

function check(path) {
  const src = fs.readFileSync(path, 'utf8');
  const clean = strip(src);
  const re = /\b(function|if|for|while|do|repeat|end|until)\b/g;
  let depth = 0, last = null, min = 0, m;
  while ((m = re.exec(clean)) !== null) {
    const k = m[1];
    if (k === 'function' || k === 'if' || k === 'for' || k === 'while' || k === 'repeat') {
      depth++; last = k;
    } else if (k === 'do') {
      if (last !== 'for' && last !== 'while') depth++;
      last = k;
    } else if (k === 'end') {
      depth--; last = k;
    } else if (k === 'until') {
      depth--; last = k;
    }
    if (depth < min) min = depth;
  }
  const paren = (clean.match(/\(/g) || []).length - (clean.match(/\)/g) || []).length;
  const brace = (clean.match(/\{/g) || []).length - (clean.match(/\}/g) || []).length;
  const brack = (clean.match(/\[/g) || []).length - (clean.match(/\]/g) || []).length;
  console.log(`${path.slice(-46)}  depth=${depth} min=${min} paren=${paren} brace=${brace} brack=${brack}`);
}

process.argv.slice(2).forEach(check);
