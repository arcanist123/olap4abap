// The master data of BW's calendar and fiscal time characteristics (docs/time-master-data.md): how complete their SID,
// attribute and text tables are for an interval (GET api/time), the values each misses (GET api/time/missing) and a
// button that fills them (POST api/time/fill, ZZXXMLA1_CL_TIME_MD). BW fills none: SIDs exist only for loaded values,
// attribute rows and texts not at all (BW's queries make the texts when they ask, the views read the tables).
// No build step: Preact with htm, vendored as one ES module; this file is what the server serves.
import { html, render, useState, useEffect } from './vendor/htm-preact-standalone.mjs';

const client = new URLSearchParams(location.search).get('sap-client');

async function api(method, resource, params = {}) {
  const query = new URLSearchParams(Object.entries(params).filter(([, v]) => v));
  if (client) query.set('sap-client', client);
  const response = await fetch(`api/${resource}?${query}`, { method });
  let data;
  try {
    data = await response.json();
  } catch {
    throw new Error(`${response.status} ${response.statusText}`);
  }
  if (!response.ok) throw new Error(data.error || `${response.status} ${response.statusText}`);
  return data;
}

// a characteristic without SID table is not active in BW: it cannot be filled; without attribute table only its SIDs
const inactive = (c) => c.missingTables.includes(c.sidTable);
const hasAttributes = (c) => c.attributeTable && !c.missingTables.includes(c.attributeTable);
const hasTexts = (c) => c.textTable && !c.missingTables.includes(c.textTable);
const missingCount = (c) => c.missingSids + c.missingAttributes + c.missingTexts;
const complete = (c) => !inactive(c) && missingCount(c) === 0;
const columns = 12;  // of the table, the detail rows span them

// the values a characteristic misses, per kind: SIDs, attribute rows, texts (GET api/time/missing)
function Missing({ entry }) {
  if (entry.error) return html`<div class="notice err">${entry.error}</div>`;
  if (!entry.data) return html`<span class="muted">Reading the missing values…</span>`;
  const kinds = [['sids', 'Without SID'], ['attributes', 'Without attribute row'], ['texts', 'Without text']];
  const shown = kinds.filter(([k]) => entry.data[k].count);
  if (!shown.length) return html`<span class="muted">Nothing is missing.</span>`;
  return shown.map(([k, label]) => {
    const part = entry.data[k];
    return html`<div style="margin: 4px 0">
      <strong>${label}</strong> <span class="muted small">(${part.count}${part.truncated ? `, the first ${part.values.length} shown` : ''})</span>
      <div class="mono small" style="white-space: normal; word-break: break-word">${part.values.join(', ')}</div></div>`;
  });
}

