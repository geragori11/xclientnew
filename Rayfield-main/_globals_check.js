// Static sanity check for a Lua file: report identifiers that are *read* but are
// neither declared as a local/parameter in an enclosing scope nor a known global.
// Baseline output is treated as the "known globals" set, so comparing an edited
// file against the original highlights only what the edit introduced.
//
//   node _globals_check.js baseline.lua edited.lua
const fs = require("fs");

const KEYWORDS = new Set([
  "and", "break", "do", "else", "elseif", "end", "false", "for", "function", "if",
  "in", "local", "nil", "not", "or", "repeat", "return", "then", "true", "until",
  "while", "goto",
]);

function tokenize(src) {
  const tokens = [];
  let i = 0;
  let line = 1;
  const n = src.length;
  const bump = (text) => { for (const ch of text) if (ch === "\n") line++; };

  function longBracket(start) {
    let j = start + 1;
    let eq = 0;
    while (src[j] === "=") { eq++; j++; }
    if (src[j] !== "[") return -1;
    const close = "]" + "=".repeat(eq) + "]";
    const end = src.indexOf(close, j + 1);
    return end === -1 ? n : end + close.length;
  }

  while (i < n) {
    const c = src[i];
    if (c === "\n") { line++; i++; continue; }
    if (c === " " || c === "\t" || c === "\r") { i++; continue; }
    if (c === "-" && src[i + 1] === "-") {
      const long = longBracket(i + 2);
      if (long !== -1) { bump(src.slice(i, long)); i = long; continue; }
      let j = i;
      while (j < n && src[j] !== "\n") j++;
      bump(src.slice(i, j));
      i = j;
      continue;
    }
    if (c === "[") {
      const long = longBracket(i);
      if (long !== -1) { bump(src.slice(i, long)); i = long; continue; }
    }
    if (c === '"' || c === "'") {
      let j = i + 1;
      while (j < n) {
        if (src[j] === "\\") { j += 2; continue; }
        if (src[j] === c) { j++; break; }
        if (src[j] === "\n") break;
        j++;
      }
      bump(src.slice(i, j));
      i = j;
      continue;
    }
    if (/[A-Za-z_]/.test(c)) {
      let j = i;
      while (j < n && /[A-Za-z0-9_]/.test(src[j])) j++;
      tokens.push({ type: "id", value: src.slice(i, j), line });
      i = j;
      continue;
    }
    if (/[0-9]/.test(c) || (c === "." && /[0-9]/.test(src[i + 1]))) {
      let j = i;
      while (j < n && /[0-9a-fA-FxX.]/.test(src[j])) j++;
      tokens.push({ type: "num", value: src.slice(i, j), line });
      i = j;
      continue;
    }
    if ((c === "." && src[i + 1] === "." && src[i + 2] === ".") || (c === "=" && src[i + 1] === "=") ||
        (c === "~" && src[i + 1] === "=") || (c === "<" && src[i + 1] === "=") ||
        (c === ">" && src[i + 1] === "=") || (c === "." && src[i + 1] === ".")) {
      const len = (c === "." && src[i + 2] === ".") ? 3 : 2;
      tokens.push({ type: "sym", value: src.substr(i, len), line });
      i += len;
      continue;
    }
    tokens.push({ type: "sym", value: c, line });
    i++;
  }
  return tokens;
}

