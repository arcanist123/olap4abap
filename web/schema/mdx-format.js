// Formats an MDX statement for reading: each clause (WITH, its MEMBER and SET, SELECT, FROM, WHERE, CELL PROPERTIES)
// on a line of its own, one axis per line, a bracket group that does not fit in the line broken into one item per
// line, keywords in upper case. Only white space and the case of keywords change, never identifiers, strings or
// comments, so the statement means the same. The formula of a calculated member or named set in single quotes
// (AS '...') is formatted as well. Text it cannot tokenize (an unclosed string, unbalanced brackets) is returned as
// it is. The tokens are those of the reference's grammar, MdxParser.jj.

const WIDTH = 100;

const KEYWORDS = new Set(['AND', 'AS', 'AXIS', 'BEGIN', 'BY', 'CASE', 'CAST', 'CELL', 'CHAPTERS', 'CREATE', 'COLUMNS',
  'COMMIT', 'CUBE', 'DIMENSION', 'DRILLTHROUGH', 'ELSE', 'EMPTY', 'END', 'EXPLAIN', 'FIRSTROWSET', 'FOR', 'FROM', 'IN',
  'IS', 'MATCHES', 'MAXROWS', 'MEMBER', 'NON', 'NOT', 'NULL', 'ON', 'OR', 'PAGES', 'PLAN', 'PROPERTIES', 'REFRESH',
  'RETURN', 'ROLLBACK', 'ROWS', 'SECTIONS', 'SELECT', 'SESSION', 'SET', 'THEN', 'TRAN', 'TRANSACTION', 'UPDATE',
  'WHEN', 'WHERE', 'XOR', 'WITH', 'EXISTING']);
// keywords written like a function, without a space before their parenthesis
const CALL_KEYWORDS = new Set(['AXIS', 'CAST']);
const OPERATORS = ['||', '<>', '<=', '>=', '=', '<', '>', '+', '-', '*', '/'];
const OPEN = { '(': ')', '{': '}' };

class Unformattable extends Error {}

// ---------------------------------------------------------------------------------------------------------- tokens

function tokenize(text) {
  const tokens = [];
  let i = 0;
  const push = (kind, end) => {
    tokens.push({ kind, text: text.slice(i, end) });
    i = end;
  };
  const closing = (quote, from) => {
    // a quote is escaped by doubling it
    for (let j = from; j < text.length; j++) {
      if (text[j] === quote) {
        if (text[j + 1] === quote) j++;
        else return j + 1;
      }
    }
    throw new Unformattable();
  };
  while (i < text.length) {
    const c = text[i];
    const rest = text.slice(i);
    if (/\s/.test(c)) {
      i++;
    } else if (rest.startsWith('--') || rest.startsWith('//')) {
      const end = text.indexOf('\n', i);
      push('line-comment', end < 0 ? text.length : end);
      tokens[tokens.length - 1].text = tokens[tokens.length - 1].text.trimEnd();
    } else if (rest.startsWith('/*')) {
      const end = text.indexOf('*/', i + 2);
      if (end < 0) throw new Unformattable();
      push('comment', end + 2);
    } else if (c === '[' || (c === '&' && text[i + 1] === '[')) {
      const end = closing(']', i + (c === '&' ? 2 : 1));
      push('id', end);
    } else if (c === "'" || c === '"') {
      push('string', closing(c, i + 1));
    } else if (/[0-9]/.test(c) || (c === '.' && /[0-9]/.test(text[i + 1]))) {
      push('number', i + /^(\d*\.?\d*)([eE][+-]?\d+)?/.exec(rest)[0].length);
    } else if (/[A-Za-z_$]/.test(c)) {
      const word = /^[A-Za-z_$][A-Za-z0-9_$]*/.exec(rest)[0];
      const after = tokens[tokens.length - 1];
      // a name after a dot (.Members, .Dimension) is a function or member name, even where it spells a keyword
      const keyword = KEYWORDS.has(word.toUpperCase()) && !(after && after.text === '.');
      tokens.push({ kind: keyword ? 'keyword' : 'word', text: keyword ? word.toUpperCase() : word });
      i += word.length;
    } else {
      const op = OPERATORS.find((o) => rest.startsWith(o));
      push(op ? 'operator' : 'punct', i + (op ? op.length : 1));
    }
  }
  tokens.forEach((t, k) => {
    // a sign: + or - where no operand precedes it
    const before = tokens[k - 1];
    t.unary = (t.text === '-' || t.text === '+') && (!before || before.kind === 'operator' || before.kind === 'keyword'
      || ['(', '{', ','].includes(before.text));
  });
  return tokens;
}

