// The query plan and the SQL statements of a traced call, shown alike by the MDX console (console.js) and the trace
// page (trace.js). A call is the traced call as GET api/trace/entry gives it (ZZXXMLA1_CL_TRACE): id, mdx, runtimeMs,
// sqlCount, sqlMs, sql (each statement with its rows, time, error, phase and node) and explain (ZZXXMLA1_CL_MDX_EXPLAIN:
// the resolved tree with the planner's marks; null for a call that is no Execute or failed before it was resolved);
// the console adds browserMs.
import { html, useState, useEffect } from './vendor/htm-preact-standalone.mjs';
import { sqlScript, copyText, download } from './trace-text.js';

export const msText = (ms) => `${Math.round(ms).toLocaleString()} ms`;
export const statementCount = (n) => `${n.toLocaleString()} SQL ${n === 1 ? 'statement' : 'statements'}`;

// Copy and its feedback for a moment
export function useCopied() {
  const [copied, setCopied] = useState('');
  useEffect(() => {
    if (!copied) return undefined;
    const timer = setTimeout(() => setCopied(''), 1500);
    return () => clearTimeout(timer);
  }, [copied]);
  const copy = (text) => copyText(text).then((ok) => setCopied(ok ? 'Copied' : 'Copy failed: select the text and press Ctrl+C'));
  const status = copied && html`<span class=${`status ${copied === 'Copied' ? 'ok' : 'err'}`} role="status">${copied}</span>`;
  return [copy, status];
}

// What the engine did when a statement ran (ZZXXMLA1_CL_MDX_ENGINE's phases, ZZXXMLA1_CL_SQL=>log_phase)
const PHASE_TEXT = {
  '': 'before the query: the schema and its metadata',
  Resolve: 'resolving the names of the query: the columns and the members it names',
  Prepare: 'the members of hierarchies without an All member',
  Slicer: 'the slicer (WHERE)',
  Axes: 'the cells the axes needed, read in one batch',
  'NON EMPTY': 'the NON EMPTY filter of the axes',
  Cells: 'the cells of the answer',
  Finish: 'the details of the axes\' members: children counts',
  Drillthrough: 'the fact rows of the drill-through',
};
const phaseName = (p) => p || 'Before';
const phaseText = (p) => PHASE_TEXT[p] ?? (/^Axis\d+$/.test(p) ? `axis ${p.slice(4)}: its sets and members` : p);
const MARK_TEXT = {
  STATIC: 'static: answered by the schema and member reads',
  RELATIONAL: 'relational: answered by grouped SQL over the facts',
  COMPUTED: 'computed: evaluated by the evaluator, cell by cell',
};

// the explanation's nodes by id, each with its parent's id (0 for the top of a part) and its part
function explainIndex(explain) {
  const nodes = new Map();
  const visit = (node, parent, part) => {
    if (!node || node.ref) return;
    nodes.set(node.id, { node, parent, part });
    node.args.forEach((a) => visit(a, node.id, part));
  };
  const visitPart = (part) => {
    visit(part.node, 0, part);
    (part.children || []).forEach(visitPart);
  };
  (explain?.parts || []).forEach(visitPart);
  return nodes;
}

// whether a statement was read by the node or one of its arguments
const readBelow = (statement, id, nodes) => {
  for (let n = statement.node; n; n = nodes.get(n)?.parent) if (n === id) return true;
  return false;
};

// the statements and their time per node (own: read by it; all: by it or its arguments) and per phase
function sqlStats(statements, nodes) {
  const add = (map, key, s) => {
    const v = map.get(key) || { count: 0, us: 0 };
    v.count += 1;
    v.us += s.us;
    map.set(key, v);
  };
  const own = new Map();
  const all = new Map();
  const phases = new Map();
  for (const s of statements) {
    add(phases, s.phase || '', s);
    if (!s.node) continue;
    add(own, s.node, s);
    for (let n = s.node; n; n = nodes.get(n)?.parent) add(all, n, s);
  }
  return { own, all, phases };
}

const serverTime = (call) => `${msText(call.runtimeMs)} on the server`
  + (call.browserMs != null ? ` (${msText(call.browserMs)} in the browser)` : '');

const Mark = ({ mark }) => mark && html`<span class=${`mark ${mark.toLowerCase()}`} title=${MARK_TEXT[mark] || mark}>${mark.toLowerCase()}</span>`;
const SqlBadge = ({ stat, title }) => stat && html`<span class="sql-badge" title=${title}>${stat.count} SQL · ${msText(stat.us / 1000)}</span>`;