function check(path) {
  const tokens = tokenize(fs.readFileSync(path, "utf8"));
  const scopes = [{ names: new Set() }];
  const used = new Map();
  const declaredIn = (name) => scopes.some((s) => s.names.has(name));
  const declare = (name) => scopes[scopes.length - 1].names.add(name);
  const note = (name, line) => { if (!used.has(name)) used.set(name, line); };

  // k is the index of "(" ; declares every identifier inside it as a parameter
  function readParams(k) {
    let depth = 1;
    let j = k + 1;
    while (j < tokens.length && depth > 0) {
      const t = tokens[j];
      if (t.type === "sym" && t.value === "(") depth++;
      else if (t.type === "sym" && t.value === ")") { depth--; if (depth === 0) break; }
      else if (t.type === "id" && !KEYWORDS.has(t.value)) declare(t.value);
      j++;
    }
    return j;
  }

  let i = 0;
  while (i < tokens.length) {
    const t = tokens[i];
    if (t.type !== "id") { i++; continue; }
    const w = t.value;

    if (w === "local") {
      let j = i + 1;
      const names = [];
      while (j < tokens.length && tokens[j].type === "id" && !KEYWORDS.has(tokens[j].value)) {
        names.push(tokens[j].value);
        j++;
        if (tokens[j] && tokens[j].value === ",") { j++; continue; }
        break;
      }
      for (const nm of names) declare(nm);
      if (tokens[j] && tokens[j].value === "function") {
        // local function NAME(params)
        let k = j + 1;
        if (tokens[k] && tokens[k].type === "id" && !KEYWORDS.has(tokens[k].value)) {
          declare(tokens[k].value);
          k++;
        }
        scopes.push({ names: new Set() });
        while (tokens[k] && tokens[k].value !== "(") k++;
        i = tokens[k] ? readParams(k) : j;
      } else {
        i = j;
      }
      continue;
    }
    if (w === "function") {
      scopes.push({ names: new Set() });
      let k = i + 1;
      if (tokens[k] && tokens[k].type === "id" && !KEYWORDS.has(tokens[k].value)) {
        const nameTok = tokens[k];
        const after = tokens[k + 1];
        if (after && (after.value === "." || after.value === ":")) {
          while (tokens[k] && (tokens[k].value === "." || tokens[k].value === ":")) k += 2;
        } else if (after && after.value === "(") {
          if (!declaredIn(nameTok.value)) note(nameTok.value, nameTok.line); // global function
          declare(nameTok.value);
          k++;
        }
      }
      while (tokens[k] && tokens[k].value !== "(") k++;
      i = tokens[k] ? readParams(k) : i + 1;
      continue;
    }
    if (w === "if" || w === "do" || w === "while" || w === "repeat") {
      scopes.push({ names: new Set() });
      i++;
      continue;
    }
    if (w === "for") {
      scopes.push({ names: new Set() });
      let j = i + 1;
      while (tokens[j] && tokens[j].value !== "=" && tokens[j].value !== "in") {
        if (tokens[j].type === "id" && !KEYWORDS.has(tokens[j].value)) declare(tokens[j].value);
        j++;
      }
      i = j;
      continue;
    }
    if (w === "end" || w === "until") {
      if (scopes.length > 1) scopes.pop();
      i++;
      continue;
    }
    if (KEYWORDS.has(w)) { i++; continue; }

    const prev = tokens[i - 1];
    const next = tokens[i + 1];
    const asField = prev && prev.type === "sym" && (prev.value === "." || prev.value === ":");
    const asKey = next && next.type === "sym" && next.value === "=";
    const isLabel = prev && prev.value === "::";
    if (!asField && !asKey && !isLabel && !declaredIn(w)) note(w, t.line);
    i++;
  }
  return used;
}

const [baseline, edited] = process.argv.slice(2);
const a = check(baseline);
const b = check(edited);
const onlyEdited = [...b.keys()].filter((k) => !a.has(k)).sort();
const both = [...b.keys()].filter((k) => a.has(k)).sort();
const gone = [...a.keys()].filter((k) => !b.has(k)).sort();
console.log("baseline:", baseline, "-> unbound reads:", a.size);
console.log("edited  :", edited, "-> unbound reads:", b.size);
console.log("\nNEW in edited (review these):");
console.log(onlyEdited.length ? onlyEdited.map((k) => `  ${k}  (first line ${b.get(k)})`).join("\n") : "  (none)");
console.log("\nOnly in baseline (reads my edit removed):");
console.log("  " + (gone.join(", ") || "(none)"));
console.log("\nPresent in both (pre-existing globals/builtins):");
console.log("  " + both.join(", "));