// The tokens as a tree: a bracket group is { open, close, items }.
function nest(tokens) {
  const stack = [{ items: [] }];
  for (const t of tokens) {
    if (OPEN[t.text]) {
      stack.push({ open: t, close: null, items: [] });
    } else if (t.text === ')' || t.text === '}') {
      const group = stack.pop();
      if (!group.open || OPEN[group.open.text] !== t.text) throw new Unformattable();
      group.close = t;
      stack[stack.length - 1].items.push(group);
    } else {
      stack[stack.length - 1].items.push(t);
    }
  }
  if (stack.length !== 1) throw new Unformattable();
  return stack[0].items;
}

const firstToken = (node) => (node.open ? node.open : node);
const lastToken = (node) => (node.close ? node.close : node);
const isKeyword = (node, ...words) => node && node.kind === 'keyword' && (!words.length || words.includes(node.text));
const hasLineComment = (nodes) => nodes.some((n) => (n.items ? hasLineComment(n.items) : n.kind === 'line-comment'));
const isQuery = (group) => group.open && group.open.text === '(' && isKeyword(group.items[0], 'SELECT', 'WITH');

function spaced(prev, next) {
  if (!prev) return false;
  const p = lastToken(prev);
  const n = firstToken(next);
  if (p.text === '(' || p.text === '{' || p.unary) return false;
  if ([')', '}', ','].includes(n.text)) return false;
  if (['.', ':', '!'].includes(p.text) || ['.', ':', '!'].includes(n.text)) return false;
  if (n.text.startsWith('&') || p.text === '@' || n.text === '@') return false;
  if (n.text === '(' && (p.kind === 'word' || (p.kind === 'keyword' && CALL_KEYWORDS.has(p.text)))) return false;
  return true;
}

// Splits nodes at their top-level commas; the commas are dropped.
function splitCommas(nodes) {
  const parts = [[]];
  for (const n of nodes) {
    if (n.text === ',') parts.push([]);
    else parts[parts.length - 1].push(n);
  }
  return parts;
}

// ---------------------------------------------------------------------------------------------------------- layout

class Writer {
  constructor() {
    this.lines = [''];
    this.escape = (s) => s;
  }
  get column() {
    return this.lines[this.lines.length - 1].length;
  }
  write(s) {
    this.lines[this.lines.length - 1] += s;
  }
  newline(indent) {
    // a line still empty (after a line comment) takes the new indent instead of staying blank
    if (this.atLineStart() && this.lines.length > 1) this.lines[this.lines.length - 1] = ' '.repeat(indent);
    else this.lines.push(' '.repeat(indent));
  }
  atLineStart() {
    return this.lines[this.lines.length - 1].trim() === '';
  }
  text() {
    return this.lines.map((l) => l.trimEnd()).join('\n').trim();
  }
}

function flatText(nodes, escape) {
  let s = '';
  let prev = null;
  for (const n of nodes) {
    if (spaced(prev, n)) s += ' ';
    s += n.items ? escape(n.open.text) + flatText(n.items, escape) + escape(n.close.text) : escape(n.text);
    prev = n;
  }
  return s;
}

// Writes nodes of an expression, breaking the bracket groups that do not fit.
function writeSeq(w, nodes, indent) {
  let prev = null;
  for (const n of nodes) {
    if (spaced(prev, n) && !w.atLineStart()) w.write(' ');
    writeNode(w, n, indent, prev);
    prev = n;
  }
}