// statements with their time (a bar shows its share of the slowest), rows, phase, element and error
function SqlTable({ statements, slowest, nodes, onNode, onPhase }) {
  if (!statements.length) return html`<div class="result-msg muted">No SQL statement.</div>`;
  return html`<table class="grid sql-list">
    <thead><tr><th class="num">#</th><th class="num">ms</th><th class="num">Rows</th><th>Phase</th><th>Element</th><th>Statement</th></tr></thead>
    <tbody>${statements.map((s) => {
      const element = nodes.get(s.node)?.node;
      return html`<tr>
        <td class="num muted">${s.n}</td>
        <td class="num" style=${`background: linear-gradient(to left, var(--accent-soft) ${(100 * s.us) / slowest}%, transparent 0)`}>${(s.us / 1000).toFixed(1)}</td>
        <td class="num">${s.error ? '' : s.rows.toLocaleString()}</td>
        <td><button class="link small" title=${phaseText(s.phase || '')} onClick=${() => onPhase(s.phase || '')}>${phaseName(s.phase)}</button></td>
        <td>${element ? html`<button class="link small mono" title=${`${element.mdx}\n– show it in the query plan`}
          onClick=${() => onNode(s.node)}>${element.label}</button>` : html`<span class="muted small">–</span>`}</td>
        <td><pre class="sql">${s.sql.trim()}</pre>${s.error && html`<div class="notice err small">${s.error}</div>`}</td>
      </tr>`;
    })}</tbody>
  </table>`;
}

// The SQL statements a call ran: in the order they ran or the slowest first, each with its phase and the element of
// the query that read it (a click shows it in the query plan: onNode, onPhase). children: more buttons for the bar.
export function SqlView({ call, onNode, onPhase, children }) {
  const [order, setOrder] = useState('ran');
  const [copy, copied] = useCopied();
  const nodes = explainIndex(call.explain);
  const statements = call.sql.map((s, i) => ({ ...s, n: i + 1 }));
  if (order === 'slowest') statements.sort((a, b) => b.us - a.us);
  return html`
    <div class="result-bar">
      <span class="muted small">${`${statementCount(call.sqlCount)}, ${msText(call.sqlMs)} of ${serverTime(call)}`}</span>
      <span class="spacer"></span>
      <div class="segmented" role="group" aria-label="Order">
        <button class=${order === 'ran' ? 'active' : ''} onClick=${() => setOrder('ran')}>As they ran</button>
        <button class=${order === 'slowest' ? 'active' : ''} onClick=${() => setOrder('slowest')}>Slowest first</button>
      </div>
      ${children}
      ${copied}
      <button onClick=${() => copy(sqlScript(call.sql))} disabled=${!call.sql.length} title="Copy the statements as one script">Copy</button>
      <button onClick=${() => download(sqlScript(call.sql), `${call.id}.sql`, 'text/plain')} disabled=${!call.sql.length}>Download</button>
    </div>
    ${call.sql.length < call.sqlCount && html`<div class="notice warn">${call.sql.length
      ? `The first ${call.sql.length.toLocaleString()} of ${call.sqlCount.toLocaleString()} statements are kept.`
      : 'The statements were not recorded: the call was traced before the trace kept them.'}</div>`}
    ${call.sql.some((s) => s.error) && html`<div class="notice err">A statement failed; its error is below it.</div>`}
    <div class="result-table">
      <${SqlTable} statements=${statements} slowest=${Math.max(1, ...call.sql.map((s) => s.us))} nodes=${nodes}
        onNode=${onNode} onPhase=${onPhase} />
    </div>`;
}

