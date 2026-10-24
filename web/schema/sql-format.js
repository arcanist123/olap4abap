// Formats an SQL statement of the trace for reading (the statements ZZXXMLA1_CL_SQL ran, as the trace page and the MDX
// console download them): each clause (SELECT, FROM, each JOIN, WHERE, GROUP BY, ORDER BY, LIMIT, UNION ALL) on a
// line of its own, a list or condition that does not fit in the line broken into one item per line (a condition
// before each AND and OR), a subquery indented in its parentheses. Only white space changes, never identifiers,
// strings, comments or the case of words, so the statement means the same. Text it cannot tokenize (an unclosed
// string or comment, unbalanced parentheses) is returned as it is. The same layout as mdx-format.js.

const WIDTH = 100;

const KEYWORDS = new Set(['ALL', 'AND', 'AS', 'ASC', 'BETWEEN', 'BY', 'CASE', 'CROSS', 'CUBE', 'DESC', 'DISTINCT',
  'ELSE', 'END', 'ESCAPE', 'EXCEPT', 'EXISTS', 'FROM', 'FULL', 'GROUP', 'GROUPING', 'HAVING', 'IN', 'INNER',
  'INTERSECT', 'IS', 'JOIN', 'LEFT', 'LIKE', 'LIMIT', 'MINUS', 'NOT', 'NULL', 'NULLS', 'OFFSET', 'ON', 'OR', 'ORDER',
  'OUTER', 'OVER', 'PARTITION', 'RIGHT', 'ROLLUP', 'SELECT', 'SETS', 'THEN', 'TOP', 'UNION', 'USING', 'VALUES',
  'WHEN', 'WHERE', 'WITH']);
// keywords written like a function, without a space before their parenthesis
const CALL_KEYWORDS = new Set(['LEFT', 'RIGHT']);
const OPERATORS = ['||', '<>', '!=', '<=', '>=', '=', '<', '>', '+', '-', '*', '/'];

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
    } else if (rest.startsWith('--')) {
      const end = text.indexOf('\n', i);
      push('line-comment', end < 0 ? text.length : end);
      tokens[tokens.length - 1].text = tokens[tokens.length - 1].text.trimEnd();
    } else if (rest.startsWith('/*')) {
      const end = text.indexOf('*/', i + 2);
      if (end < 0) throw new Unformattable();
      push('comment', end + 2);
    } else if (c === "'") {
      push('string', closing(c, i + 1));
    } else if (c === '"') {
      push('word', closing(c, i + 1));
    } else if (/[0-9]/.test(c) || (c === '.' && /[0-9]/.test(text[i + 1]))) {
      push('number', i + /^(\d*\.?\d*)([eE][+-]?\d+)?/.exec(rest)[0].length);
    } else if (/[A-Za-z_$#]/.test(c)) {
      const word = /^[A-Za-z_$#][A-Za-z0-9_$#]*/.exec(rest)[0];
      const after = tokens[tokens.length - 1];
      // a name after a dot (t.ORDER) is a column, even where it spells a keyword
      const keyword = KEYWORDS.has(word.toUpperCase()) && !(after && after.text === '.');
      tokens.push({ kind: keyword ? 'keyword' : 'word', text: word, upper: word.toUpperCase() });
      i += word.length;
    } else {
      const op = OPERATORS.find((o) => rest.startsWith(o));
      push(op ? 'operator' : 'punct', i + (op ? op.length : 1));
    }
  }
  tokens.forEach((t, k) => {
    // a sign: + or - where no operand precedes it; * as COUNT(*) or SELECT * is no operator either
    const before = tokens[k - 1];
    const noOperand = !before || before.kind === 'operator' || before.kind === 'keyword'
      || ['(', ','].includes(before.text);
    t.unary = (t.text === '-' || t.text === '+') && noOperand;
    if (t.text === '*' && (noOperand || before.text === '.')) t.kind = 'word';
  });
  return tokens;
}

