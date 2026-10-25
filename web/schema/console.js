// The MDX console: runs MDX statements against the XMLA endpoint this app is served by (ZZXXMLA1_MAIN_ENDPOINT, POST)
// and shows the answer. A result of up to two axes is a grid (Axis0 the columns, Axis1 the rows), one of more axes
// a flat table with a column per hierarchy of every axis and one row per cell. The cube browser on the left lists
// the catalog's cubes, measures, hierarchies and levels from the schema rowsets; a click inserts a unique name.
// Format lays the statement out for reading (mdx-format.js). Next to the result are the SOAP request and response of
// the Execute and, while Trace is on, its query plan (the resolved tree with the planner's marks,
// ZZXXMLA1_CL_MDX_EXPLAIN) and the SQL statements it ran, each with the phase and the element of the query that read
// it: the request asks the endpoint to trace the call
// (header X-olap4abap-Trace), the answer names the traced call (X-olap4abap-Trace-Id) and its statements are read from
// the trace (GET api/trace/entry, ZZXXMLA1_CL_TRACE), where the call is listed too. The trace page's "Open in MDX
// Console" hands over a traced call: its statement and catalog, and the call as the result, as it was answered.
// The mode "BW's MDX" sends the statement, in BW's names, to the endpoint for BW's MDX instead (POST bw/check with a
// user and a key date, ZZXXMLA1_CL_BW_MDX_API): the answer is the check's status and the statement in olap4abap's
// names, never data; traced as an Execute is, so its SQL statements are shown too.
// No build step: Preact with htm, vendored as one ES module; this file is what the server serves.
import { html, render, useState, useEffect, useRef, useCallback, useMemo } from './vendor/htm-preact-standalone.mjs';
import { formatMdx } from './mdx-format.js';
import { prettyXml, download } from './trace-text.js';
import { msText, statementCount, useCopied, SqlView, PlanView } from './query-plan.js';

// beyond these the browser gets slow; the rest of the answer is counted, not shown
const MAX_GRID_ROWS = 2000;
const MAX_GRID_COLUMNS = 500;
const MAX_FLAT_ROWS = 10000;
const MAX_SHOWN_CHARS = 1000000;  // of the SOAP response and request
const HISTORY_SIZE = 50;

// ---------------------------------------------------------------------------------------------------------- XMLA

const client = new URLSearchParams(location.search).get('sap-client');
// the app's folder is /schema/ below the ICF node, the node itself is the XMLA endpoint
const endpoint = location.pathname.replace(/\/schema(\/.*)?$/, '') || '/';

const escapeXml = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const propertyList = (props) => Object.entries(props).filter(([, v]) => v)
  .map(([k, v]) => `<${k}>${escapeXml(v)}</${k}>`).join('');
const envelope = (body) => '<SOAP-ENV:Envelope xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/">'
  + `<SOAP-ENV:Body>${body}</SOAP-ENV:Body></SOAP-ENV:Envelope>`;

// the elements below el with this local name, in any namespace
const all = (el, name) => (el ? [...el.getElementsByTagNameNS('*', name)] : []);
const first = (el, name) => all(el, name)[0];
const children = (el, name) => (el ? [...el.children].filter((c) => c.localName === name) : []);
const text = (el, name) => first(el, name)?.textContent ?? '';

// traced: the endpoint traces the call whatever the user's trace; the answer (and the error) has its traceId
async function post(action, body, traced = false) {
  const started = performance.now();
  const request = envelope(body);
  const response = await fetch(endpoint + (client ? `?sap-client=${encodeURIComponent(client)}` : ''), {
    method: 'POST',
    headers: { 'Content-Type': 'text/xml; charset=utf-8', SOAPAction: `"urn:schemas-microsoft-com:xml-analysis:${action}"`,
      ...(traced ? { 'X-olap4abap-Trace': 'true' } : {}) },
    body: request,
  });
  const raw = await response.text();
  const ms = performance.now() - started;
  const exchange = { request, raw, ms, traceId: response.headers.get('X-olap4abap-Trace-Id') || '' };
  return { doc: answerOf(raw, `${response.status} ${response.statusText}`, exchange), ...exchange };
}

// the SOAP answer as a document; one that is no XML or a fault is an error with the exchange
function answerOf(raw, status, exchange) {
  const doc = new DOMParser().parseFromString(raw, 'application/xml');
  if (doc.getElementsByTagName('parsererror')[0]) {
    throw Object.assign(new Error(`${status}: the answer is not XML`), exchange);
  }
  const fault = first(doc, 'Fault');
  if (fault) {
    const description = first(fault, 'Error')?.getAttribute('Description');
    throw Object.assign(new Error(description || text(fault, 'faultstring') || 'SOAP fault'), exchange);
  }
  return doc;
}

// a traced call's entry without its response (the console has that): runtime, SQL statements with rows and time
async function tracedCall(id) {
  const query = new URLSearchParams({ id, response: 'false' });
  if (client) query.set('sap-client', client);
  const response = await fetch(`api/trace/entry?${query}`);
  let data;
  try {
    data = await response.json();
  } catch {
    throw new Error(`${response.status} ${response.statusText}`);
  }
  if (!response.ok) throw new Error(data.error || `${response.status} ${response.statusText}`);
  return data;
}

// a traced call as a run of the console (the trace page's "Open in MDX Console"): its answer as it was sent (all of
// it, GET api/trace/response), its request, query plan and SQL statements; nothing is run again
async function tracedRun(id) {
  const trace = await tracedCall(id);
  const exchange = { request: trace.request || '', raw: '', ms: null, traceId: id, mdx: trace.mdx || '', trace, fromTrace: true,
    kind: trace.method === 'CHECK' ? 'bw' : 'xmla' };
  if (!trace.status) {
    return { ...exchange, state: 'err', message: 'The call has no answer: it is still running, or it was aborted (a short dump, ST22).' };
  }
  const query = new URLSearchParams({ id });
  if (client) query.set('sap-client', client);
  const response = await fetch(`api/trace/response?${query}`);
  const raw = await response.text();
  if (!response.ok) return { ...exchange, state: 'err', message: `The response could not be read: ${response.status} ${response.statusText}` };
  if (exchange.kind === 'bw') return { ...exchange, raw, ...checkOf(raw, `HTTP ${trace.status}`) };
  try {
    return { ...exchange, raw, state: 'ok', result: parseCellset(answerOf(raw, `HTTP ${trace.status}`, {})) };
  } catch (e) {
    return { ...exchange, raw, state: 'err', message: e.message };
  }
}