// The query plan as text to read or pass on: the statement, the plan's marks, the server's time, the phases, the tree
// (each element with its type, mark and the SQL statements it and its arguments read; #n numbers the elements) and
// the SQL statements, each with its phase and element
export function planText(call) {
  const { explain } = call;
  const nodes = explainIndex(explain);
  const stats = sqlStats(call.sql, nodes);
  const sql = (stat) => (stat ? `  [${stat.count} SQL, ${msText(stat.us / 1000)}]` : '');
  const lines = [`Query plan of ${explain.cube} (olap4abap, ${new Date().toLocaleString()})`, '', call.mdx || '', '',
    `Plan: query ${explain.plan.query.toLowerCase()}${explain.plan.slicer ? `, slicer ${explain.plan.slicer.toLowerCase()}` : ''}`
      + explain.plan.axes.map((m, i) => `, axis ${i} ${m.toLowerCase()}`).join('') + `, cells ${explain.plan.cells.toLowerCase()}`,
    `Time: ${statementCount(call.sqlCount)} ${msText(call.sqlMs)} of ${serverTime(call)}`,
    '', 'Phases'];
  for (const [phase, stat] of stats.phases) lines.push(`  ${phaseName(phase).padEnd(12)}${sql(stat).trim().padEnd(20)}  ${phaseText(phase)}`);
  const walk = (node, depth) => {
    const pad = '  '.repeat(depth);
    if (node.ref) {
      lines.push(`${pad}${node.label}  (named set #${node.ref}, above)`);
      return;
    }
    lines.push(`${pad}#${node.id} ${node.label}  ${node.type || ''}  ${(node.mark || '').toLowerCase()}${sql(stats.all.get(node.id))}`);
    node.args.forEach((a) => walk(a, depth + 1));
  };
  const walkPart = (part, depth) => {
    lines.push('', `${'  '.repeat(depth)}${part.label}`);
    if (part.node) walk(part.node, depth + 1);
    (part.children || []).forEach((c) => walkPart(c, depth + 1));
  };
  explain.parts.forEach((part) => walkPart(part, 0));
  lines.push('', 'SQL statements', '');
  call.sql.forEach((s, i) => {
    const element = nodes.get(s.node)?.node;
    lines.push(`-- ${i + 1}: ${phaseName(s.phase)}${element ? `, #${element.id} ${element.label}` : ''}, `
      + `${s.error ? `failed: ${s.error.replace(/\s+/g, ' ')}` : `${s.rows} ${s.rows === 1 ? 'row' : 'rows'}`}, ${(s.us / 1000).toFixed(1)} ms`,
    `${s.sql.trim()};`, '');
  });
  return lines.join('\n');
}

// the query plan as data: the statement, the explanation and the statements
export const planJson = (call) => JSON.stringify({
  mdx: call.mdx, traceId: call.id, runtimeMs: call.runtimeMs, sqlCount: call.sqlCount, sqlMs: call.sqlMs,
  browserMs: call.browserMs != null ? Math.round(call.browserMs) : undefined, explain: call.explain, sql: call.sql,
}, null, 2);

// a node of the resolved tree: what it is, its type, its mark of the plan and the SQL it and its arguments read
function PlanNode({ node, depth, stats, selection, onSelect, nodes }) {
  const [open, setOpen] = useState(() => !node.args || node.args.length <= 12);
  if (node.ref) {
    const target = nodes.get(node.ref)?.node;
    return html`<div class="plan-node ref" style=${`padding-left: ${8 + depth * 16}px`}>
      <span class="twisty"></span><button class="link small" onClick=${() => onSelect({ node: node.ref })}
        title="The named set, explained where it first appears">${node.label} ↑</button>
      ${target && html`<${Mark} mark=${target.mark} />`}
    </div>`;
  }
  const own = stats.own.get(node.id);
  const all = stats.all.get(node.id);
  const selected = selection?.node === node.id;
  return html`
    <div class=${`plan-node${selected ? ' selected' : ''}`} style=${`padding-left: ${8 + depth * 16}px`}
      onClick=${() => onSelect({ node: node.id })} title=${node.mdx}>
      <span class="twisty" onClick=${(e) => { e.stopPropagation(); setOpen(!open); }}>${node.args.length ? (open ? '▾' : '▸') : ''}</span>
      <span class="plan-label mono">${node.label}</span>
      ${node.type && html`<span class="muted small">${node.type}</span>`}
      <${Mark} mark=${node.mark} />
      <span class="spacer"></span>
      ${all && html`<${SqlBadge} stat=${all} title=${own && own.count === all.count ? 'SQL statements it read'
        : `SQL statements it and its arguments read; itself: ${own ? `${own.count}, ${msText(own.us / 1000)}` : 'none'}`} />`}
    </div>
    ${open && node.args.map((a) => html`<${PlanNode} node=${a} depth=${depth + 1} stats=${stats} selection=${selection}
      onSelect=${onSelect} nodes=${nodes} />`)}`;
}

function PlanPart({ part, depth, ...rest }) {
  return html`
    <div class="plan-part" style=${`padding-left: ${8 + depth * 16}px`}>${part.label}</div>
    ${part.node && html`<${PlanNode} node=${part.node} depth=${depth + 1} ...${rest} />`}
    ${(part.children || []).map((c) => html`<${PlanPart} part=${c} depth=${depth + 1} ...${rest} />`)}`;
}

