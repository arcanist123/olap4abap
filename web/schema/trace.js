// The trace of the XMLA endpoint (ZZXXMLA1_CL_TRACE): switched on per SAP user for two hours (GET api/trace, POST
// api/trace/on, trace/off; switching on deletes the calls older than seven days), every call of a user with the trace on is listed with its SOAP request, the MDX statement of an Execute
// and the SOAP response (GET api/trace/entry, the whole response as sent from api/trace/response), the SQL
// statements the call ran with their rows, time, error, phase and element, and the query plan of an Execute: the same
// views as the MDX console's (query-plan.js).
// No build step: Preact with htm, vendored as one ES module; this file is what the server serves.
import { html, render, useState, useEffect, useRef } from './vendor/htm-preact-standalone.mjs';
import { prettyXml, copyText, download } from './trace-text.js';
import { SqlView, PlanView } from './query-plan.js';

const client = new URLSearchParams(location.search).get('sap-client');
const REFRESH_MS = 5000;
const MAX_CHOICES = [50, 200, 500, 1000, 5000, 10000];
const MAX_KEY = 'olap4abap.trace.max';
// the number of calls listed is remembered per browser; storage may be unavailable (private windows)
const storedMax = () => {
  try {
    const n = Number(localStorage.getItem(MAX_KEY));
    return MAX_CHOICES.includes(n) ? n : 200;
  } catch {
    return 200;
  }
};

const apiUrl = (resource, params = {}) => {
  const query = new URLSearchParams(Object.entries(params).filter(([, v]) => v));
  if (client) query.set('sap-client', client);
  return `api/${resource}?${query}`;
};

async function api(method, resource, params = {}) {
  const response = await fetch(apiUrl(resource, params), { method });
  let data;
  try {
    data = await response.json();
  } catch {
    throw new Error(`${response.status} ${response.statusText}`);
  }
  if (!response.ok) throw new Error(data.error || `${response.status} ${response.statusText}`);
  return data;
}

const time = (iso) => iso ? new Date(iso).toLocaleString() : '';
const size = (n) => n >= 1048576 ? `${(n / 1048576).toFixed(1)} MB` : n >= 1024 ? `${(n / 1024).toFixed(1)} KB` : `${n} B`;
const what = (c) => c.method === 'EXECUTE' ? 'Execute' : c.method === 'DISCOVER' ? 'Discover' : '(no XMLA)';
const firstLine = (s) => s.replace(/\s+/g, ' ').trim();

// the Catalog property of an Execute request, initial if it names none
function requestCatalog(xml) {
  const doc = new DOMParser().parseFromString(xml || '', 'application/xml');
  const element = doc.getElementsByTagNameNS('*', 'Catalog')[0];
  return element ? element.textContent.trim() : '';
}

// the MDX console with a traced Execute: its statement and catalog in the editor, the call itself (answer, request,
// query plan, SQL statements) as the result (console.js reads the fragment)
const consoleUrl = (entry) => {
  const fragment = new URLSearchParams({ statement: entry.mdx, trace: entry.id });
  const catalog = requestCatalog(entry.request);
  if (catalog) fragment.set('catalog', catalog);
  return `console.html${location.search}#${fragment}`;
};