async function discover(requestType, restrictions = {}, properties = {}) {
  const { doc } = await post('Discover', '<Discover xmlns="urn:schemas-microsoft-com:xml-analysis">'
    + `<RequestType>${requestType}</RequestType>`
    + `<Restrictions><RestrictionList>${propertyList(restrictions)}</RestrictionList></Restrictions>`
    + `<Properties><PropertyList>${propertyList({ ...properties, Content: 'Data' })}</PropertyList></Properties>`
    + '</Discover>');
  return all(doc, 'row').map((row) => Object.fromEntries([...row.children].map((c) => [c.localName, c.textContent])));
}

function execute(statement, dataSource, catalog, traced) {
  return post('Execute', '<Execute xmlns="urn:schemas-microsoft-com:xml-analysis">'
    + `<Command><Statement>${escapeXml(statement)}</Statement></Command>`
    + `<Properties><PropertyList>${propertyList({ DataSourceInfo: dataSource, Catalog: catalog, Format: 'Multidimensional',
      AxisFormat: 'TupleFormat', Content: 'Data' })}</PropertyList></Properties>`
    + '</Execute>', traced);
}

// ---------------------------------------------------------------------------------------------------- BW's MDX

// POST bw/check?user=&keyDate= with the statement as body; the answer is the check's JSON (traced: as post)
async function check(statement, user, keyDate, traced) {
  const started = performance.now();
  const query = new URLSearchParams();
  if (user) query.set('user', user);
  if (keyDate) query.set('keyDate', keyDate);
  if (client) query.set('sap-client', client);
  const response = await fetch(`${endpoint.replace(/\/$/, '')}/bw/check?${query}`, {
    method: 'POST',
    headers: { 'Content-Type': 'text/plain; charset=utf-8', ...(traced ? { 'X-olap4abap-Trace': 'true' } : {}) },
    body: statement,
  });
  const raw = await response.text();
  const exchange = { request: statement, raw, ms: performance.now() - started, traceId: response.headers.get('X-olap4abap-Trace-Id') || '' };
  return { ...exchange, ...checkOf(raw, `${response.status} ${response.statusText}`) };
}

// the answer of a check as a run's state: ok with the check (its status may be ERROR), or err if it was refused
function checkOf(raw, status) {
  let data;
  try {
    data = JSON.parse(raw);
  } catch {
    return { state: 'err', message: `${status}: the answer is not JSON` };
  }
  if (data.error) return { state: 'err', message: data.error };
  return { state: 'ok', check: data };
}

const prettyJson = (s) => {
  try {
    return JSON.stringify(JSON.parse(s), null, 2);
  } catch {
    return s;
  }
};

const CHECK_STATUS = { RESOLVED: 'ok', OK: 'ok', EMPTY: 'warn', UNKNOWN: 'warn', 'NO AUTH': 'err', ERROR: 'err' };

// the check's answer: its status, user and key date, BW's message or the fault, the statement in olap4abap's names
function CheckView({ run }) {
  const { check: c, trace } = run;
  const [copy, copied] = useCopied();
  const resolved = useMemo(() => (c.resolved ? formatMdx(c.resolved) : ''), [c.resolved]);
  return html`
    <div class="result-bar">
      <span class=${`status ${CHECK_STATUS[c.status] || 'warn'}`}>${c.status}</span>
      <span class="muted small">for <span class="mono">${c.user}</span> at ${c.keyDate}${run.ms != null ? ` · ${msText(run.ms)}` : ''}
        ${trace && !trace.error && html`<span title="On the server: the call's runtime, its SQL statements and their time">${
          ` · server ${msText(trace.runtimeMs)}, ${statementCount(trace.sqlCount)} ${msText(trace.sqlMs)}`}</span>`}</span>
      <span class="spacer"></span>
      ${copied}
      <button disabled=${!resolved} onClick=${() => copy(resolved)} title="Copy the statement in olap4abap's names">Copy</button>
    </div>
    ${c.message && html`<div class=${`notice ${c.status === 'ERROR' ? 'err' : 'info'}`}>${c.message}</div>`}
    ${resolved && html`<div class="muted small">The statement in olap4abap's names:</div>
      <textarea class="trace" readonly spellcheck="false" value=${resolved} aria-label="The statement in olap4abap's names"></textarea>`}`;
}

// BW's names, as the endpoint for BW's MDX reads them; a click inserts the example
const BW_NAMES = [
  ['Cube', 'the InfoProvider after $', '[$ZCLVISITA]'],
  ['Key figure', '', '[Measures].[ZCLVISNO]'],
  ['Characteristic', 'its flat hierarchy', '[ZCLDIAG].Members'],
  ['Member', 'by its key, NUMC with its zeros', '[ZCLDOC].[001]'],
  ['Initial value', '', '[ZCLDIAG].[]'],
  ['BW hierarchy', 'characteristic, name and version in fixed columns', '[ZCLDOC                        ZCLDOC_ORG                    001]'],
  ['Level', 'of a BW hierarchy', 'LEVEL01'],
  ['Node', 'name and InfoObject in fixed columns', '[CARD                            0HIER_NODE                    ]'],
  ['Leaf', 'by its key, no path', '[ZCLDIAG   ZCLDIAG_ICD].[A09]'],
];

