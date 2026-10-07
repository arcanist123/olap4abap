// The master data of BW's calendar time characteristics (docs/time-master-data.md): how complete their SID and
// attribute tables are for an interval (GET api/time), and a button that fills them (POST api/time/fill,
// ZZXXMLA1_CL_TIME_MD). BW fills neither: SIDs exist only for loaded values, attribute rows not at all.
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

const complete = (c) => c.missingSids === 0 && c.missingAttributes === 0;

function App() {
  const [state, setState] = useState(null);       // the answer of GET time (or of the last fill)
  const [from, setFrom] = useState('');
  const [to, setTo] = useState('');
  const [selected, setSelected] = useState(new Set());
  const [busy, setBusy] = useState('');
  const [error, setError] = useState('');
  const [filled, setFilled] = useState(null);

  const show = (data) => {
    setState(data);
    setFrom(data.from);
    setTo(data.to);
  };
  const load = (params = {}) => {
    setBusy('Reading the tables…');
    setError('');
    return api('GET', 'time', params).then(show, (e) => setError(e.message)).finally(() => setBusy(''));
  };
  useEffect(() => { load(); }, []);
  // what is incomplete is selected when the state arrives the first time
  useEffect(() => {
    if (state && !selected.size && !filled) setSelected(new Set(state.characteristics.filter((c) => !complete(c)).map((c) => c.name)));
  }, [state]);

  const toggle = (name) => setSelected((s) => {
    const next = new Set(s);
    if (next.has(name)) next.delete(name); else next.add(name);
    return next;
  });
  const fill = () => {
    const names = state.characteristics.map((c) => c.name).filter((n) => selected.has(n));
    if (!confirm(`Create the SIDs and attribute rows of ${names.join(', ')} for ${from} to ${to}?\n\n`
      + 'Every view on these tables then has the new periods as members.')) return;
    setBusy('Filling…');
    setError('');
    api('POST', 'time/fill', { from, to, characteristics: names.join(',') })
      .then((data) => { setFilled(data.filled); show(data); }, (e) => setError(e.message))
      .finally(() => setBusy(''));
  };

  const changed = state && (from !== state.from || to !== state.to);
  return html`
    <div class="topbar"><h1>Time Master Data</h1><span class="muted">SIDs and attributes of BW's calendar characteristics</span>
      <span class="spacer"></span><a href=${`./${location.search}`}>Schema Builder</a><a href=${`console.html${location.search}`}>MDX Console</a></div>
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
              <th class="num">Missing SIDs</th><th class="num">Attribute rows</th><th class="num">Missing rows</th><th>Values with SID</th></tr></thead>
            <tbody>${state.characteristics.map((c) => html`
              <tr class="clickable" onClick=${() => toggle(c.name)}>
                <td><input type="checkbox" checked=${selected.has(c.name)} onClick=${(e) => e.stopPropagation()} onChange=${() => toggle(c.name)}
                  aria-label=${`Select ${c.name}`} /></td>
                <td><strong class="mono">${c.name}</strong>${complete(c) && html` <span class="status ok">complete</span>`}</td>
                <td class="mono small">${c.sidTable}${c.attributeTable && html`<br />${c.attributeTable}`}</td>
                <td class="num">${c.sids}</td>
                <td class="num">${c.expected}</td>
                <td class="num">${c.missingSids || ''}</td>
                <td class="num">${c.attributeTable ? c.attributes : html`<span class="muted">none</span>`}</td>
                <td class="num">${c.missingAttributes || ''}</td>
                <td class="mono small">${c.first && `${c.first} … ${c.last}`}</td>
              </tr>`)}
            </tbody>
          </table>`}
        </div>
      </section>
      ${filled && html`<section class="section">
        <header><h2>Last fill</h2></header>
        <div class="body">${filled.map((f) => html`<div class=${`notice ${f.error ? 'err' : 'ok'}`}>
          <span class="mono">${f.name}</span>: ${f.error || `${f.createdSids} SIDs created, ${f.attributeRows} attribute rows written`}</div>`)}
        </div>
      </section>`}
      <p class="muted small">The fiscal characteristics (0FISC*, they depend on a fiscal year variant) and 0CALDAY are not filled here.
        Values with a SID outside the interval get their attribute rows too.</p>
    </div></div>`;
}

const root = document.getElementById('app');
root.textContent = '';
render(html`<${App} />`, root);
