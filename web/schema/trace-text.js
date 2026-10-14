// What the trace page (trace.js) and the MDX console (console.js) show of a call: its XML indented, its SQL
// statements as a script, and Copy that works on plain HTTP too.

const ms = (us) => (us / 1000).toFixed(1);

// the SQL statements of a call as one script: each statement after a comment with its number, rows and time
export const sqlScript = (statements) => statements.map((s, i) => `-- ${i + 1}: ${s.error ? `failed: ${s.error.replace(/\s+/g, ' ')}`
  : `${s.rows} ${s.rows === 1 ? 'row' : 'rows'}`}, ${ms(s.us)} ms\n${s.sql.trim()};`).join('\n\n');

// XML indented for reading: a line per tag, an element of text only (or none) on one line. The tags and text are
// kept as sent (no parser), so it also indents the beginning of a response cut off for showing, and it is quick on
// megabytes.
export function prettyXml(text) {
  if (!text) return text;
  const tokens = text.split(/(<!--[\s\S]*?-->|<!\[CDATA\[[\s\S]*?\]\]>|<[^>]*>)/);
  const out = [];
  let depth = 0;
  const isOpen = (t) => t.startsWith('<') && !t.startsWith('</') && !t.startsWith('<?') && !t.startsWith('<!') && !t.endsWith('/>');
  for (let i = 0; i < tokens.length; i++) {
    const token = tokens[i];
    if (!token || !token.trim()) continue;
    const pad = '  '.repeat(depth);
    if (!token.startsWith('<')) {
      out.push(pad + token.trim());
    } else if (token.startsWith('</')) {
      depth = Math.max(0, depth - 1);
      out.push('  '.repeat(depth) + token);
    } else if (isOpen(token)) {
      // <a>text</a> and <a></a> on one line
      const next = tokens[i + 1] ?? '';
      if (!next.includes('<') && tokens[i + 2]?.startsWith('</')) {
        out.push(pad + token + next + tokens[i + 2]);
        i += 2;
      } else {
        out.push(pad + token);
        depth += 1;
      }
    } else {
      out.push(pad + token);
    }
  }
  return out.join('\n');
}

// navigator.clipboard exists only on HTTPS and localhost; the endpoint is often plain HTTP, so a hidden textarea and
// execCommand('copy') are the fallback
export async function copyText(text) {
  try {
    if (navigator.clipboard && window.isSecureContext) {
      await navigator.clipboard.writeText(text);
      return true;
    }
  } catch { /* the fallback below */ }
  const area = Object.assign(document.createElement('textarea'), { value: text, readOnly: true });
  area.style.cssText = 'position:fixed;top:0;left:0;opacity:0';
  document.body.appendChild(area);
  area.select();
  let copied = false;
  try { copied = document.execCommand('copy'); } catch { copied = false; }
  area.remove();
  return copied;
}

export const download = (text, name, type = 'text/xml') => {
  const url = URL.createObjectURL(new Blob([text], { type }));
  const a = Object.assign(document.createElement('a'), { href: url, download: name });
  a.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
};