// the place of BW's names next to the editor, where the cube browser is in the XMLA mode
function BwNames({ onInsert }) {
  return html`<nav class="tree browser" aria-label="BW's names">
    <div class="group"><h3>BW's names</h3></div>
    ${BW_NAMES.map(([what, note, example]) => html`<button class="item" title=${`${example} – click to insert`}
      onClick=${() => onInsert(example)}>
      <span class="label"><strong>${what}</strong>${note && html` <span class="muted small">${note}</span>`}<br />
        <span class="mono small">${example.replace(/ {2,}/g, (m) => '·'.repeat(m.length))}</span></span>
    </button>`)}
    <div class="muted small pad">Fixed columns are shown with dots for their blanks. The answer is the check's status for
      the user at the key date, never data.</div>
  </nav>`;
}

// ------------------------------------------------------------------------------------------------------ cellset

// The answer of an Execute as plain data: the axes (Axis0, Axis1, ... in order), the slicer and the cells by ordinal.
function parseCellset(doc) {
  const info = new Map(all(doc, 'AxisInfo').map((a) => [a.getAttribute('name'),
    children(a, 'HierarchyInfo').map((h) => h.getAttribute('name'))]));
  const member = (m) => ({
    hierarchy: m.getAttribute('Hierarchy'),
    uname: text(m, 'UName'),
    caption: text(m, 'Caption'),
    lnum: Number(text(m, 'LNum')) || 0,
  });
  const axisOf = (a) => {
    const name = a.getAttribute('name');
    const tuples = all(a, 'Tuple').map((t) => children(t, 'Member').map(member));
    return { name, tuples, hierarchies: info.get(name) || (tuples[0] || []).map((m) => m.hierarchy) };
  };
  const axes = all(doc, 'Axis').map(axisOf);
  const slicer = axes.find((a) => a.name === 'SlicerAxis');
  const data = axes.filter((a) => /^Axis\d+$/.test(a.name));
  // an axis the answer lists in AxesInfo but sends without tuples has none
  for (const [name, hierarchies] of info) {
    if (/^Axis\d+$/.test(name) && !data.some((a) => a.name === name)) data.push({ name, tuples: [], hierarchies });
  }
  data.sort((a, b) => a.name.slice(4) - b.name.slice(4));
  const cells = new Map();
  for (const c of all(doc, 'Cell')) {
    const value = children(c, 'Value')[0];
    const error = first(value, 'Error');
    cells.set(Number(c.getAttribute('CellOrdinal')), {
      value: error ? '' : value?.textContent ?? '',
      type: value?.getAttributeNS('http://www.w3.org/2001/XMLSchema-instance', 'type') || '',
      formatted: children(c, 'FmtValue')[0]?.textContent,
      error: error ? text(error, 'Description') || error.getAttribute('Description') || '#ERR' : '',
    });
  }
  const cube = text(first(doc, 'CubeInfo'), 'CubeName');
  return { cube, axes: data, slicer, cells, size: data.reduce((n, a) => n * a.tuples.length, 1) };
}

const NUMERIC = /^xsd:(double|float|decimal|int|integer|long|short|byte|unsigned\w+)$/;

function Cell({ cell }) {
  if (!cell) return html`<td class="num"></td>`;
  if (cell.error) return html`<td class="num cell-err" title=${cell.error}>#ERR</td>`;
  const shown = cell.formatted ?? cell.value;
  const numeric = NUMERIC.test(cell.type) || (!cell.type && shown !== '' && !isNaN(Number(cell.value)));
  return html`<td class=${numeric ? 'num' : ''} title=${cell.formatted != null && cell.formatted !== cell.value ? cell.value : ''}>${shown}</td>`;
}

const samePrefix = (a, b, depth) => {
  for (let i = 0; i <= depth; i++) if (a[i]?.uname !== b[i]?.uname) return false;
  return true;
};
const caption = (m) => m.caption || m.uname;
const hierarchyLabel = (h) => h.replace(/^\[|\]$/g, '').replace(/\]\.\[/g, '.');

// A grid for up to two axes: Axis0 the column headers (one header row per hierarchy, a member spans the columns it
// shares with its neighbours), Axis1 the row headers (likewise, spanning rows). Zero axes: the one cell.
function Grid({ result }) {
  const [columnsAxis, rowsAxis] = result.axes;
  if (!columnsAxis) return html`<table class="grid"><tbody><tr><${Cell} cell=${result.cells.get(0)} /></tr></tbody></table>`;
  const columns = columnsAxis.tuples.slice(0, MAX_GRID_COLUMNS);
  const rows = rowsAxis ? rowsAxis.tuples.slice(0, MAX_GRID_ROWS) : [[]];
  const columnDepth = columnsAxis.hierarchies.length;
  const rowDepth = rowsAxis ? rowsAxis.hierarchies.length : 0;
  const width = columnsAxis.tuples.length;

  const headerRows = columnsAxis.hierarchies.map((h, depth) => {
    const spans = [];
    for (let c = 0; c < columns.length;) {
      let span = 1;
      while (c + span < columns.length && samePrefix(columns[c], columns[c + span], depth)) span++;
      spans.push({ member: columns[c][depth], span });
      c += span;
    }
    return spans;
  });
  // rowSpans[r][depth]: the rows the member spans from row r, 0 where an upper row's span covers it
  const rowSpans = rows.map((tuple, r) => tuple.map((_, depth) => {
    if (r > 0 && samePrefix(rows[r - 1], tuple, depth)) return 0;
    let span = 1;
    while (r + span < rows.length && samePrefix(tuple, rows[r + span], depth)) span++;
    return span;
  }));

  return html`<table class="grid">
    <thead>
      ${headerRows.map((spans, depth) => html`<tr>
        ${depth === 0 && columnDepth > 1 && rowDepth > 0 && html`<th class="corner" colspan=${rowDepth} rowspan=${columnDepth - 1}></th>`}
        ${depth === columnDepth - 1 && rowsAxis && rowsAxis.hierarchies.map((h) => html`<th class="corner" title=${h}>${hierarchyLabel(h)}</th>`)}
        ${spans.map(({ member, span }) => html`<th class="member col-head" colspan=${span} title=${member?.uname}>${member ? caption(member) : ''}</th>`)}
      </tr>`)}
    </thead>
    <tbody>
      ${!columns.length && html`<tr><td class="muted">The column axis is empty.</td></tr>`}
      ${rows.length === 0 && columns.length > 0 && html`<tr><td class="muted" colspan=${columns.length + rowDepth}>The row axis is empty.</td></tr>`}
      ${columns.length > 0 && rows.map((tuple, r) => html`<tr>
        ${tuple.map((member, depth) => rowSpans[r][depth] > 0 && html`<th class="member row-head" rowspan=${rowSpans[r][depth]}
          title=${member.uname} style=${`padding-left: ${8 + member.lnum * 14}px`}>${caption(member)}</th>`)}
        ${columns.map((_, c) => html`<${Cell} cell=${result.cells.get(r * width + c)} />`)}
      </tr>`)}
    </tbody>
  </table>`;
}