// The query plan: the resolved tree of the formulas, subselects, slicer and axes with each element's mark of the plan
// and the SQL statements it read; the phases of the engine with theirs. A click on an element or a phase lists its
// statements next to the tree. selection: the element ({node}) or phase ({phase}) selected, null for all.
export function PlanView({ call, selection, setSelection }) {
  const [below, setBelow] = useState(true);
  const { explain } = call;
  if (!explain) {
    return html`<div class="result-msg muted">No query plan: the call is no Execute of a query, or the statement failed
      before it was resolved${call.sql.length ? ' (its SQL statements are on the SQL statements tab)' : ''}.</div>`;
  }
  const nodes = explainIndex(explain);
  const stats = sqlStats(call.sql, nodes);
  const numbered = call.sql.map((s, i) => ({ ...s, n: i + 1 }));
  const slowest = Math.max(1, ...call.sql.map((s) => s.us));
  const selectedNode = selection?.node != null ? nodes.get(selection.node)?.node : null;
  const shown = selectedNode ? numbered.filter((s) => (below ? readBelow(s, selectedNode.id, nodes) : s.node === selectedNode.id))
    : selection?.phase != null ? numbered.filter((s) => (s.phase || '') === selection.phase) : numbered;
  const phases = [...stats.phases.keys()];
  const onNode = (id) => setSelection({ node: id });
  const onPhase = (phase) => setSelection({ phase });
  const name = `query-plan-${explain.cube}-${call.id.slice(0, 8)}`;
  return html`
    <div class="result-bar">
      <span class="muted small">Click an element or a phase to list its SQL statements.</span>
      <span class="spacer"></span>
      <span class="muted small">Download</span>
      <div class="segmented" role="group" aria-label="Download the query plan">
        <button onClick=${() => download(planText(call), `${name}.txt`, 'text/plain')}
          title="The statement, the plan, the tree with each element's SQL and the SQL statements, as text">Text</button>
        <button onClick=${() => download(planJson(call), `${name}.json`, 'application/json')}
          title="The statement, the explanation and the SQL statements as JSON">JSON</button>
      </div>
    </div>
    <div class="plan">
    <div class="plan-tree">
      <div class="plan-summary small">
        <span class="muted">Plan of ${explain.cube}:</span> query <${Mark} mark=${explain.plan.query} />
        ${explain.plan.slicer && html`slicer <${Mark} mark=${explain.plan.slicer} />`}
        ${explain.plan.axes.map((m, i) => html`axis ${i} <${Mark} mark=${m} /> `)}
        cells <${Mark} mark=${explain.plan.cells} />
      </div>
      <div class="plan-part">Phases</div>
      ${phases.map((p) => html`<div class=${`plan-node${selection?.phase === p ? ' selected' : ''}`} style="padding-left: 24px"
        onClick=${() => onPhase(p)} title=${phaseText(p)}>
        <span class="plan-label phase">${phaseName(p)}</span><span class="muted small plan-desc">${phaseText(p)}</span>
        <span class="spacer"></span><${SqlBadge} stat=${stats.phases.get(p)} title="SQL statements of the phase" />
      </div>`)}
      ${explain.parts.map((part) => html`<${PlanPart} part=${part} depth=${0} stats=${stats} selection=${selection}
        onSelect=${setSelection} nodes=${nodes} />`)}
    </div>
    <div class="plan-sql">
      <div class="result-bar">
        <span class="small">${selectedNode ? html`<span class="mono">${selectedNode.label}</span> <${Mark} mark=${selectedNode.mark} />`
          : selection?.phase != null ? html`Phase <strong>${phaseName(selection.phase)}</strong>: ${phaseText(selection.phase)}`
          : 'All statements; click an element or a phase'}</span>
        <span class="spacer"></span>
        ${selectedNode && html`<label class="inline small"><input type="checkbox" checked=${below}
          onChange=${(e) => setBelow(e.target.checked)} /> with its arguments</label>`}
        ${selection && html`<button onClick=${() => setSelection(null)}>All</button>`}
      </div>
      ${selectedNode && html`<pre class="sql plan-mdx" title="The element as MDX">${selectedNode.mdx}</pre>`}
      <div class="result-table">
        <${SqlTable} statements=${shown} slowest=${slowest} nodes=${nodes} onNode=${onNode} onPhase=${onPhase} />
      </div>
    </div>
  </div>`;
}