function writeNode(w, n, indent, prev) {
  if (n.items) {
    if (isQuery(n)) {
      w.write(w.escape(n.open.text));
      w.newline(indent + 2);
      writeQuery(w, n.items, indent + 2);
      w.newline(indent);
      w.write(w.escape(n.close.text));
    } else if (!hasLineComment(n.items) && w.column + flatText([n], w.escape).length <= WIDTH) {
      w.write(flatText([n], w.escape));
    } else {
      w.write(w.escape(n.open.text));
      const parts = splitCommas(n.items);
      parts.forEach((part, k) => {
        w.newline(indent + 2);
        writeSeq(w, part, indent + 2);
        if (k < parts.length - 1) w.write(',');
      });
      w.newline(indent);
      w.write(w.escape(n.close.text));
    }
  } else if (n.kind === 'string' && n.text[0] === "'" && isKeyword(prev, 'AS')) {
    writeFormula(w, n, indent);
  } else {
    w.write(w.escape(n.text));
    if (n.kind === 'line-comment') w.newline(indent);
  }
}

// A formula in single quotes: its text formatted as an expression, its quotes doubled again.
function writeFormula(w, n, indent) {
  let nodes;
  try {
    nodes = nest(tokenize(n.text.slice(1, -1).replace(/''/g, "'")));
  } catch (e) {
    if (!(e instanceof Unformattable)) throw e;
    return w.write(n.text);
  }
  const outer = w.escape;
  w.escape = (s) => outer(s.replace(/'/g, "''"));
  w.write(outer("'"));
  writeSeq(w, nodes, indent);
  w.write(outer("'"));
  w.escape = outer;
}

// Splits a statement's top-level nodes into clauses, each starting at one of the words.
function clauses(nodes, startsClause) {
  const result = [];
  nodes.forEach((n, k) => {
    if (!result.length || startsClause(n, nodes[k + 1], nodes[k - 1])) result.push([]);
    result[result.length - 1].push(n);
  });
  return result;
}

const TOP_CLAUSES = ['WITH', 'SELECT', 'FROM', 'WHERE', 'DRILLTHROUGH', 'RETURN', 'EXPLAIN'];

function writeQuery(w, nodes, indent) {
  const top = clauses(nodes, (n, next) => isKeyword(n, ...TOP_CLAUSES)
    || (isKeyword(n, 'CELL') && isKeyword(next, 'PROPERTIES')));
  top.forEach((clause, k) => {
    if (k > 0) w.newline(indent);
    const head = clause[0];
    if (isKeyword(head, 'WITH')) {
      w.write('WITH');
      // a calculated member, named set or cell calculation each on a line, its properties below it
      for (const definition of clauses(clause.slice(1), (n) => isKeyword(n, 'MEMBER', 'SET', 'CELL'))) {
        w.newline(indent + 2);
        const parts = splitCommas(definition);
        parts.forEach((part, p) => {
          if (p > 0) {
            w.write(',');
            w.newline(indent + 4);
          }
          writeSeq(w, part, indent + 4);
        });
      }
    } else if (isKeyword(head, 'SELECT')) {
      const axes = splitCommas(clause.slice(1));
      w.write('SELECT');
      if (axes.length === 1 && axes[0].length === 0) return;
      if (axes.length === 1 && !hasLineComment(axes[0])
        && w.column + 1 + flatText(axes[0], w.escape).length <= WIDTH) {
        w.write(' ');
        writeSeq(w, axes[0], indent + 2);
        return;
      }
      axes.forEach((axis, a) => {
        w.newline(indent + 2);
        writeSeq(w, axis, indent + 2);
        if (a < axes.length - 1) w.write(',');
      });
    } else {
      writeSeq(w, clause, indent);
    }
  });
}

/** The statement formatted; the text as it is where it cannot be tokenized. */
export function formatMdx(text) {
  try {
    const w = new Writer();
    writeQuery(w, nest(tokenize(text)), 0);
    return w.text();
  } catch (e) {
    if (e instanceof Unformattable) return text;
    throw e;
  }
}