// A flat table for any number of axes: a column per hierarchy of every axis, the highest axis first, and one row per
// cell in the order of the cell ordinals (Axis0 changes fastest), so the leftmost column changes slowest.
function Flat({ result, limit }) {
  const axes = [...result.axes].reverse();
  const sizes = result.axes.map((a) => a.tuples.length);
  const strides = sizes.map((_, k) => sizes.slice(0, k).reduce((n, s) => n * s, 1));
  const count = Math.min(result.size, limit);
  const rows = [];
  for (let ordinal = 0; ordinal < count; ordinal++) {
    const members = [];
    for (let k = result.axes.length - 1; k >= 0; k--) {
      members.push(...result.axes[k].tuples[Math.floor(ordinal / strides[k]) % sizes[k]]);
    }
    rows.push(html`<tr>
      ${members.map((m) => html`<td title=${m.uname}>${caption(m)}</td>`)}
      <${Cell} cell=${result.cells.get(ordinal)} />
    </tr>`);
  }
  return html`<table class="grid flat">
    <thead><tr>
      ${axes.map((a) => a.hierarchies.map((h) => html`<th title=${`${a.name}: ${h}`} data-axis=${a.name}>${hierarchyLabel(h)}</th>`))}
      <th class="num">Value</th>
    </tr></thead>
    <tbody>${rows}</tbody>
  </table>`;
}

const size = (n) => n >= 1048576 ? `${(n / 1048576).toFixed(1)} MB` : n >= 1024 ? `${(n / 1024).toFixed(1)} KB` : `${n} B`;
// the cells of the answer as a grid or a table
function Cells({ run, view, setView }) {
  const tableRef = useRef(null);
  const [copy, copied] = useCopied();
  const { result, trace } = run;
  const grid = result.axes.length <= 2 && view !== 'flat';
  const truncated = grid
    ? (result.axes[0]?.tuples.length > MAX_GRID_COLUMNS || result.axes[1]?.tuples.length > MAX_GRID_ROWS)
    : result.size > MAX_FLAT_ROWS;
  const slicer = result.slicer?.tuples.flat() || [];

  return html`
    <div class="result-bar">
      <span class="muted small">
        ${result.cube && html`<span class="mono">${result.cube}</span> · `}
        ${`${result.axes.length} ${result.axes.length === 1 ? 'axis' : 'axes'} (${result.axes.map((a) => a.tuples.length).join(' × ') || '–'})`
          + ` · ${result.size.toLocaleString()} cell${result.size === 1 ? '' : 's'}${run.ms != null ? ` · ${msText(run.ms)}` : ''}`}
        ${trace && !trace.error && html`<span title="On the server: the call's runtime, its SQL statements and their time">${
          ` · server ${msText(trace.runtimeMs)}, ${statementCount(trace.sqlCount)} ${msText(trace.sqlMs)}`}</span>`}
      </span>
      ${slicer.length > 0 && html`<span class="small" title="The slicer (WHERE)">where ${slicer.map((m, i) => html`${i > 0 && ', '}<span
        class="kind" title=${m.uname}>${caption(m)}</span>`)}</span>`}
      <span class="spacer"></span>
      ${result.axes.length <= 2 && result.axes.length > 0 && html`<div class="segmented" role="group" aria-label="View">
        <button class=${grid ? 'active' : ''} onClick=${() => setView('grid')}>Grid</button>
        <button class=${grid ? '' : 'active'} onClick=${() => setView('flat')}>Table</button>
      </div>`}
      ${copied}
      <button onClick=${() => copy(tableRef.current.innerText)} title="Copy the table as tab-separated text">Copy</button>
    </div>
    ${truncated && html`<div class="notice warn">The answer is too large to show in full: ${grid
      ? `the first ${MAX_GRID_ROWS.toLocaleString()} rows and ${MAX_GRID_COLUMNS.toLocaleString()} columns are shown`
      : `the first ${MAX_FLAT_ROWS.toLocaleString()} of ${result.size.toLocaleString()} rows are shown`}.</div>`}
    <div class="result-table" ref=${tableRef}>
      ${grid ? html`<${Grid} result=${result} />` : html`<${Flat} result=${result} limit=${MAX_FLAT_ROWS} />`}
    </div>`;
}