function Users({ state, onSwitch, busy }) {
  const [user, setUser] = useState('');
  const name = (user || state.user).trim().toUpperCase();
  const on = state.users.some((u) => u.user === name);
  return html`<section class="section">
    <header><h2>Traced users</h2><span class="spacer"></span>
      <span class="muted small">a trace switches itself off after ${state.activeHours} hours; calls are kept ${state.retentionDays} days</span></header>
    <div class="body">
      <div class="row">
        <label class="muted" for="user">User</label>
        <input id="user" type="text" maxlength="12" placeholder=${state.user} value=${user}
          onInput=${(e) => setUser(e.target.value)} onKeyDown=${(e) => e.key === 'Enter' && onSwitch('on', name)} />
        <button class="primary" disabled=${busy || !name} onClick=${() => onSwitch('on', name)}
          title=${`On for ${state.activeHours} hours from now`}>${on ? `Switch on again for ${state.activeHours} hours` : 'Switch trace on'}</button>
        ${on && html`<span class="status ok">on</span>`}
      </div>
      ${state.users.length ? html`<table>
        <thead><tr><th>User</th><th>Since</th><th>On until</th><th>Switched on by</th><th></th></tr></thead>
        <tbody>${state.users.map((u) => html`<tr>
          <td><strong class="mono">${u.user}</strong>${u.user === state.user && html` <span class="muted small">(this page's user)</span>`}</td>
          <td>${time(u.since)}</td><td>${time(u.until)}</td><td class="mono">${u.by}</td>
          <td class="actions"><button disabled=${busy} onClick=${() => onSwitch('off', u.user)}>Switch off</button></td>
        </tr>`)}</tbody>
      </table>` : html`<div class="muted">The trace is off for every user.</div>`}
      <div class="notice info small">A call is traced under the SAP user it runs as. This page runs as${' '}
        <span class="mono">${state.user}</span>; while the ICF node <span class="mono">/zzxxmla1</span> logs on anonymously,
        every XMLA call runs as that user too. The client's address and User-Agent tell the callers apart.</div>
    </div>
  </section>`;
}

function Detail({ id, onClose }) {
  const [entry, setEntry] = useState(null);
  const [error, setError] = useState('');
  const [tab, setTab] = useState('');
  const [selection, setSelection] = useState(null);  // the element ({node}) or phase ({phase}) of the query plan
  const [pretty, setPretty] = useState(true);
  const [copied, setCopied] = useState('');  // the feedback of Copy, for a moment
  useEffect(() => {
    if (!copied) return undefined;
    const timer = setTimeout(() => setCopied(''), 2000);
    return () => clearTimeout(timer);
  }, [copied]);
  useEffect(() => {
    setEntry(null);
    setError('');
    setSelection(null);
    api('GET', 'trace/entry', { id }).then((e) => {
      setEntry(e);
      // the tab chosen before, where the call has it; an Execute starts with its query plan
      setTab((t) => (!t || (t === 'mdx' && !e.mdx) || (t === 'plan' && e.method !== 'EXECUTE')
        ? (e.method === 'EXECUTE' ? 'plan' : e.mdx ? 'mdx' : 'request') : t));
    }, (e) => setError(e.message));
  }, [id]);
  if (error) return html`<section class="section detail"><div class="body"><div class="notice err">${error}</div></div></section>`;
  if (!entry) return html`<section class="section detail"><div class="body muted">Reading the call…</div></section>`;

  // the query plan and the SQL statements as the MDX console shows them (query-plan.js); a statement's element or
  // phase is shown in the plan
  const show = (target) => {
    setSelection(target);
    setTab('plan');
  };
  const view = tab === 'plan' || tab === 'sql';
  const raw = tab === 'mdx' ? entry.mdx : tab === 'request' ? entry.request : tab === 'response' ? entry.response : '';
  const xml = tab === 'request' || tab === 'response';
  const shown = !xml || !pretty ? raw : prettyXml(raw);
  // what is shown (indented or not) is what is copied
  const copy = () => copyText(shown).then((ok) => setCopied(ok ? 'Copied' : 'Copy failed: select the text and press Ctrl+C'));
  const save = () => tab === 'response' && entry.responseTruncated
    ? window.open(apiUrl('trace/response', { id }), '_blank')
    : download(raw, `${entry.id}-${tab}.${xml ? 'xml' : tab}`);
  return html`<section class="section detail">
    <header><h2>${what(entry)}${entry.type && html` <span class="mono">${entry.type}</span>`}</h2>
      <span class="muted small">${time(entry.at)} · ${entry.user} · ${entry.client}${entry.status ? ` · ${entry.runtimeMs} ms · ${entry.sqlCount} SQL statements, ${entry.sqlMs} ms` : ''}</span>
      <span class="spacer"></span>
      ${entry.mdx && html`<a class="button" href=${consoleUrl(entry)} target="_blank" rel="noopener"
        title=${`Open the call in the MDX console: its statement${requestCatalog(entry.request) ? ` on catalog ${requestCatalog(entry.request)}` : ''}, its answer, query plan and SQL statements`}>Open in MDX Console</a>`}
      <button class="link" onClick=${onClose}>Close</button></header>
    <div class="tabs" role="tablist">
      ${entry.mdx && html`<button role="tab" class=${tab === 'mdx' ? 'active' : ''} onClick=${() => setTab('mdx')}>MDX statement</button>`}
      ${entry.method === 'EXECUTE' && html`<button role="tab" class=${tab === 'plan' ? 'active' : ''} onClick=${() => setTab('plan')}>Query plan
        <span class="muted small">${!entry.status ? 'none' : entry.explain ? '' : 'none'}</span></button>`}
      <button role="tab" class=${tab === 'request' ? 'active' : ''} onClick=${() => setTab('request')}>SOAP request <span class="muted small">${size(entry.requestLength)}</span></button>
      <button role="tab" class=${tab === 'response' ? 'active' : ''} onClick=${() => setTab('response')}>SOAP response <span class="muted small">${entry.status ? size(entry.responseLength) : 'none'}</span></button>
      <button role="tab" class=${tab === 'sql' ? 'active' : ''} onClick=${() => setTab('sql')}>SQL statements <span class="muted small">${entry.status ? entry.sqlCount : 'none'}</span></button>
    </div>
    ${view ? html`<div class="body trace-view">
      ${!entry.status ? html`<div class="notice warn">No ${tab === 'plan' ? 'query plan' : 'statements'}: the call is still running, or it
        was aborted (a short dump, ST22).</div>`
        : tab === 'plan' ? html`<${PlanView} call=${entry} selection=${selection} setSelection=${setSelection} />`
        : html`<${SqlView} call=${entry} onNode=${(node) => show({ node })} onPhase=${(phase) => show({ phase })} />`}
    </div>` : html`<div class="body">
      <div class="row">
        ${xml && html`<label class="inline"><input type="checkbox" checked=${pretty} onChange=${(e) => setPretty(e.target.checked)} /> Indent XML</label>`}
        <span class="spacer"></span>
        ${copied && html`<span class=${`status ${copied === 'Copied' ? 'ok' : 'err'}`} role="status">${copied}</span>`}
        <button onClick=${copy} disabled=${!raw}>Copy</button>
        <button onClick=${save} disabled=${!raw}>Download</button>
      </div>
      ${tab === 'response' && !entry.status && html`<div class="notice warn">No response: the call is still running, or it was aborted (a short dump, ST22).</div>`}
      ${tab === 'response' && entry.responseTruncated && html`<div class="notice warn">The response has ${size(entry.responseLength)}; the first million characters are shown, Download gives all of it.</div>`}
      ${tab === 'response' && entry.fault && html`<div class="notice err">The answer is a SOAP fault.</div>`}
      <textarea class="trace" readonly spellcheck="false" value=${shown} aria-label=${tab}></textarea>
      ${entry.userAgent && html`<div class="muted small">User-Agent: <span class="mono">${entry.userAgent}</span></div>`}
    </div>`}
  </section>`;
}

function App() {
  const [state, setState] = useState(null);       // the answer of GET trace
  const [filter, setFilter] = useState('');
  const [kinds, setKinds] = useState({ DISCOVER: true, EXECUTE: true });  // the toggles: which calls are listed
  const [max, setMax] = useState(storedMax);
  const [selected, setSelected] = useState('');
  const [auto, setAuto] = useState(false);
  const [busy, setBusy] = useState('');
  const [error, setError] = useState('');
  const filterRef = useRef(filter);
  filterRef.current = filter;
  // one toggle on: the server lists only that method (its newest 200); both on: every call; both off: none
  const method = kinds.DISCOVER === kinds.EXECUTE ? '' : kinds.DISCOVER ? 'DISCOVER' : 'EXECUTE';
  const methodRef = useRef(method);
  methodRef.current = method;
  const maxRef = useRef(max);
  maxRef.current = max;
  const chooseMax = (n) => {
    setMax(n);
    try { localStorage.setItem(MAX_KEY, String(n)); } catch { /* not remembered */ }
  };
  const none = !kinds.DISCOVER && !kinds.EXECUTE;

  const load = (quiet) => {
    if (!quiet) setBusy('Reading the trace…');
    return api('GET', 'trace', { filter: filterRef.current, method: methodRef.current, max: maxRef.current })
      .then((data) => { setState(data); setError(''); }, (e) => setError(e.message))
      .finally(() => quiet || setBusy(''));
  };
  useEffect(() => { load(); }, [filter, method, max]);
  useEffect(() => {
    if (!auto) return undefined;
    const timer = setInterval(() => load(true), REFRESH_MS);
    return () => clearInterval(timer);
  }, [auto]);

  const post = (resource, params, message) => {
    if (message && !confirm(message)) return;
    setBusy('Saving…');
    api('POST', resource, { ...params, filter, method, max })
      .then((data) => { setState(data); setError(''); }, (e) => setError(e.message))
      .finally(() => setBusy(''));
  };
  const onSwitch = (how, user) => post(`trace/${how}`, { user });
  const clear = (user) => {
    post('trace/clear', { user }, user ? `Delete the traced calls of ${user}?` : 'Delete all traced calls of every user?');
    setSelected('');
  };

  const userNames = state ? [...new Set([...state.users.map((u) => u.user), ...state.calls.map((c) => c.user), filter].filter(Boolean))].sort() : [];
  return html`
    <div class="topbar"><h1>XMLA Trace</h1><span class="muted">the calls of the XMLA endpoint, per user</span>
      <span class="spacer"></span><a href=${`./${location.search}`}>Schema Builder</a><a href=${`console.html${location.search}`}>MDX Console</a>
      <a href=${`time.html${location.search}`}>Time Master Data</a></div>
    <div class="page"><div class="pane wide">
      ${error && html`<div class="notice err">${error}</div>`}
      ${state && html`<${Users} state=${state} onSwitch=${onSwitch} busy=${!!busy} />`}
      <div class=${selected ? 'trace-split' : ''}>
      <section class="section">
        <header><h2>Calls</h2>
          <select value=${filter} onChange=${(e) => { setFilter(e.target.value); setSelected(''); }} aria-label="User">
            <option value="">All users</option>
            ${userNames.map((u) => html`<option value=${u}>${u}</option>`)}
          </select>
          <div class="segmented" role="group" aria-label="Calls">
            ${[['DISCOVER', 'Discover'], ['EXECUTE', 'Execute']].map(([k, label]) => html`<button
              class=${kinds[k] ? 'active' : ''} aria-pressed=${kinds[k]} title=${`Show the ${label} calls`}
              onClick=${() => { setKinds((s) => ({ ...s, [k]: !s[k] })); setSelected(''); }}>${label}</button>`)}
          </div>
          <label class="inline">Show
            <select value=${max} onChange=${(e) => chooseMax(Number(e.target.value))} aria-label="Calls shown">
              ${MAX_CHOICES.map((n) => html`<option value=${n}>${n.toLocaleString()}</option>`)}
            </select> newest</label>
          <span class="spacer"></span>
          ${busy && html`<span class="status busy">${busy}</span>`}
          <label class="inline"><input type="checkbox" checked=${auto} onChange=${(e) => setAuto(e.target.checked)} /> Refresh every 5 s</label>
          <button onClick=${() => load()} disabled=${!!busy}>Refresh</button>
          ${filter && html`<button class="danger" onClick=${() => clear(filter)} disabled=${!!busy || !state?.calls.length}>Delete ${filter}'s calls</button>`}
          <button class="danger" onClick=${() => clear('')} disabled=${!!busy}>Delete all</button></header>
        <div class="scroll-x">${!state ? html`<div class="body muted">${busy || 'No data.'}</div>`
          : none ? html`<div class="body muted">Switch Discover or Execute on to list calls.</div>`
          : !state.calls.length ? html`<div class="body muted">No traced ${method ? `${what({ method })} ` : ''}calls${filter ? ` of ${filter}` : ''}.</div>` : html`
          <table>
            <thead><tr><th>Time</th><th class="wide-only">User</th><th>Call</th><th>Statement or rowset</th><th>Status</th>
              <th class="num">ms</th><th class="num" title="SQL statements and their milliseconds">SQL</th><th class="num">Response</th><th class="wide-only">Client</th></tr></thead>
            <tbody>${state.calls.map((c) => html`
              <tr class=${`clickable${c.id === selected ? ' selected' : ''}`} onClick=${() => setSelected(c.id === selected ? '' : c.id)}>
                <td class="small">${time(c.at)}</td>
                <td class="mono wide-only">${c.user}</td>
                <td>${what(c)}</td>
                <td class="mono small statement" title=${c.mdx}>${c.mdx ? firstLine(c.mdx) : c.type}</td>
                <td>${!c.status ? html`<span class="status warn">no answer</span>`
                  : c.fault ? html`<span class="status err">fault</span>`
                  : c.status === 200 ? html`<span class="status ok">ok</span>` : html`<span class="status err">${c.status}</span>`}</td>
                <td class="num">${c.status ? c.runtimeMs : ''}</td>
                <td class="num" title="SQL statements, their milliseconds">${c.status ? `${c.sqlCount} · ${c.sqlMs}` : ''}</td>
                <td class="num">${c.status ? size(c.responseLength) : ''}</td>
                <td class="mono small wide-only">${c.client}</td>
              </tr>`)}
            </tbody>
          </table>`}
        </div>
        ${state && !none && state.calls.length >= state.max && html`<div class="body muted small">The newest ${state.max.toLocaleString()} calls are shown; choose more next to Show.</div>`}
      </section>
      ${selected && html`<${Detail} id=${selected} onClose=${() => setSelected('')} />`}
      </div>
    </div></div>`;
}

const root = document.getElementById('app');
root.textContent = '';
render(html`<${App} />`, root);