function App() {
  const [state, setState] = useState(null);       // the answer of GET time (or of the last fill)
  const [from, setFrom] = useState('');
  const [to, setTo] = useState('');
  const [selected, setSelected] = useState(new Set());
  const [busy, setBusy] = useState('');
  const [error, setError] = useState('');
  const [filled, setFilled] = useState(null);
  const [details, setDetails] = useState({});     // per characteristic shown: {data} or {error}, {} while it is read

  const readMissing = (name, interval) => {
    setDetails((d) => ({ ...d, [name]: {} }));
    api('GET', 'time/missing', { characteristic: name, ...interval })
      .then((data) => setDetails((d) => (d[name] ? { ...d, [name]: { data } } : d)),
        (e) => setDetails((d) => (d[name] ? { ...d, [name]: { error: e.message } } : d)));
  };
  const toggleMissing = (name) => {
    if (details[name]) setDetails((d) => { const next = { ...d }; delete next[name]; return next; });
    else readMissing(name, { from: state.from, to: state.to });
  };

  const show = (data) => {
    setState(data);
    setFrom(data.from);
    setTo(data.to);
    // the open lists of missing values are read again for the new state
    Object.keys(details).forEach((name) => readMissing(name, { from: data.from, to: data.to }));
  };
  const load = (params = {}) => {
    setBusy('Reading the tables…');
    setError('');
    return api('GET', 'time', params).then(show, (e) => setError(e.message)).finally(() => setBusy(''));
  };
  useEffect(() => { load(); }, []);
  // what is incomplete is selected when the state arrives the first time
  useEffect(() => {
    if (state && !selected.size && !filled) setSelected(new Set(state.characteristics.filter((c) => !complete(c) && !inactive(c)).map((c) => c.name)));
  }, [state]);

  const toggle = (name) => setSelected((s) => {
    const next = new Set(s);
    if (next.has(name)) next.delete(name); else next.add(name);
    return next;
  });
  const fill = () => {
    const names = state.characteristics.map((c) => c.name).filter((n) => selected.has(n));
    if (!confirm(`Create the SIDs, attribute rows and texts of ${names.join(', ')} for ${from} to ${to}?\n\n`
      + 'Every view on these tables then has the new periods as members.')) return;
    setBusy('Filling…');
    setError('');
    api('POST', 'time/fill', { from, to, characteristics: names.join(',') })
      .then((data) => { setFilled(data.filled); show(data); }, (e) => setError(e.message))
      .finally(() => setBusy(''));
  };

  const changed = state && (from !== state.from || to !== state.to);
  return html`
    <div class="topbar"><h1>Time Master Data</h1><span class="muted">SIDs and attributes of BW's time characteristics</span>
      <span class="spacer"></span><a href=${`./${location.search}`}>Schema Builder</a><a href=${`console.html${location.search}`}>MDX Console</a><a href=${`trace.html${location.search}`}>Trace</a></div>
    <div class="page"><div class="pane">
      ${error && html`<div class="notice err">${error}</div>`}
      <section class="section">
        <header><h2>Interval</h2><span class="spacer"></span>
          <span class="muted small">default: BW's interval of the virtual time hierarchies (RSRHIERARCHYVIRT)</span></header>
        <div class="body"><div class="row">
          <label class="muted" for="from">From</label><input id="from" type="date" value=${from} onInput=${(e) => setFrom(e.target.value)} />
          <label class="muted" for="to">to</label><input id="to" type="date" value=${to} onInput=${(e) => setTo(e.target.value)} />
          <button onClick=${() => load({ from, to })} disabled=${!!busy}>${changed ? 'Show for this interval' : 'Refresh'}</button>
          ${state && html`<span class="muted small">working days: factory calendar <span class="mono">${state.calendar}</span></span>`}
        </div></div>
      </section>
      <section class="section">
        <header><h2>Characteristics</h2><span class="spacer"></span>
          ${busy && html`<span class="status busy">${busy}</span>`}
          <button class="primary" onClick=${fill} disabled=${!!busy || !state || !selected.size || changed}
            title=${changed ? 'Show the state for this interval first' : ''}>Fill selected</button></header>
        <div class="scroll-x">${!state ? html`<div class="body muted">${busy || 'No data.'}</div>` : html`
          <table>
            <thead><tr><th></th><th>Characteristic</th><th>Tables</th><th class="num">With SID</th><th class="num">In interval</th>
              <th class="num">Missing SIDs</th><th class="num">Attribute rows</th><th class="num">Missing rows</th>
              <th class="num">Texts</th><th class="num">Missing texts</th><th>Values with SID</th><th></th></tr></thead>
            <tbody>${state.characteristics.map((c) => html`
              <tr class=${inactive(c) ? '' : 'clickable'} onClick=${() => !inactive(c) && toggle(c.name)}>
                <td><input type="checkbox" checked=${selected.has(c.name)} disabled=${inactive(c)} onClick=${(e) => e.stopPropagation()}
                  onChange=${() => toggle(c.name)} aria-label=${`Select ${c.name}`} /></td>
                <td><strong class="mono">${c.name}</strong>${complete(c) && html` <span class="status ok">complete</span>`}
                  ${inactive(c) && html` <span class="status err">not active</span>`}</td>
                <td class="mono small">${[c.sidTable, c.attributeTable, c.textTable].filter(Boolean).map((t, i) => html`${i ? html`<br />` : ''}${t}${
                  c.missingTables.includes(t) ? html` <span class="status err" title="no such table in this system">missing</span>` : ''}`)}</td>
                <td class="num">${inactive(c) ? '' : c.sids}</td>
                <td class="num">${c.expected}</td>
                <td class="num">${c.missingSids || ''}</td>
                <td class="num">${hasAttributes(c) ? c.attributes : html`<span class="muted">none</span>`}</td>
                <td class="num">${c.missingAttributes || ''}</td>
                <td class="num">${hasTexts(c) ? c.texts : html`<span class="muted">none</span>`}</td>
                <td class="num">${c.missingTexts || ''}</td>
                <td class="mono small">${c.first && `${c.first} … ${c.last}`}</td>
                <td>${!inactive(c) && missingCount(c) > 0 && html`<button class="link small" onClick=${(e) => { e.stopPropagation(); toggleMissing(c.name); }}
                  aria-expanded=${!!details[c.name]}>${details[c.name] ? 'Hide missing' : 'Show missing'}</button>`}</td>
              </tr>
              ${details[c.name] && html`<tr><td></td><td colspan=${columns - 1}><${Missing} entry=${details[c.name]} /></td></tr>`}`)}
            </tbody>
          </table>`}
        </div>
      </section>
      ${filled && html`<section class="section">
        <header><h2>Last fill</h2></header>
        <div class="body">${filled.map((f) => html`<div class=${`notice ${f.error ? 'err' : 'ok'}`}>
          <span class="mono">${f.name}</span>: ${f.error || `${f.createdSids} SIDs created, ${f.attributeRows} attribute rows and ${f.textRows} texts written${f.warning ? `; ${f.warning}` : ''}`}</div>`)}
        </div>
      </section>`}
      <p class="muted small">0FISCYEAR and 0FISCPER are filled for the fiscal year variant K4, as 0CALYEAR and 0CALMONTH: its
        years and its periods 001 to 012 (the months); BW adds period 000 and the special periods of a year with its first
        period. 0CALDAY is not filled here.
        Values with a SID outside the interval get their attribute rows and texts too. Texts are written in English, the
        language of the views, as BW's queries make them (JAN 1997 and January 1997, Q1 1997, Monday; the initial value
        Not assigned); 0CALYEAR, 0CALWEEK, 0HALFYEAR1 and 0FISCPER have no text table. A characteristic whose SID table this
        system does not have is not active in BW and cannot be filled; one without attribute table gets its SIDs only.</p>
    </div></div>`;
}

const root = document.getElementById('app');
root.textContent = '';
render(html`<${App} />`, root);