// the SOAP request or response as sent, or indented for reading (format: xml, json, or text shown as it is)
// A browser cannot lay out a textarea of a hundred megabytes: of a larger text the first MAX_SHOWN_CHARS are shown
// (as on the trace page); Download gives all of it.
function Xml({ text, name, format = 'xml', children: notices }) {
  const [pretty, setPretty] = useState(true);
  const [copy, copied] = useCopied();
  const cut = text.length > MAX_SHOWN_CHARS;
  const part = useMemo(() => (cut ? text.slice(0, MAX_SHOWN_CHARS) : text), [text]);
  const shown = useMemo(() => (!pretty ? part : format === 'xml' ? prettyXml(part) : format === 'json' ? prettyJson(part) : part),
    [part, pretty, format]);
  return html`
    <div class="result-bar">
      ${format !== 'text' && html`<label class="inline"><input type="checkbox" checked=${pretty} onChange=${(e) => setPretty(e.target.checked)} /> Indent ${format.toUpperCase()}</label>`}
      <span class="muted small">${size(text.length)}</span>
      <span class="spacer"></span>
      ${copied}
      <button onClick=${() => copy(shown)} disabled=${!text} title=${cut ? 'Copy the part shown' : 'Copy the text shown'}>Copy</button>
      <button onClick=${() => download(text, name)} disabled=${!text} title="All of it, as sent">Download</button>
    </div>
    ${cut && html`<div class="notice warn">${`The text has ${size(text.length)}; the first ${MAX_SHOWN_CHARS.toLocaleString('en')} characters are shown`
      + ' (Copy copies those). Download gives all of it.'}</div>`}
    ${notices}
    <textarea class="trace" readonly spellcheck="false" value=${shown} aria-label=${name}></textarea>`;
}

// ------------------------------------------------------------------------------------------- query plan and SQL

// the run's traced call as the shared views take it (query-plan.js): its trace with the statement and the browser's time
const tracedCallOf = (run) => ({ ...run.trace, id: run.traceId, mdx: run.mdx, browserMs: run.ms });

// what is shown instead of the trace while there is none: Trace off, not read yet, not readable
function traceMissing(run, traced, what) {
  if (!run.traceId) {
    return html`<div class="result-msg muted">${traced
      ? 'The endpoint did not trace the call.'
      : `Trace is off: switch it on next to Run and run the statement again to see its ${what}.`}</div>`;
  }
  if (!run.trace) return html`<div class="result-msg muted">Reading the trace…</div>`;
  if (run.trace.error) return html`<div class="result-msg"><div class="notice err">The trace could not be read: ${run.trace.error}</div></div>`;
  return null;
}

function Sql({ run, traced, onNode, onPhase }) {
  return traceMissing(run, traced, 'SQL statements') || html`<${SqlView} call=${tracedCallOf(run)} onNode=${onNode} onPhase=${onPhase}>
    <a class="button" href=${`trace.html${location.search}`} target="_blank" rel="noopener" title="The call is listed on the trace page too">Trace page</a>
  <//>`;
}

function Plan({ run, traced, selection, setSelection }) {
  return traceMissing(run, traced, 'query plan')
    || html`<${PlanView} call=${tracedCallOf(run)} selection=${selection} setSelection=${setSelection} />`;
}