// The tokens as a tree: a parenthesis group is { open, close, items }.
function nest(tokens) {
  const stack = [{ items: [] }];
  for (const t of tokens) {
    if (t.text === '(') {
      stack.push({ open: t, close: null, items: [] });
    } else if (t.text === ')') {
      const group = stack.pop();
      if (!group.open) throw new Unformattable();
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
const isKeyword = (node, ...words) => node && node.kind === 'keyword' && (!words.length || words.includes(node.upper));
const hasLineComment = (nodes) => nodes.some((n) => (n.items ? hasLineComment(n.items) : n.kind === 'line-comment'));
const isQuery = (group) => group.open && isKeyword(group.items[0], 'SELECT', 'WITH');

function spaced(prev, next) {
  if (!prev) return false;
  const p = lastToken(prev);
  const n = firstToken(next);
  if (p.text === '(' || p.unary) return false;
  if ([')', ',', ';'].includes(n.text)) return false;
  if (p.text === '.' || n.text === '.') return false;
  if (n.text === '(' && (p.kind === 'word' || (p.kind === 'keyword' && CALL_KEYWORDS.has(p.upper)))) return false;
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

// Splits a condition before its top-level AND and OR (each part but the first starts with it); the AND of a BETWEEN
// stays in its part.
function splitConditions(nodes) {
  const parts = [[]];
  let between = false;
  for (const n of nodes) {
    if (isKeyword(n, 'AND', 'OR') && !between && parts[parts.length - 1].length) parts.push([]);
    else if (isKeyword(n, 'AND')) between = false;
    if (isKeyword(n, 'BETWEEN')) between = true;
    parts[parts.length - 1].push(n);
  }
  return parts;
}

// ---------------------------------------------------------------------------------------------------------- layout

class Writer {
  constructor() {
    this.lines = [''];
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

function flatText(nodes) {
  let s = '';
  let prev = null;
  for (const n of nodes) {
    if (spaced(prev, n)) s += ' ';
    s += n.items ? n.open.text + flatText(n.items) + n.close.text : n.text;
    prev = n;
  }
  return s;
}

const fits = (w, nodes, extra = 0) => !hasLineComment(nodes) && w.column + extra + flatText(nodes).length <= WIDTH;

// Writes nodes of an expression, breaking the parenthesis groups that do not fit.
function writeSeq(w, nodes, indent) {
  let prev = null;
  for (const n of nodes) {
    if (spaced(prev, n) && !w.atLineStart()) w.write(' ');
    writeNode(w, n, indent);
    prev = n;
  }
}

// Writes a condition, a line per AND and OR where it does not fit.
function writeCondition(w, nodes, indent) {
  if (fits(w, nodes)) return writeSeq(w, nodes, indent);
  splitConditions(nodes).forEach((part, k) => {
    if (k > 0) w.newline(indent);
    writeSeq(w, part, indent);
  });
}

// Writes a list, an item per line (below the line, at indent) where it does not fit.
function writeList(w, nodes, indent, extra = 0) {
  if (fits(w, nodes, extra)) {
    if (extra) w.write(' ');
    return writeSeq(w, nodes, indent);
  }
  const parts = splitCommas(nodes);
  parts.forEach((part, k) => {
    w.newline(indent);
    writeSeq(w, part, indent);
    if (k < parts.length - 1) w.write(',');
  });
}

function writeNode(w, n, indent) {
  if (n.items) {
    if (isQuery(n)) {
      w.write(n.open.text);
      w.newline(indent + 2);
      writeStatement(w, n.items, indent + 2);
      w.newline(indent);
      w.write(n.close.text);
    } else if (fits(w, [n])) {
      w.write(flatText([n]));
    } else {
      w.write(n.open.text);
      if (splitCommas(n.items).length > 1) {
        writeList(w, n.items, indent + 2);
      } else {
        w.newline(indent + 2);
        writeCondition(w, n.items, indent + 2);
      }
      w.newline(indent);
      w.write(n.close.text);
    }
  } else {
    w.write(n.text);
    if (n.kind === 'line-comment') w.newline(indent);
  }
}

// The words a clause starts with (the longest first), the joins among them
const CLAUSES = [['SELECT', 'DISTINCT'], ['SELECT', 'TOP'], ['SELECT'], ['FROM'], ['WHERE'], ['GROUP', 'BY'],
  ['HAVING'], ['ORDER', 'BY'], ['LIMIT'], ['OFFSET'], ['UNION', 'ALL'], ['UNION'], ['INTERSECT'], ['EXCEPT'],
  ['MINUS'], ['WITH'], ['LEFT', 'OUTER', 'JOIN'], ['RIGHT', 'OUTER', 'JOIN'], ['FULL', 'OUTER', 'JOIN'],
  ['INNER', 'JOIN'], ['LEFT', 'JOIN'], ['RIGHT', 'JOIN'], ['FULL', 'JOIN'], ['CROSS', 'JOIN'], ['JOIN']];
const LISTS = ['SELECT', 'GROUP BY', 'ORDER BY', 'WITH'];
const CONDITIONS = ['WHERE', 'HAVING'];

function clauseAt(nodes, k) {
  return CLAUSES.find((words) => words.every((word, j) => isKeyword(nodes[k + j], word)));
}

// Splits a statement's top-level nodes into clauses: { head: 'GROUP BY', body }; a block comment at the top level
// (the bound values ZZXXMLA1_CL_SQL appends) is a clause of its own.
function clauses(nodes) {
  const result = [];
  for (let k = 0; k < nodes.length;) {
    const words = clauseAt(nodes, k);
    if (words) {
      result.push({ head: words.join(' '), body: [] });
      k += words.length;
    } else if (nodes[k].kind === 'comment' || !result.length) {
      result.push({ head: '', body: [nodes[k]] });
      k += 1;
    } else {
      result[result.length - 1].body.push(nodes[k]);
      k += 1;
    }
  }
  return result;
}

function writeStatement(w, nodes, indent) {
  clauses(nodes).forEach(({ head, body }, k) => {
    const join = head.endsWith('JOIN');
    if (k > 0) w.newline(join ? indent + 2 : indent);
    w.write(head);
    if (!body.length) return;
    if (!head) {
      writeSeq(w, body, indent);
    } else if (LISTS.includes(head.replace(/ (DISTINCT|TOP)$/, ''))) {
      writeList(w, body, indent + 2, 1);
    } else if (CONDITIONS.includes(head)) {
      w.write(' ');
      writeCondition(w, body, indent + 2);
    } else if (join) {
      // the table on the join's line, its ON condition after it or, where it does not fit, below it
      const on = body.findIndex((n) => isKeyword(n, 'ON', 'USING'));
      w.write(' ');
      if (on < 0) return writeSeq(w, body, indent + 4);
      writeSeq(w, body.slice(0, on), indent + 4);
      if (!fits(w, body.slice(on), 1)) w.newline(indent + 4);
      else w.write(' ');
      writeSeq(w, [body[on]], indent + 4);
      w.write(' ');
      writeCondition(w, body.slice(on + 1), indent + 6);
    } else {
      // a list (FROM a, b) an item per line where it does not fit; a single item (FROM (SELECT ...) s) at the indent
      w.write(' ');
      if (splitCommas(body).length > 1) writeList(w, body, indent + 2);
      else writeSeq(w, body, indent);
    }
  });
}

/** The statement formatted; the text as it is where it cannot be tokenized. */
export function formatSql(text) {
  try {
    const w = new Writer();
    writeStatement(w, nest(tokenize(text)), 0);
    return w.text();
  } catch (e) {
    if (e instanceof Unformattable) return text;
    throw e;
  }
}