// The answer of the last run: its cells (or its error), its query plan, the SQL statements it ran and the SOAP
// response and request
function Result({ run, view, setView, tab, setTab, traced }) {
  const [selection, setSelection] = useState(null);  // the element ({node}) or phase ({phase}) of the query plan
  if (run.state === 'busy') return html`<div class="result-msg muted">${run.message || 'Running…'}</div>`;
  const { trace } = run;
  const bw = run.kind === 'bw';
  const sqlLabel = !run.traceId ? 'off' : !trace ? '…' : trace.error ? '!' : `${trace.sqlCount} · ${msText(trace.sqlMs)}`;
  const planLabel = !run.traceId ? 'off' : !trace ? '…' : trace.error || !trace.explain ? 'none' : '';
  // a check has no query plan; its request is the statement, its response JSON
  const tabs = bw
    ? [['result', 'Result', run.state === 'err' || run.check?.status === 'ERROR' ? 'error' : ''], ['sql', 'SQL statements', sqlLabel],
      ['response', 'Response', size((run.raw || '').length)], ['request', 'Request', '']]
    : [['result', 'Result', run.state === 'err' ? 'error' : ''], ['plan', 'Query plan', planLabel],
      ['sql', 'SQL statements', sqlLabel], ['response', 'SOAP response', size((run.raw || '').length)], ['request', 'SOAP request', '']];
  const shown = tabs.some(([key]) => key === tab) ? tab : 'result';
  // from a statement to its element or phase in the plan
  const show = (target) => {
    setSelection(target);
    setTab('plan');
  };
  return html`<div class="result">
    ${run.fromTrace && html`<div class="notice info small">The traced call of <span class="mono">${trace?.user}</span>${
      trace?.at ? ` at ${new Date(trace.at).toLocaleString()}` : ''}, as it was answered; ${run.kind === 'bw' ? 'Check' : 'Run'} runs the statement again.</div>`}
    <div class="tabs result-tabs" role="tablist">
      ${tabs.map(([key, label, note]) => html`<button role="tab" class=${shown === key ? 'active' : ''} aria-selected=${shown === key}
        onClick=${() => setTab(key)}>${label}${note && html` <span class="muted small">${note}</span>`}</button>`)}
    </div>
    ${shown === 'response' ? html`<${Xml} text=${run.raw || ''} name=${bw ? 'check-response.json' : 'execute-response.xml'} format=${bw ? 'json' : 'xml'}>
        ${run.state === 'err' && run.raw && html`<div class="notice err">${bw ? 'The check was refused.' : 'The answer is a SOAP fault, or no XML.'}</div>`}
        ${!run.raw && html`<div class="notice warn">No response: ${run.message}</div>`}
      <//>`
      : shown === 'request' ? html`<${Xml} text=${run.request || ''} name=${bw ? 'check-request.mdx' : 'execute-request.xml'} format=${bw ? 'text' : 'xml'} />`
      : shown === 'sql' ? html`<${Sql} run=${run} traced=${traced} onNode=${(id) => !bw && show({ node: id })} onPhase=${(phase) => !bw && show({ phase })} />`
      : shown === 'plan' ? html`<${Plan} run=${run} traced=${traced} selection=${selection} setSelection=${setSelection} />`
      : run.state === 'err' ? html`<div class="notice err">${run.message}</div>`
      : bw ? html`<${CheckView} run=${run} />`
      : html`<${Cells} run=${run} view=${view} setView=${setView} />`}
  </div>`;
}

// -------------------------------------------------------------------------------------------------- cube browser

function Browser({ dataSource, catalog, onInsert }) {
  const [cubes, setCubes] = useState(null);
  const [open, setOpen] = useState({});
  const [content, setContent] = useState({});
  const [error, setError] = useState('');
  useEffect(() => {
    setCubes(null);
    setOpen({});
    setContent({});
    setError('');
    if (!catalog) return;
    discover('MDSCHEMA_CUBES', { CATALOG_NAME: catalog }, { DataSourceInfo: dataSource, Catalog: catalog })
      .then(setCubes, (e) => setError(e.message));
  }, [catalog]);

  const loadCube = async (cube) => {
    const restrictions = { CATALOG_NAME: catalog, CUBE_NAME: cube };
    const properties = { DataSourceInfo: dataSource, Catalog: catalog };
    try {
      const [measures, hierarchies, levels] = await Promise.all([
        discover('MDSCHEMA_MEASURES', restrictions, properties),
        discover('MDSCHEMA_HIERARCHIES', restrictions, properties),
        discover('MDSCHEMA_LEVELS', restrictions, properties),
      ]);
      const dimensions = [];
      for (const h of hierarchies.filter((x) => x.DIMENSION_UNIQUE_NAME !== '[Measures]')) {
        let d = dimensions.find((x) => x.uname === h.DIMENSION_UNIQUE_NAME);
        if (!d) dimensions.push(d = { uname: h.DIMENSION_UNIQUE_NAME, hierarchies: [] });
        d.hierarchies.push({
          uname: h.HIERARCHY_UNIQUE_NAME,
          caption: h.HIERARCHY_CAPTION || h.HIERARCHY_NAME,
          levels: levels.filter((l) => l.HIERARCHY_UNIQUE_NAME === h.HIERARCHY_UNIQUE_NAME && l.LEVEL_TYPE !== '1')
            .sort((a, b) => a.LEVEL_NUMBER - b.LEVEL_NUMBER)
            .map((l) => ({ uname: l.LEVEL_UNIQUE_NAME, caption: l.LEVEL_CAPTION || l.LEVEL_NAME })),
        });
      }
      setContent((c) => ({
        ...c,
        [cube]: {
          measures: measures.map((m) => ({ uname: m.MEASURE_UNIQUE_NAME, caption: m.MEASURE_CAPTION || m.MEASURE_NAME })),
          dimensions,
        },
      }));
    } catch (e) {
      setContent((c) => ({ ...c, [cube]: { error: e.message } }));
    }
  };
  const toggle = (key, load) => {
    setOpen((o) => ({ ...o, [key]: !o[key] }));
    if (load && !open[key]) load();
  };

  const leaf = (uname, label, kind, depth) => html`<button class="item" style=${`padding-left: ${14 + depth * 14}px`} draggable="true"
    title=${`${uname} – click to insert, or drag`} onClick=${() => onInsert(uname)}
    onDragStart=${(e) => e.dataTransfer.setData('text/plain', uname)}>
    <span class=${`glyph ${kind}`}></span><span class="label">${label}</span>
  </button>`;
  const node = (key, label, kind, depth, load, uname) => html`<button class="item" style=${`padding-left: ${14 + depth * 14}px`}
    onClick=${() => toggle(key, load)} onDblClick=${() => uname && onInsert(uname)} title=${uname ? `${uname} – double-click to insert` : ''}
    draggable=${!!uname} onDragStart=${(e) => uname && e.dataTransfer.setData('text/plain', uname)}>
    <span class="twisty">${open[key] ? '▾' : '▸'}</span><span class=${`glyph ${kind}`}></span><span class="label">${label}</span>
  </button>`;

  return html`<nav class="tree browser" aria-label="Cubes">
    <div class="group"><h3>Cubes</h3></div>
    ${error && html`<div class="notice err small" style="margin: 0 14px">${error}</div>`}
    ${!catalog ? html`<div class="muted small pad">No catalog.</div>` : cubes == null && !error ? html`<div class="muted small pad">Loading…</div>` : null}
    ${(cubes || []).map((cube) => {
      const name = cube.CUBE_NAME;
      const c = content[name];
      return html`
        ${node(name, html`<strong>${name}</strong>${cube.CUBE_CAPTION && cube.CUBE_CAPTION !== name
          && html` <span class="muted small">${cube.CUBE_CAPTION}</span>`}`, 'cube', 0, () => loadCube(name), `[${name}]`)}
        ${open[name] && (c == null ? html`<div class="muted small pad">Loading…</div>`
          : c.error ? html`<div class="notice err small" style="margin: 0 14px">${c.error}</div>` : html`
          ${node(`${name}|m`, 'Measures', 'folder', 1, null, '[Measures]')}
          ${open[`${name}|m`] && c.measures.map((m) => leaf(m.uname, m.caption, 'measure', 2))}
          ${c.dimensions.map((d) => {
            const key = `${name}|${d.uname}`;
            // a dimension with one hierarchy of its name shows the levels right away
            const single = d.hierarchies.length === 1 && d.hierarchies[0].uname === d.uname;
            return html`
              ${node(key, hierarchyLabel(d.uname), 'dimension', 1, null, d.uname)}
              ${open[key] && (single ? d.hierarchies[0].levels.map((l) => leaf(l.uname, l.caption, 'level', 2))
                : d.hierarchies.map((h) => html`
                  ${node(`${key}|${h.uname}`, h.caption, 'hierarchy', 2, null, h.uname)}
                  ${open[`${key}|${h.uname}`] && h.levels.map((l) => leaf(l.uname, l.caption, 'level', 3))}`))}`;
          })}`)}`;
    })}
  </nav>`;
}

// ---------------------------------------------------------------------------------------------------------- app

function load(key, fallback) {
  try {
    const value = localStorage.getItem(`olap4abap.console.${key}`);
    return value == null ? fallback : JSON.parse(value);
  } catch {
    return fallback;
  }
}
function save(key, value) {
  try {
    localStorage.setItem(`olap4abap.console.${key}`, JSON.stringify(value));
  } catch {
    // private window or blocked storage: the console works without it
  }
}

// A statement handed over in the URL's fragment (#statement=...&catalog=...&trace=..., the trace page's "Open in MDX
// Console"; trace the id of the traced call, shown as the result; a check with mode=bw, user and keyDate): read once,
// then removed from the address bar, so a reload shows what was typed since. The fragment is not sent to the server,
// so a long statement fits.
function handedOver() {
  const params = new URLSearchParams(location.hash.slice(1));
  if (!params.has('statement')) return {};
  history.replaceState(null, '', location.pathname + location.search);
  return { statement: params.get('statement'), catalog: params.get('catalog') || '', trace: params.get('trace') || '',
    mode: params.get('mode') === 'bw' ? 'bw' : '', user: params.get('user') || '', keyDate: params.get('keyDate') || '' };
}

const DEFAULT_KEY_DATE = '9999-12-31';
// the statement and the history are kept per mode
const modeKey = (mode, key) => (mode === 'bw' ? `bw.${key}` : key);

function App() {
  const [handed] = useState(handedOver);
  const [mode, setMode] = useState(() => (handed.statement != null ? handed.mode || 'xmla' : load('mode', 'xmla')));
  const [user, setUser] = useState(() => (handed.mode ? handed.user : load('bw.user', '')));
  const [keyDate, setKeyDate] = useState(() => (handed.mode ? handed.keyDate : load('bw.keyDate', DEFAULT_KEY_DATE)) || DEFAULT_KEY_DATE);
  const [sources, setSources] = useState(null);
  const [catalogs, setCatalogs] = useState([]);
  const [catalog, setCatalog] = useState(() => handed.catalog || load('catalog', ''));
  const [statement, setStatement] = useState(() => handed.statement ?? load(modeKey(mode, 'statement'), ''));
  const [history, setHistory] = useState(() => load(modeKey(mode, 'history'), []));
  const [run, setRun] = useState(() => (handed.trace ? { state: 'busy', message: 'Reading the traced call…' } : null));
  const [view, setView] = useState('grid');
  const [tab, setTab] = useState('result');
  const [traced, setTraced] = useState(() => load('trace', true));
  const runs = useRef(0);  // the number of the last run: a trace read for an earlier one is dropped
  const [error, setError] = useState('');
  const editor = useRef(null);
  const dataSource = sources?.[0]?.DataSourceName || '';

  useEffect(() => {
    (async () => {
      try {
        const ds = await discover('DISCOVER_DATASOURCES');
        setSources(ds);
        const rows = await discover('DBSCHEMA_CATALOGS', {}, { DataSourceInfo: ds[0]?.DataSourceName });
        const names = rows.map((r) => r.CATALOG_NAME);
        setCatalogs(names);
        setCatalog((c) => (names.includes(c) ? c : names[0] || ''));
      } catch (e) {
        setError(e.message);
      }
    })();
  }, []);
  useEffect(() => {
    if (!handed.trace) return;
    const number = ++runs.current;
    tracedRun(handed.trace).catch((e) => ({ state: 'err', message: `The traced call could not be read: ${e.message}`,
      raw: '', request: '', traceId: handed.trace, trace: { error: e.message } }))
      .then((done) => number === runs.current && setRun(done));
  }, []);
  useEffect(() => save('catalog', catalog), [catalog]);
  useEffect(() => save(modeKey(mode, 'statement'), statement), [statement]);
  useEffect(() => save('trace', traced), [traced]);
  useEffect(() => save('mode', mode), [mode]);
  useEffect(() => save('bw.user', user), [user]);
  useEffect(() => save('bw.keyDate', keyDate), [keyDate]);

  // the other mode's statement and history; the result of this one goes
  const switchMode = (next) => {
    if (next === mode) return;
    runs.current++;
    setMode(next);
    setStatement(load(modeKey(next, 'statement'), ''));
    setHistory(load(modeKey(next, 'history'), []));
    setRun(null);
  };

  const runStatement = useCallback(async () => {
    const area = editor.current;
    const selected = area && area.selectionStart !== area.selectionEnd
      ? area.value.slice(area.selectionStart, area.selectionEnd) : statement;
    const mdx = selected.trim();
    if (!mdx || (mode === 'xmla' && !catalog)) return;
    const number = ++runs.current;
    setRun({ state: 'busy' });
    let done;
    if (mode === 'bw') {
      try {
        done = { ...await check(mdx, user.trim().toUpperCase(), keyDate, traced), kind: 'bw', mdx };
      } catch (e) {
        done = { state: 'err', kind: 'bw', message: e.message, raw: '', request: mdx, traceId: '', mdx };
      }
    } else {
      try {
        const { doc, ms, raw, request, traceId } = await execute(mdx, dataSource, catalog, traced);
        done = { state: 'ok', result: parseCellset(doc), ms, raw, request, traceId, mdx };
      } catch (e) {
        done = { state: 'err', message: e.message, ms: e.ms, raw: e.raw || '', request: e.request || '', traceId: e.traceId || '', mdx };
      }
    }
    if (number !== runs.current) return;
    setRun(done);
    if (done.traceId) {
      tracedCall(done.traceId).catch((e) => ({ error: e.message }))
        .then((trace) => number === runs.current && setRun({ ...done, trace }));
    }
    setHistory((h) => {
      const next = [mdx, ...h.filter((x) => x !== mdx)].slice(0, HISTORY_SIZE);
      save(modeKey(mode, 'history'), next);
      return next;
    });
  }, [mode, statement, catalog, dataSource, traced, user, keyDate]);

  const insert = (piece) => {
    const area = editor.current;
    const start = area ? area.selectionStart : statement.length;
    const end = area ? area.selectionEnd : statement.length;
    const next = statement.slice(0, start) + piece + statement.slice(end);
    setStatement(next);
    requestAnimationFrame(() => {
      if (!area) return;
      area.focus();
      area.setSelectionRange(start + piece.length, start + piece.length);
    });
  };

  // formats the selection, or the statement; typed into the textarea, so Ctrl+Z undoes it
  const format = () => {
    const area = editor.current;
    if (!area) return;
    const selected = area.selectionStart !== area.selectionEnd;
    const start = selected ? area.selectionStart : 0;
    const end = selected ? area.selectionEnd : area.value.length;
    const formatted = formatMdx(area.value.slice(start, end));
    if (formatted === area.value.slice(start, end)) return;
    area.focus();
    area.setSelectionRange(start, end);
    if (!document.execCommand('insertText', false, formatted)) {
      setStatement(area.value.slice(0, start) + formatted + area.value.slice(end));
    }
  };

  const busy = run?.state === 'busy';
  return html`
    <div class="topbar">
      <div class="title"><h1>MDX Console</h1><span class="src">olap4abap</span></div>
      <div class="segmented" role="group" aria-label="Mode">
        <button class=${mode === 'xmla' ? 'active' : ''} aria-pressed=${mode === 'xmla'} onClick=${() => switchMode('xmla')}
          title="Execute in olap4abap's names on a catalog of the XMLA endpoint">XMLA</button>
        <button class=${mode === 'bw' ? 'active' : ''} aria-pressed=${mode === 'bw'} onClick=${() => switchMode('bw')}
          title="Check a statement in BW's names for a user at a key date (the endpoint for BW's MDX; no data)">BW's MDX</button>
      </div>
      ${mode === 'xmla' ? html`<label class="inline">Catalog
        <select value=${catalog} onChange=${(e) => setCatalog(e.target.value)} disabled=${!catalogs.length}>
          ${!catalogs.length && html`<option value="">–</option>`}
          ${catalogs.map((c) => html`<option value=${c}>${c}</option>`)}
        </select>
      </label>` : html`<label class="inline" title="A test user of the authorisation scenarios, or empty for your own">User
        <input type="text" maxlength="12" size="13" placeholder="you" value=${user} onInput=${(e) => setUser(e.target.value)} />
      </label>
      <label class="inline">Key date
        <input type="date" value=${keyDate} onInput=${(e) => setKeyDate(e.target.value || DEFAULT_KEY_DATE)} />
      </label>`}
      <span class="spacer"></span>
      <a href=${`./${location.search}`}>Schema Builder</a>
      <a href=${`time.html${location.search}`}>Time Master Data</a>
      <a href=${`trace.html${location.search}`}>Trace</a>
    </div>
    ${error && html`<div class="banner" role="alert">${error}</div>`}
    <div class="editor console">
      ${mode === 'xmla' ? html`<${Browser} dataSource=${dataSource} catalog=${catalog} onInsert=${insert} />`
        : html`<${BwNames} onInsert=${insert} />`}
      <main class="main console-main">
        <div class="query">
          <textarea ref=${editor} class="mdx" spellcheck="false" value=${statement} aria-label="MDX statement"
            placeholder=${mode === 'xmla' ? 'SELECT {[Measures].Members} ON COLUMNS\nFROM [Cube]'
              : 'SELECT {[Measures].[ZCLVISNO]} ON COLUMNS\nFROM [$ZCLVISITA]\nWHERE ([ZCLDOC].[001])'}
            onInput=${(e) => setStatement(e.target.value)}
            onKeyDown=${(e) => {
              if ((e.ctrlKey || e.metaKey) && e.key === 'Enter') { e.preventDefault(); runStatement(); }
              if (e.shiftKey && e.altKey && e.code === 'KeyF') { e.preventDefault(); format(); }
            }}></textarea>
          <div class="row">
            <button class="primary" disabled=${busy || (mode === 'xmla' && !catalog) || !statement.trim()} onClick=${runStatement}
              title=${mode === 'xmla' ? 'Run the statement, or the selected part of it (Ctrl+Enter)'
                : 'Check the statement, or the selected part of it, for the user at the key date (Ctrl+Enter)'}>${
                busy ? 'Running…' : mode === 'xmla' ? 'Run' : 'Check'}</button>
            <button disabled=${!statement.trim()} onClick=${format}
              title="Lay out the statement, or the selected part of it, for reading (Shift+Alt+F)">Format</button>
            <label class="inline" title="Trace the call: its SQL statements, their rows and time (the call is listed on the trace page too)">
              <input type="checkbox" checked=${traced} onChange=${(e) => setTraced(e.target.checked)} /> Trace SQL</label>
            <select value="" aria-label="History" disabled=${!history.length} onChange=${(e) => {
              const i = e.target.value;
              e.target.value = '';
              if (i !== '') setStatement(history[Number(i)]);
            }}>
              <option value="">History…</option>
              ${history.map((h, i) => html`<option value=${i}>${h.replace(/\s+/g, ' ').slice(0, 90)}</option>`)}
            </select>
            <span class="muted small">Ctrl+Enter runs the statement or the selection, Shift+Alt+F formats it; click a name on the left to insert it.</span>
          </div>
        </div>
        ${run ? html`<${Result} run=${run} view=${view} setView=${setView} tab=${tab} setTab=${setTab} traced=${traced} />`
          : html`<div class="result-msg muted">${mode === 'xmla' ? 'Write a statement and run it. Up to two axes show as a grid, more as a table.'
            : 'Write a statement in BW\'s names and check it: the answer is its status for the user at the key date, never data.'}</div>`}
      </main>
    </div>`;
}

const root = document.getElementById('app');
root.textContent = '';
render(html`<${App} />`, root);
