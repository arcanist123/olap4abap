// The schema builder (docs/schema-generator.md, UI): proposes a Mondrian schema for a BW InfoProvider or reopens an
// accepted one, lets the user edit it and accepts it through the API below this folder (ZZXXMLA1_CL_SCHEMA_API).
// The schema XML is the model: it is edited as a DOM (DOMParser) and sent back as text, the server never parses JSON.
// No build step: Preact with htm, vendored as one ES module; this file is what the server serves.
import { html, render, useState, useEffect, useMemo, useRef, useCallback } from './vendor/htm-preact-standalone.mjs';

const TIME_TYPES = ['TimeYears', 'TimeHalfYears', 'TimeQuarters', 'TimeMonths', 'TimeWeeks', 'TimeDays', 'TimeHours',
  'TimeMinutes', 'TimeSeconds', 'TimeUndefined'];
// what the engine evaluates (ZZXXMLA1_CL_MDX_FACTS): count, everything else is summed
const AGGREGATORS = ['sum', 'count'];
const FORMATS = ['Standard', '#,###', '#,##0', '#,##0.00', 'Currency', 'Percent', '0.0%'];
// a catalog name is a file name too (ZZXXMLA1_CL_SCHEMA_API, check_catalog_name)
const CATALOG_NAME = /^[A-Za-z0-9_-][A-Za-z0-9_.-]*$/;

// ---------------------------------------------------------------------------------------------------------- API

const client = new URLSearchParams(location.search).get('sap-client');

async function api(method, resource, params = {}, body) {
  const query = new URLSearchParams(params);
  if (client) query.set('sap-client', client);
  const response = await fetch(`api/${resource}?${query}`, {
    method,
    body,
    headers: body == null ? {} : { 'Content-Type': 'application/xml; charset=utf-8' },
  });
  let data;
  try {
    data = await response.json();
  } catch {
    throw new Error(`${response.status} ${response.statusText}`);
  }
  if (!response.ok) throw new Error(data.error || `${response.status} ${response.statusText}`);
  return data;
}

// ---------------------------------------------------------------------------------------------------------- XML

function parseXml(text) {
  const doc = new DOMParser().parseFromString(text, 'application/xml');
  const error = doc.getElementsByTagName('parsererror')[0];
  if (error) throw new Error(error.textContent.trim().split('\n').filter(Boolean).slice(0, 2).join(' '));
  if (doc.documentElement.tagName !== 'Schema') throw new Error('The root element is not <Schema>');
  return doc;
}

const escapeText = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const escapeAttr = (s) => escapeText(s).replace(/"/g, '&quot;').replace(/\n/g, '&#10;').replace(/\t/g, '&#9;');

// The schema as text, indented by two spaces; whitespace between elements is not kept, comments are.
function serialize(doc) {
  const lines = [];
  const walk = (node, depth) => {
    const pad = '  '.repeat(depth);
    if (node.nodeType === Node.COMMENT_NODE) return lines.push(`${pad}<!--${node.data}-->`);
    if (node.nodeType === Node.CDATA_SECTION_NODE) return lines.push(`${pad}<![CDATA[${node.data}]]>`);
    if (node.nodeType === Node.TEXT_NODE) return node.data.trim() && lines.push(pad + escapeText(node.data.trim()));
    if (node.nodeType !== Node.ELEMENT_NODE) return;
    const attrs = [...node.attributes].map((a) => ` ${a.name}="${escapeAttr(a.value)}"`).join('');
    const content = [...node.childNodes].filter((c) => c.nodeType !== Node.TEXT_NODE || c.data.trim());
    if (!content.length) return lines.push(`${pad}<${node.tagName}${attrs}/>`);
    if (content.length === 1 && content[0].nodeType === Node.TEXT_NODE) {
      return lines.push(`${pad}<${node.tagName}${attrs}>${escapeText(content[0].data.trim())}</${node.tagName}>`);
    }
    lines.push(`${pad}<${node.tagName}${attrs}>`);
    content.forEach((c) => walk(c, depth + 1));
    lines.push(`${pad}</${node.tagName}>`);
  };
  doc.childNodes.forEach((n) => walk(n, 0));
  return lines.join('\n') + '\n';
}

const kids = (el, tag) => (el ? [...el.children].filter((c) => c.tagName === tag) : []);
const attr = (el, name) => (el && el.getAttribute(name)) ?? '';
function setAttr(el, name, value) {
  if (value === '' || value == null) el.removeAttribute(name);
  else el.setAttribute(name, value);
}
function create(doc, tag, attrs) {
  const el = doc.createElement(tag);
  Object.entries(attrs).forEach(([name, value]) => setAttr(el, name, value));
  return el;
}
// inserts el after the last child of the parent with one of the tags, else as its last child
function insertAfterLast(parent, el, tags) {
  const last = [...parent.children].filter((c) => tags.includes(c.tagName)).pop();
  parent.insertBefore(el, last ? last.nextSibling : null);
}
// moves el before its previous (-1) or after its next (+1) sibling of the same tag
function move(el, step) {
  const siblings = kids(el.parentNode, el.tagName);
  const other = siblings[siblings.indexOf(el) + step];
  if (!other) return;
  if (step < 0) el.parentNode.insertBefore(el, other);
  else el.parentNode.insertBefore(other, el);
}
const isTrue = (el, name, fallback) => (el.hasAttribute(name) ? attr(el, name) === 'true' : fallback);

// --------------------------------------------------------------------------------------------- the schema model

const schemaOf = (doc) => doc.documentElement;
const sharedDims = (doc) => kids(schemaOf(doc), 'Dimension');
const cubesOf = (doc) => kids(schemaOf(doc), 'Cube');
const isTime = (dim) => attr(dim, 'type') === 'TimeDimension';
const attributesOf = (dim) => kids(dim, 'DimensionAttribute');
const hierarchiesOf = (dim) => kids(dim, 'Hierarchy');
const keyColumn = (attribute) => attr(kids(attribute, 'KeyColumn')[0], 'columnName');
const usagesOf = (doc, dim) =>
  cubesOf(doc).flatMap((cube) => kids(cube, 'DimensionUsage').filter((u) => attr(u, 'source') === attr(dim, 'name'))
    .map((usage) => ({ cube, usage })));
const isShared = (dim) => dim.parentNode.tagName === 'Schema';

// The selection is a path, so it survives undo (which replaces the document).
function resolve(doc, sel) {
  if (sel.kind === 'cube') return cubesOf(doc)[sel.ci];
  if (sel.kind === 'dim') return sel.ci == null ? sharedDims(doc)[sel.di] : kids(cubesOf(doc)[sel.ci], 'Dimension')[sel.di];
  return schemaOf(doc);
}

// The time suggestions of a proposal, keyed by the view and column, which the UI never changes (names it does).
function suggestionKeys(doc, suggestions) {
  const keys = new Map();
  for (const s of suggestions || []) {
    const dim = sharedDims(doc).find((d) => attr(d, 'name') === s.dimension);
    const attribute = attributesOf(dim).find((a) => attr(a, 'name') === s.attribute);
    if (attribute) keys.set(`${attr(dim, 'table')}|${keyColumn(attribute)}`, s.levelType);
  }
  return keys;
}
const suggestionFor = (suggestions, dim, attribute) => suggestions.get(`${attr(dim, 'table')}|${keyColumn(attribute)}`);

function setTimeDimension(dim, on, suggestions) {
  const attributes = attributesOf(dim);
  if (on) {
    dim.setAttribute('type', 'TimeDimension');
    // Mondrian requires a time level type on every level of a time dimension, the attribute hierarchies' too
    for (const a of attributes) {
      if (!TIME_TYPES.includes(attr(a, 'levelType'))) a.setAttribute('levelType', suggestionFor(suggestions, dim, a) || 'TimeUndefined');
    }
    for (const h of hierarchiesOf(dim)) {
      for (const level of kids(h, 'Level')) {
        if (TIME_TYPES.includes(attr(level, 'levelType'))) continue;
        const source = attributes.find((a) => attr(a, 'name') === attr(level, 'sourceAttribute'));
        level.setAttribute('levelType', source ? attr(source, 'levelType') : 'TimeUndefined');
      }
    }
  } else {
    dim.removeAttribute('type');
    attributes.forEach((a) => a.setAttribute('levelType', 'Regular'));
    hierarchiesOf(dim).forEach((h) => kids(h, 'Level').forEach((level) => level.removeAttribute('levelType')));
  }
}

function renameDimension(doc, dim, name) {
  const old = attr(dim, 'name');
  dim.setAttribute('name', name);
  if (isShared(dim)) {
    for (const cube of cubesOf(doc)) {
      for (const usage of kids(cube, 'DimensionUsage').filter((u) => attr(u, 'source') === old)) {
        usage.setAttribute('source', name);
        if (attr(usage, 'name') === old) usage.setAttribute('name', name);
      }
    }
  }
  for (const h of hierarchiesOf(dim)) {
    const member = attr(h, 'defaultMember');
    if (member.startsWith(`[${old}]`)) h.setAttribute('defaultMember', `[${name}]${member.slice(old.length + 2)}`);
  }
}

function renameAttribute(dim, attribute, name) {
  const old = attr(attribute, 'name');
  attribute.setAttribute('name', name);
  for (const h of hierarchiesOf(dim)) {
    for (const level of kids(h, 'Level')) {
      if (attr(level, 'sourceAttribute') === old) level.setAttribute('sourceAttribute', name);
      kids(level, 'Property').filter((p) => attr(p, 'sourceAttribute') === old).forEach((p) => p.setAttribute('sourceAttribute', name));
    }
  }
}

function setAttributeLevelType(dim, attribute, levelType) {
  const old = attr(attribute, 'levelType');
  attribute.setAttribute('levelType', levelType);
  // the levels on the attribute follow, unless they were given another type
  for (const h of hierarchiesOf(dim)) {
    for (const level of kids(h, 'Level')) {
      if (attr(level, 'sourceAttribute') === attr(attribute, 'name') && attr(level, 'levelType') === old) {
        level.setAttribute('levelType', levelType);
      }
    }
  }
}

// an attribute is an attribute hierarchy unless attributeHierarchyEnabled is false; the proposal makes only the key one
const hasHierarchy = (attribute) => isTrue(attribute, 'attributeHierarchyEnabled', true);
const setAttributeHierarchy = (attribute, on) => setAttr(attribute, 'attributeHierarchyEnabled', on ? '' : 'false');

const required = (what) => (value) => (value.trim() ? '' : `${what} needs a name`);
const unique = (what, others) => (value) =>
  required(what)(value) || (others.includes(value) ? `${what} '${value}' exists already` : '');

// ------------------------------------------------------------------------------------------------- components

function TextField({ value = '', onCommit, validate, placeholder, mono, readOnly, list, title, size }) {
  const [text, setText] = useState(value);
  const [error, setError] = useState('');
  useEffect(() => {
    setText(value);
    setError('');
  }, [value]);
  const commit = () => {
    if (text === value) return setError('');
    const problem = validate ? validate(text) : '';
    if (problem) return setError(problem);
    setError('');
    onCommit(text);
  };
  if (readOnly) return html`<input type="text" class=${mono ? 'mono' : ''} value=${value} readOnly size=${size} title=${title || value} />`;
  return html`<span>
    <input type="text" class=${[mono && 'mono', error && 'invalid'].filter(Boolean).join(' ')} value=${text}
      placeholder=${placeholder} list=${list} size=${size} title=${error || title || ''}
      onInput=${(e) => setText(e.target.value)} onChange=${commit}
      onKeyDown=${(e) => { if (e.key === 'Escape') { setText(value); setError(''); } }} />
    ${error && html`<div class="field-error">${error}</div>`}
  </span>`;
}

function Select({ value, options, onChange, title }) {
  const values = options.includes(value) || value === '' ? options : [value, ...options];
  return html`<select value=${value} title=${title} onChange=${(e) => onChange(e.target.value)}>
    ${value === '' && html`<option value="">–</option>`}
    ${values.map((o) => html`<option value=${o}>${o}</option>`)}
  </select>`;
}

function Check({ checked, onChange, label, title, disabled }) {
  return html`<label class="switch" title=${title}>
    <input type="checkbox" checked=${checked} disabled=${disabled} onChange=${(e) => onChange(e.target.checked)} />${label}
  </label>`;
}

function Dialog({ title, children, footer, onClose }) {
  useEffect(() => {
    const onKey = (e) => e.key === 'Escape' && onClose && onClose();
    addEventListener('keydown', onKey);
    return () => removeEventListener('keydown', onKey);
  }, [onClose]);
  return html`<div class="backdrop" onClick=${(e) => e.target === e.currentTarget && onClose && onClose()}>
    <div class="dialog" role="dialog" aria-modal="true">
      <header><h2>${title}</h2></header>
      <div class="body">${children}</div>
      <footer>${footer}</footer>
    </div>
  </div>`;
}

// ------------------------------------------------------------------------------------------------- start page

function formatTime(iso) {
  if (!iso) return '';
  const d = new Date(iso);
  return isNaN(d) ? iso : d.toLocaleString();
}

function Start({ onOpen, opening, error }) {
  const [providers, setProviders] = useState(null);
  const [schemas, setSchemas] = useState(null);
  const [loadError, setLoadError] = useState('');
  const [filter, setFilter] = useState('');
  const [removing, setRemoving] = useState(null);
  const loadSchemas = () => api('GET', 'schemas').then((d) => setSchemas(d.schemas), (e) => setLoadError(e.message));
  useEffect(() => {
    api('GET', 'providers').then((d) => setProviders(d.providers), (e) => setLoadError(e.message));
    loadSchemas();
  }, []);
  const words = filter.toLowerCase().split(/\s+/).filter(Boolean);
  const shown = (providers || []).filter((p) =>
    words.every((w) => `${p.name} ${p.text} ${p.infoarea} ${p.kind}`.toLowerCase().includes(w)));

  return html`
    <div class="topbar"><h1>Schema Builder</h1><span class="muted">Mondrian schemas for BW InfoProviders</span></div>
    <div class="page">
    ${(error || loadError) && html`<div style="padding: 16px 16px 0"><div class="notice err">${error || loadError}</div></div>`}
    ${opening && html`<div style="padding: 16px 16px 0"><div class="notice info">${opening}</div></div>`}
    <div class="start">
      <section class="card">
        <header><h2>Accepted schemas</h2><span class="spacer"></span><span class="muted small">catalogs of /WEB-INF/datasources.xml</span></header>
        <div class="scroll">
          ${schemas == null ? html`<div class="body muted">Loading…</div>` : !schemas.length ? html`<div class="body muted">No catalogs yet.</div>` : html`
          <table>
            <thead><tr><th>Catalog</th><th>Schema file</th><th>Changed</th><th></th></tr></thead>
            <tbody>${schemas.map((s) => html`
              <tr class=${s.exists ? 'clickable' : ''} title=${s.exists ? `Edit ${s.catalog}` : 'The schema file is missing'}
                onClick=${() => s.exists && !opening && onOpen({ kind: 'schema', name: s.catalog })}>
                <td><strong>${s.catalog}</strong><div class="muted small">${s.dataSource}</div></td>
                <td class="mono">${s.file}${!s.exists && html` <span class="kind">missing</span>`}</td>
                <td class="small">${formatTime(s.changedAt)}<div class="muted">${s.changedBy}</div></td>
                <td><button class="danger" title=${`Remove catalog ${s.catalog}`} disabled=${!!opening}
                  onClick=${(e) => { e.stopPropagation(); setRemoving({ kind: 'confirm', schema: s }); }}>Remove…</button></td>
              </tr>`)}
            </tbody>
          </table>`}
        </div>
      </section>
      <section class="card">
        <header>
          <h2>Propose from a provider</h2><span class="spacer"></span>
          <input type="search" placeholder="Filter by name, text, InfoArea" value=${filter} onInput=${(e) => setFilter(e.target.value)}
            aria-label="Filter providers" style="width: min(260px, 100%)" />
        </header>
        <div class="scroll">
          ${providers == null ? html`<div class="body muted">Loading…</div>` : html`
          <table>
            <thead><tr><th>Provider</th><th>Text</th><th>InfoArea</th></tr></thead>
            <tbody>${shown.map((p) => html`
              <tr class="clickable" title=${`Propose a schema for ${p.name}`} onClick=${() => !opening && onOpen({ kind: 'proposal', name: p.name })}>
                <td><strong class="mono">${p.name}</strong> <span class="kind">${p.kind}</span></td>
                <td>${p.text}</td>
                <td class="mono small">${p.infoarea}</td>
              </tr>`)}
            </tbody>
          </table>
          ${!shown.length && html`<div class="body muted">No provider matches.</div>`}`}
        </div>
      </section>
    </div>
    </div>
    ${removing && html`<${RemoveDialog} dialog=${removing} onClose=${() => setRemoving(null)}
      onRemove=${async () => {
        const s = removing.schema;
        setRemoving({ kind: 'removing', schema: s });
        try {
          const result = await api('POST', 'remove', { catalog: s.catalog });
          setRemoving({ kind: 'done', schema: s, result });
        } catch (e) {
          setRemoving({ kind: 'failed', schema: s, message: e.message });
        }
        loadSchemas();
      }} />`}`;
}

function RemoveDialog({ dialog, onRemove, onClose }) {
  const s = dialog.schema;
  if (dialog.kind === 'confirm') {
    return html`<${Dialog} title="Remove the schema" onClose=${onClose} footer=${html`
      <button onClick=${onClose}>Cancel</button>
      <button class="primary" onClick=${onRemove}>Remove ${s.catalog}</button>`}>
      <div class="notice warn">Catalog <strong class="mono">${s.catalog}</strong> and its cubes are removed: the next XMLA request
        does not see them. This cannot be undone here; the schema can be proposed and accepted again.</div>
      <div class="form">
        <label>Data source</label><span>${s.dataSource}</span>
        <label>Schema file</label><span class="mono">${s.file}${s.exists ? ' (deleted)' : ' (missing)'}</span>
        <label>Views</label><span>kept: other schemas can use them</span>
      </div>
    <//>`;
  }
  if (dialog.kind === 'removing') {
    return html`<${Dialog} title="Removing…" footer=${''}><span class="muted">Removing ${s.catalog}…</span><//>`;
  }
  if (dialog.kind === 'failed') {
    return html`<${Dialog} title="Not removed" onClose=${onClose} footer=${html`<button onClick=${onClose}>Close</button>`}>
      <div class="notice err">${dialog.message}</div><span class="muted">Nothing was changed.</span>
    <//>`;
  }
  const r = dialog.result;
  return html`<${Dialog} title="Removed" onClose=${onClose} footer=${html`<button class="primary" onClick=${onClose}>Close</button>`}>
    <div class="notice ok">Catalog <strong class="mono">${r.catalog}</strong> is removed from /WEB-INF/datasources.xml.</div>
    <span class="muted">${r.removedFiles.length ? html`Deleted ${r.removedFiles.map((f, i) => html`${i > 0 && ', '}<span class="mono">${f}</span>`)}.` : 'No schema file deleted.'}</span>
  <//>`;
}

// ----------------------------------------------------------------------------------------------------- panes

function SchemaPane({ doc, edit, source, catalog, notes }) {
  const schema = schemaOf(doc);
  return html`<div class="pane">
    <div class="form">
      <label>Schema name</label>
      <${TextField} value=${attr(schema, 'name')} validate=${required('The schema')} onCommit=${(v) => edit(() => schema.setAttribute('name', v))} />
      <label>Description</label>
      <${TextField} value=${attr(schema, 'description')} onCommit=${(v) => edit(() => setAttr(schema, 'description', v))} />
      ${source.kind === 'proposal' && html`
        <label>Provider</label><span><strong class="mono">${source.name}</strong> <span class="kind">${source.providerKind}</span> ${source.text}</span>
        <label>Fact table</label><span class="mono">${source.factTable}</span>`}
      ${source.kind === 'schema' && html`
        <label>Schema file</label><span class="mono">${source.file}</span>
        <label>Last accepted</label><span>${formatTime(source.changedAt)} ${source.changedBy && html`<span class="muted">by ${source.changedBy}</span>`}</span>`}
    </div>
    <div class="notice info">
      Every attribute of a dimension is already an attribute hierarchy, so the schema is usable as proposed. Rename what
      reads badly, drop what nobody needs, mark a dimension as time, and build user hierarchies (e.g. Country › State ›
      City) from attributes. The server checks the schema as you edit; <strong>Accept</strong> generates the views,
      writes the schema file and registers catalog <strong class="mono">${catalog || '?'}</strong>.
    </div>
    ${notes.length > 0 && html`<section class="section">
      <header><h3>Not proposed</h3></header>
      <div class="body"><ul class="plain">${notes.map((n) => html`<li><span class="mono">${n.iobjnm}</span>: ${n.reason}</li>`)}</ul></div>
    </section>`}
  </div>`;
}

function CubePane({ doc, edit, cube, select }) {
  const measures = kids(cube, 'Measure');
  const usages = kids(cube, 'DimensionUsage');
  const privates = kids(cube, 'Dimension');
  const known = ['Table', 'DimensionUsage', 'Dimension', 'Measure', 'Annotations'];
  const others = [...cube.children].filter((c) => !known.includes(c.tagName)).map((c) => c.tagName);
  const measureNames = measures.map((m) => attr(m, 'name'));
  const dimNames = [...usages, ...privates].map((u) => attr(u, 'name'));
  const defaultMeasure = attr(cube, 'defaultMeasure');

  const removeMeasure = (m) => edit(() => {
    const name = attr(m, 'name');
    m.remove();
    if (defaultMeasure === name) setAttr(cube, 'defaultMeasure', attr(kids(cube, 'Measure')[0], 'name'));
  });

  return html`<div class="pane">
    <div class="form">
      <label>Cube name</label>
      <${TextField} value=${attr(cube, 'name')} validate=${unique('A cube', cubesOf(doc).filter((c) => c !== cube).map((c) => attr(c, 'name')))}
        onCommit=${(v) => edit(() => cube.setAttribute('name', v))} />
      <label>Caption</label>
      <${TextField} value=${attr(cube, 'caption')} placeholder=${attr(cube, 'name')} onCommit=${(v) => edit(() => setAttr(cube, 'caption', v))} />
      <label>Fact table</label>
      <${TextField} readOnly mono value=${attr(kids(cube, 'Table')[0], 'name')} />
      <label>Default measure</label>
      <${Select} value=${defaultMeasure} options=${measureNames} onChange=${(v) => edit(() => setAttr(cube, 'defaultMeasure', v))} />
    </div>

    <section class="section">
      <header><h3>Measures</h3><span class="spacer"></span><span class="muted small">key figures of the fact table</span></header>
      <div class="body scroll-x"><table>
        <thead><tr><th>Name</th><th>Column</th><th>Aggregator</th><th>Format string</th><th>Visible</th><th></th></tr></thead>
        <tbody>${measures.map((m, i) => html`<tr key=${i}>
          <td><${TextField} value=${attr(m, 'name')} validate=${unique('A measure', measureNames.filter((n) => n !== attr(m, 'name')))}
            onCommit=${(v) => edit(() => { if (defaultMeasure === attr(m, 'name')) cube.setAttribute('defaultMeasure', v); m.setAttribute('name', v); })} /></td>
          <td class="mono small">${attr(m, 'column')}</td>
          <td><${Select} value=${attr(m, 'aggregator')} options=${AGGREGATORS} onChange=${(v) => edit(() => m.setAttribute('aggregator', v))}
            title="The engine evaluates sum and count" /></td>
          <td><${TextField} value=${attr(m, 'formatString')} list="formats" placeholder="Standard" mono
            onCommit=${(v) => edit(() => setAttr(m, 'formatString', v))} /></td>
          <td><input type="checkbox" checked=${isTrue(m, 'visible', true)} aria-label="Visible"
            onChange=${(e) => edit(() => m.setAttribute('visible', String(e.target.checked)))} /></td>
          <td class="actions">
            <button class="icon" title="Up" disabled=${i === 0} onClick=${() => edit(() => move(m, -1))}>↑</button>
            <button class="icon" title="Down" disabled=${i === measures.length - 1} onClick=${() => edit(() => move(m, 1))}>↓</button>
            <button class="icon danger" title="Remove the measure" disabled=${measures.length === 1} onClick=${() => removeMeasure(m)}>✕</button>
          </td>
        </tr>`)}</tbody>
      </table></div>
    </section>

    <section class="section">
      <header><h3>Dimensions of the cube</h3><span class="spacer"></span><span class="muted small">joined on the fact table's foreign key</span></header>
      <div class="body scroll-x"><table>
        <thead><tr><th>Name in the cube</th><th>Dimension</th><th>Foreign key</th><th></th></tr></thead>
        <tbody>
          ${usages.map((u, i) => {
            const di = sharedDims(doc).findIndex((d) => attr(d, 'name') === attr(u, 'source'));
            return html`<tr key=${'u' + i}>
              <td><${TextField} value=${attr(u, 'name')} validate=${unique('A dimension', dimNames.filter((n) => n !== attr(u, 'name')))}
                onCommit=${(v) => edit(() => u.setAttribute('name', v))} /></td>
              <td>${di >= 0 ? html`<button class="link" onClick=${() => select({ kind: 'dim', ci: null, di })}>${attr(u, 'source')}</button>`
                : html`<span class="field-error">${attr(u, 'source')} (missing)</span>`}</td>
              <td class="mono small">${attr(u, 'foreignKey')}</td>
              <td class="actions"><button class="icon danger" title="Remove from the cube (the dimension stays)"
                onClick=${() => confirm(`Remove '${attr(u, 'name')}' from cube '${attr(cube, 'name')}'?`) && edit(() => u.remove())}>✕</button></td>
            </tr>`;
          })}
          ${privates.map((d, i) => html`<tr key=${'p' + i}>
            <td>${attr(d, 'name')}</td>
            <td><button class="link" onClick=${() => select({ kind: 'dim', ci: cubesOf(doc).indexOf(cube), di: i })}>private dimension</button></td>
            <td class="mono small">${attr(d, 'foreignKey')}</td><td></td>
          </tr>`)}
        </tbody>
      </table></div>
    </section>
    ${others.length > 0 && html`<div class="notice warn">The cube also has ${[...new Set(others)].join(', ')}; edit them on the XML tab.</div>`}
  </div>`;
}

function DimensionPane({ doc, edit, dim, sel, select, suggestions }) {
  const time = isTime(dim);
  const attributes = attributesOf(dim);
  const hierarchies = hierarchiesOf(dim);
  const usages = isShared(dim) ? usagesOf(doc, dim) : [];
  const attrNames = attributes.map((a) => attr(a, 'name'));
  const used = new Set(hierarchies.flatMap((h) => kids(h, 'Level').flatMap((l) =>
    [attr(l, 'sourceAttribute'), ...kids(l, 'Property').map((p) => attr(p, 'sourceAttribute'))])));
  const siblings = isShared(dim) ? sharedDims(doc) : kids(dim.parentNode, 'Dimension');
  const hierarchyCount = hierarchies.length + attributes.filter(hasHierarchy).length;

  const remove = () => {
    const what = usages.length ? ` and its ${usages.length} cube usage(s)` : '';
    if (!confirm(`Remove dimension '${attr(dim, 'name')}'${what}?`)) return;
    edit(() => {
      usages.forEach(({ usage }) => usage.remove());
      dim.remove();
    });
    select({ kind: 'schema' });
  };
  const addHierarchy = () => edit(() => {
    const names = [...attrNames, ...hierarchies.map((h) => attr(h, 'name'))];
    let name = `${attr(dim, 'name')} Hierarchy`;
    for (let n = 2; names.includes(name); n++) name = `${attr(dim, 'name')} Hierarchy ${n}`;
    insertAfterLast(dim, create(doc, 'Hierarchy', { name, hasAll: 'true' }), ['Hierarchy', 'DimensionAttribute']);
  });

  return html`<div class="pane">
    <div class="form">
      <label>Dimension name</label>
      <${TextField} value=${attr(dim, 'name')} validate=${unique('A dimension', siblings.filter((d) => d !== dim).map((d) => attr(d, 'name')))}
        onCommit=${(v) => edit(() => renameDimension(doc, dim, v))} />
      <label>Caption</label>
      <${TextField} value=${attr(dim, 'caption')} placeholder=${attr(dim, 'name')} onCommit=${(v) => edit(() => setAttr(dim, 'caption', v))} />
      <label>Table</label>
      <${TextField} readOnly mono value=${attr(dim, 'table')} title="The view of the characteristic; a placeholder (ZZXXMLA1_C_...) is replaced by the view generated on accept" />
      <label>Time</label>
      <span class="row">
        <${Check} checked=${time} label="Time dimension" onChange=${(on) => edit(() => setTimeDimension(dim, on, suggestions))} />
        <span class="muted small">enables the time functions (Ytd, ParallelPeriod, …); every level then needs a time level type</span>
      </span>
      ${isShared(dim) && html`<label>Used by</label>
        <span>${usages.length ? usages.map(({ cube, usage }, i) => html`${i > 0 && ', '}<button class="link"
          onClick=${() => select({ kind: 'cube', ci: cubesOf(doc).indexOf(cube) })}>${attr(cube, 'name')}</button>
          <span class="muted small"> as ${attr(usage, 'name')} on <span class="mono">${attr(usage, 'foreignKey')}</span></span>`)
          : html`<span class="muted">no cube – not visible in MDX</span>`}</span>`}
    </div>

    <section class="section">
      <header><h3>Attributes</h3><span class="spacer"></span><span class="muted small">a ticked attribute is a hierarchy of its own; the others serve as levels and properties</span></header>
      <div class="body scroll-x"><table>
        <thead><tr><th>Name</th><th>Key column</th><th>Name column</th><th>Hierarchy</th>${time && html`<th>Level type</th>`}<th></th></tr></thead>
        <tbody>${attributes.map((a, i) => {
          const suggestion = suggestionFor(suggestions, dim, a);
          const isKey = attr(a, 'usage') === 'Key';
          return html`<tr key=${i}>
            <td><${TextField} value=${attr(a, 'name')} validate=${unique('An attribute', attrNames.filter((n) => n !== attr(a, 'name')))}
              onCommit=${(v) => edit(() => renameAttribute(dim, a, v))} /></td>
            <td class="mono small">${keyColumn(a)} ${isKey && html`<span class="kind">key</span>`}</td>
            <td class="mono small">${attr(kids(a, 'NameColumn')[0], 'columnName')}</td>
            <td><${Check} checked=${hasHierarchy(a)} disabled=${hasHierarchy(a) && hierarchyCount === 1}
              title=${hasHierarchy(a) && hierarchyCount === 1 ? 'The dimension needs a hierarchy' : 'The attribute is a hierarchy of its own'}
              onChange=${(on) => edit(() => setAttributeHierarchy(a, on))} /></td>
            ${time && html`<td><div class="row">
              <${Select} value=${attr(a, 'levelType')} options=${TIME_TYPES} onChange=${(v) => edit(() => setAttributeLevelType(dim, a, v))} />
              ${suggestion && suggestion !== attr(a, 'levelType') && html`<button class="link small"
                onClick=${() => edit(() => setAttributeLevelType(dim, a, suggestion))}>suggested: ${suggestion}</button>`}
            </div></td>`}
            <td class="actions"><button class="icon danger" disabled=${isKey || used.has(attr(a, 'name'))}
              title=${isKey ? 'The key attribute stays' : used.has(attr(a, 'name')) ? 'A hierarchy uses it' : 'Remove the attribute'}
              onClick=${() => edit(() => a.remove())}>✕</button></td>
          </tr>`;
        })}</tbody>
      </table></div>
    </section>

    <section class="section">
      <header>
        <h3>User hierarchies</h3><span class="spacer"></span>
        <button onClick=${addHierarchy}>Add hierarchy</button>
      </header>
      <div class="body">
        ${!hierarchies.length && html`<span class="muted">None. A user hierarchy nests attributes as levels, top level first.</span>`}
        ${hierarchies.map((h, i) => html`<${HierarchyEditor} key=${i} doc=${doc} edit=${edit} dim=${dim} h=${h}
          others=${[...attrNames, ...hierarchies.filter((o) => o !== h).map((o) => attr(o, 'name'))]} />`)}
      </div>
    </section>

    <div class="row"><button class="danger" onClick=${remove}>Remove dimension</button></div>
  </div>`;
}

function HierarchyEditor({ doc, edit, dim, h, others }) {
  const [open, setOpen] = useState({});
  const time = isTime(dim);
  const levels = kids(h, 'Level');
  const attributes = attributesOf(dim);
  const attrNames = attributes.map((a) => attr(a, 'name'));
  const hasAll = isTrue(h, 'hasAll', true);
  const name = attr(h, 'name');
  const clash = (!name || name === attr(dim, 'name')) && attrNames.includes(attr(dim, 'name'));
  const levelNames = levels.map((l) => attr(l, 'name'));

  const addLevel = (source) => edit(() => {
    const a = attributes.find((x) => attr(x, 'name') === source);
    let levelName = source;
    for (let n = 2; levelNames.includes(levelName); n++) levelName = `${source} ${n}`;
    h.appendChild(create(doc, 'Level', {
      name: levelName,
      uniqueMembers: levels.length === 0 ? 'true' : 'false',
      sourceAttribute: source,
      levelType: time ? attr(a, 'levelType') || 'TimeUndefined' : '',
    }));
  });

  return html`<div class="hier">
    <header>
      <${TextField} value=${name} placeholder=${`(unnamed: [${attr(dim, 'name')}])`}
        validate=${(v) => (v && others.includes(v) ? `'${v}' is already an attribute or hierarchy of the dimension` : '')}
        onCommit=${(v) => edit(() => setAttr(h, 'name', v))} />
      <${Check} checked=${hasAll} label="All member" onChange=${(on) => edit(() => h.setAttribute('hasAll', String(on)))} />
      ${hasAll && html`<${TextField} value=${attr(h, 'allMemberName')} placeholder="All member name" size="16"
        onCommit=${(v) => edit(() => setAttr(h, 'allMemberName', v))} />`}
      <${TextField} value=${attr(h, 'defaultMember')} mono placeholder=${hasAll ? 'default member: the All member' : `default member, e.g. [${attr(dim, 'name')}].[1997]`}
        title="A unique member name" onCommit=${(v) => edit(() => setAttr(h, 'defaultMember', v))} />
      <span class="spacer"></span>
      <button class="danger" onClick=${() => confirm(`Remove hierarchy '${name || attr(dim, 'name')}'?`) && edit(() => h.remove())}>Remove</button>
    </header>
    <div class="body">
      ${clash && html`<div class="notice warn">Name the hierarchy: the attribute '${attr(dim, 'name')}' has the dimension's name, so an
        unnamed hierarchy (or one named like the dimension) would share its unique name.</div>`}
      ${!hasAll && !attr(h, 'defaultMember') && html`<div class="notice warn">Without an All member the first member is the default; BW's
        empty member (SID 0) may come first, so give a default member.</div>`}
      ${levels.length > 0 && html`<div class="scroll-x"><table>
        <thead><tr><th>#</th><th>Level</th><th>Attribute</th>${time && html`<th>Level type</th>`}<th title="Members are unique within the level, not only within their parent">Unique</th><th>Properties</th><th></th></tr></thead>
        <tbody>${levels.map((l, i) => {
          const props = kids(l, 'Property');
          return html`
          <tr key=${'l' + i}>
            <td class="num muted">${i + 1}</td>
            <td><${TextField} value=${attr(l, 'name')} validate=${unique('A level', levelNames.filter((n) => n !== attr(l, 'name')))}
              onCommit=${(v) => edit(() => l.setAttribute('name', v))} /></td>
            <td><${Select} value=${attr(l, 'sourceAttribute')} options=${attrNames} onChange=${(v) => edit(() => l.setAttribute('sourceAttribute', v))} /></td>
            ${time && html`<td><${Select} value=${attr(l, 'levelType')} options=${TIME_TYPES} onChange=${(v) => edit(() => l.setAttribute('levelType', v))} /></td>`}
            <td><input type="checkbox" checked=${isTrue(l, 'uniqueMembers', false)} aria-label="Unique members"
              onChange=${(e) => edit(() => l.setAttribute('uniqueMembers', String(e.target.checked)))} /></td>
            <td><button class="link" onClick=${() => setOpen({ ...open, [i]: !open[i] })}>${props.length} ${open[i] ? '▾' : '▸'}</button></td>
            <td class="actions">
              <button class="icon" title="Up" disabled=${i === 0} onClick=${() => edit(() => move(l, -1))}>↑</button>
              <button class="icon" title="Down" disabled=${i === levels.length - 1} onClick=${() => edit(() => move(l, 1))}>↓</button>
              <button class="icon danger" title="Remove the level" onClick=${() => edit(() => l.remove())}>✕</button>
            </td>
          </tr>
          ${open[i] && html`<tr key=${'p' + i}><td></td><td colspan=${time ? 6 : 5}><div class="props">
            ${props.map((p, j) => html`<div class="row" key=${j}>
              <${TextField} value=${attr(p, 'name')} validate=${required('A property')} onCommit=${(v) => edit(() => p.setAttribute('name', v))} />
              <span class="muted">from</span>
              <${Select} value=${attr(p, 'sourceAttribute')} options=${attrNames} onChange=${(v) => edit(() => p.setAttribute('sourceAttribute', v))} />
              <button class="icon danger" title="Remove the property" onClick=${() => edit(() => p.remove())}>✕</button>
            </div>`)}
            <div class="row"><select value="" aria-label="Add a property" onChange=${(e) => {
              const source = e.target.value;
              e.target.value = '';
              if (source) edit(() => l.appendChild(create(doc, 'Property', { name: source, sourceAttribute: source })));
            }}>
              <option value="">Add a member property…</option>
              ${attrNames.filter((n) => !props.some((p) => attr(p, 'sourceAttribute') === n)).map((n) => html`<option value=${n}>${n}</option>`)}
            </select><span class="muted small">attributes shown with each member of this level</span></div>
          </div></td></tr>`}`;
        })}</tbody>
      </table></div>`}
      <div class="row">
        <select value="" aria-label="Add a level" onChange=${(e) => {
          const source = e.target.value;
          e.target.value = '';
          if (source) addLevel(source);
        }}>
          <option value="">Add a level…</option>
          ${attrNames.map((n) => html`<option value=${n}>${n}${levels.some((l) => attr(l, 'sourceAttribute') === n) ? ' (used)' : ''}</option>`)}
        </select>
        ${!levels.length && html`<span class="muted small">start with the top level</span>`}
      </div>
    </div>
  </div>`;
}

function XmlPane({ xml, replace }) {
  const [text, setText] = useState(xml);
  const [error, setError] = useState('');
  useEffect(() => {
    setText(xml);
    setError('');
  }, [xml]);
  const apply = () => {
    try {
      replace(parseXml(text));
    } catch (e) {
      setError(e.message);
    }
  };
  const download = () => {
    const link = document.createElement('a');
    link.href = URL.createObjectURL(new Blob([xml], { type: 'application/xml' }));
    link.download = `${attr(parseXml(xml).documentElement, 'name') || 'schema'}.xml`;
    link.click();
    URL.revokeObjectURL(link.href);
  };
  return html`<div class="pane" style="max-width: none">
    <div class="row">
      <button class="primary" disabled=${text === xml} onClick=${apply}>Apply</button>
      <button disabled=${text === xml} onClick=${() => { setText(xml); setError(''); }}>Revert</button>
      <button onClick=${download}>Download</button>
      <span class="muted small">Anything the outline does not cover (calculated members, captions, annotations, …) is edited here.</span>
    </div>
    ${error && html`<div class="notice err">${error}</div>`}
    <textarea class="xml" spellcheck="false" value=${text} onInput=${(e) => setText(e.target.value)}
      onKeyDown=${(e) => {
        if ((e.ctrlKey || e.metaKey) && e.key === 's') { e.preventDefault(); apply(); }
      }}></textarea>
  </div>`;
}

// ------------------------------------------------------------------------------------------------------ editor

function Tree({ doc, sel, select, notes }) {
  const item = (target, label, badge, sub) => {
    const selected = JSON.stringify(target) === JSON.stringify(sel);
    return html`<button class=${`item${sub ? ' sub' : ''}${selected ? ' selected' : ''}`} onClick=${() => select(target)}>
      <span>${label}</span>${badge && html`<span class="badge">${badge}</span>`}
    </button>`;
  };
  const usedNames = new Set(cubesOf(doc).flatMap((c) => kids(c, 'DimensionUsage').map((u) => attr(u, 'source'))));
  return html`<nav class="tree" aria-label="Schema outline">
    ${item({ kind: 'schema' }, html`<strong>${attr(schemaOf(doc), 'name') || 'Schema'}</strong>`, notes.length ? `${notes.length} note${notes.length > 1 ? 's' : ''}` : '')}
    <div class="group"><h3>Cubes</h3></div>
    ${cubesOf(doc).map((cube, ci) => html`
      ${item({ kind: 'cube', ci }, attr(cube, 'name'), `${kids(cube, 'Measure').length} measures`)}
      ${kids(cube, 'Dimension').map((d, di) => item({ kind: 'dim', ci, di }, attr(d, 'name'), isTime(d) ? 'time' : '', true))}`)}
    <div class="group"><h3>Dimensions</h3></div>
    ${sharedDims(doc).map((d, di) => item({ kind: 'dim', ci: null, di }, attr(d, 'name'),
      [isTime(d) && 'time', hierarchiesOf(d).length && `${hierarchiesOf(d).length} hier.`, !usedNames.has(attr(d, 'name')) && 'unused']
        .filter(Boolean).join(' · ')))}
  </nav>`;
}

function Editor({ session, onClose, onAccepted }) {
  const [doc, setDoc] = useState(session.doc);
  const [version, setVersion] = useState(0);
  const [source, setSource] = useState(session.source);
  const [catalog, setCatalog] = useState(session.catalog);
  const [dirty, setDirty] = useState(false);
  const [sel, setSel] = useState({ kind: 'schema' });
  const [tab, setTab] = useState('outline');
  const [check, setCheck] = useState({ state: 'busy' });
  const [dialog, setDialog] = useState(null);
  const undoStack = useRef([]);
  const xml = useMemo(() => serialize(doc), [doc, version]);

  const edit = useCallback((change) => {
    undoStack.current.push(serialize(doc));
    if (undoStack.current.length > 100) undoStack.current.shift();
    change(doc);
    setVersion((v) => v + 1);
    setDirty(true);
  }, [doc]);
  const replace = useCallback((next) => {
    undoStack.current.push(serialize(doc));
    setDoc(next);
    setVersion((v) => v + 1);
    setDirty(true);
  }, [doc]);
  const undo = useCallback(() => {
    const previous = undoStack.current.pop();
    if (previous == null) return;
    setDoc(parseXml(previous));
    setVersion((v) => v + 1);
  }, []);

  // Ctrl+Z outside of input fields (they have their own undo)
  useEffect(() => {
    const onKey = (e) => {
      if ((e.ctrlKey || e.metaKey) && e.key === 'z' && !/^(INPUT|TEXTAREA|SELECT)$/.test(document.activeElement.tagName)) {
        e.preventDefault();
        undo();
      }
    };
    addEventListener('keydown', onKey);
    return () => removeEventListener('keydown', onKey);
  }, [undo]);
  useEffect(() => {
    const onLeave = (e) => { if (dirty) { e.preventDefault(); e.returnValue = ''; } };
    addEventListener('beforeunload', onLeave);
    return () => removeEventListener('beforeunload', onLeave);
  }, [dirty]);

  // the server's checks of accept, nothing written; the last request wins
  const sequence = useRef(0);
  useEffect(() => {
    const mine = ++sequence.current;
    setCheck((c) => ({ ...c, state: 'busy' }));
    const timer = setTimeout(async () => {
      try {
        if (!CATALOG_NAME.test(catalog)) throw new Error('A catalog name has letters, digits, _, - and . (not first)');
        const result = await api('POST', 'check', { catalog }, xml);
        if (mine === sequence.current) setCheck({ state: 'ok', result, xml, catalog });
      } catch (e) {
        if (mine === sequence.current) setCheck({ state: 'err', message: e.message });
      }
    }, 500);
    return () => clearTimeout(timer);
  }, [xml, catalog]);

  const current = check.state === 'ok' && check.xml === xml && check.catalog === catalog;
  const accept = async () => {
    setDialog({ kind: 'accepting' });
    try {
      const result = await api('POST', 'accept', { catalog }, xml);
      undoStack.current = [];
      setDoc(parseXml(result.xml));
      setVersion((v) => v + 1);
      setDirty(false);
      const reopened = { kind: 'schema', name: result.catalog, file: result.file, changedAt: new Date().toISOString(), changedBy: '' };
      setSource(reopened);
      setDialog({ kind: 'accepted', result });
      onAccepted(reopened);
    } catch (e) {
      setDialog({ kind: 'failed', message: e.message });
    }
  };

  let target = resolve(doc, sel);
  const shownSel = target ? sel : { kind: 'schema' };
  if (!target) target = schemaOf(doc);
  const status = check.state === 'busy' ? html`<span class="status busy">Checking…</span>`
    : check.state === 'err' ? html`<span class="status err" title=${check.message}>✕ Does not load</span>`
      : html`<span class="status ok" title=${check.result.file}>✓ Loads${check.result.newCatalog ? ' · new catalog' : ' · replaces the catalog\'s schema'}</span>`;

  return html`
    <div class="topbar">
      <button onClick=${() => (!dirty || confirm('Leave without accepting? Your changes are lost.')) && onClose()} title="Back to the list">←</button>
      <div class="title">
        <h1>Schema Builder</h1>
        <span class="src">${source.kind === 'proposal' ? html`proposal for <span class="mono">${source.name}</span>` : html`catalog <span class="mono">${source.name}</span>`}${dirty && ' · edited'}</span>
      </div>
      <span class="spacer"></span>
      <label class="inline">Catalog
        <input type="text" class=${`mono${CATALOG_NAME.test(catalog) ? '' : ' invalid'}`} value=${catalog} size="16"
          onInput=${(e) => setCatalog(e.target.value.trim())} />
      </label>
      ${status}
      <button disabled=${!undoStack.current.length} onClick=${undo} title="Undo (Ctrl+Z)">Undo</button>
      <button class="primary" disabled=${!current} onClick=${() => setDialog({ kind: 'confirm' })}
        title=${current ? 'Generate the views, write the schema file and register the catalog' : 'Waiting for a successful check'}>Accept…</button>
    </div>
    ${check.state === 'err' && html`<div class="banner" role="alert">${check.message}</div>`}
    <div class="editor">
      <${Tree} doc=${doc} sel=${shownSel} select=${(s) => { setSel(s); setTab('outline'); }} notes=${session.notes} />
      <main class="main">
        <div class="tabs" role="tablist">
          <button role="tab" class=${tab === 'outline' ? 'active' : ''} onClick=${() => setTab('outline')}>Outline</button>
          <button role="tab" class=${tab === 'xml' ? 'active' : ''} onClick=${() => setTab('xml')}>XML</button>
        </div>
        ${tab === 'xml' ? html`<${XmlPane} xml=${xml} replace=${replace} />`
          : shownSel.kind === 'cube' ? html`<${CubePane} key=${JSON.stringify(shownSel)} doc=${doc} edit=${edit} cube=${target} select=${setSel} />`
            : shownSel.kind === 'dim' ? html`<${DimensionPane} key=${JSON.stringify(shownSel)} doc=${doc} edit=${edit} dim=${target} sel=${shownSel}
                select=${setSel} suggestions=${session.suggestions} />`
              : html`<${SchemaPane} doc=${doc} edit=${edit} source=${source} catalog=${catalog} notes=${session.notes} />`}
      </main>
    </div>
    <datalist id="formats">${FORMATS.map((f) => html`<option value=${f} />`)}</datalist>
    ${dialog && html`<${AcceptDialog} dialog=${dialog} check=${check} catalog=${catalog} onAccept=${accept} onClose=${() => setDialog(null)} />`}`;
}

function AcceptDialog({ dialog, check, catalog, onAccept, onClose }) {
  if (dialog.kind === 'confirm') {
    const r = check.result;
    return html`<${Dialog} title="Accept the schema" onClose=${onClose} footer=${html`
      <button onClick=${onClose}>Cancel</button>
      <button class="primary" onClick=${onAccept}>${r.newCatalog ? 'Accept' : 'Replace the schema'}</button>`}>
      ${r.newCatalog ? html`<div class="notice info">Catalog <strong class="mono">${r.catalog}</strong> is new: it is added to the first data source.</div>`
        : html`<div class="notice warn">Catalog <strong class="mono">${r.catalog}</strong> exists: its schema file is replaced, and the next
          XMLA request serves the new schema.</div>`}
      <div class="form">
        <label>Schema file</label><span class="mono">${r.file}</span>
        <label>Views</label>
        <span>${r.views.length ? html`generated for ${r.views.map((v, i) => html`${i > 0 && ', '}<span class="mono">${v}</span>`)}` : 'none to generate'}</span>
      </div>
    <//>`;
  }
  if (dialog.kind === 'accepting') {
    return html`<${Dialog} title="Accepting…" footer=${''}><span class="muted">Generating the views and writing ${catalog}…</span><//>`;
  }
  if (dialog.kind === 'failed') {
    return html`<${Dialog} title="Not accepted" onClose=${onClose} footer=${html`<button onClick=${onClose}>Close</button>`}>
      <div class="notice err">${dialog.message}</div><span class="muted">Nothing was written.</span>
    <//>`;
  }
  const r = dialog.result;
  return html`<${Dialog} title="Accepted" onClose=${onClose} footer=${html`<button class="primary" onClick=${onClose}>Close</button>`}>
    <div class="notice ok">Catalog <strong class="mono">${r.catalog}</strong> is written to <span class="mono">${r.file}</span>; the next XMLA
      request reads it.</div>
    ${r.views.length > 0 && html`<table>
      <thead><tr><th>Characteristic</th><th>DDL source</th><th>View</th></tr></thead>
      <tbody>${r.views.map((v) => html`<tr><td class="mono">${v.characteristic}</td><td class="mono">${v.ddlName}</td><td class="mono">${v.viewName}</td></tr>`)}</tbody>
    </table>`}
  <//>`;
}

// --------------------------------------------------------------------------------------------------------- app

// #proposal/<provider> or #schema/<catalog>, so a reload opens the same thing again
const readHash = () => {
  const m = /^#(proposal|schema)\/(.+)$/.exec(location.hash);
  return m ? { kind: m[1], name: decodeURIComponent(m[2]) } : null;
};
const writeHash = (what) => history.replaceState(null, '', what ? `#${what.kind}/${encodeURIComponent(what.name)}` : location.pathname + location.search);

function App() {
  const [session, setSession] = useState(null);
  const [opening, setOpening] = useState('');
  const [error, setError] = useState('');
  const counter = useRef(0);

  const open = async (what) => {
    setError('');
    setOpening(what.kind === 'proposal' ? `Proposing a schema for ${what.name}…` : `Opening catalog ${what.name}…`);
    try {
      let next;
      if (what.kind === 'proposal') {
        const d = await api('GET', 'proposal', { provider: what.name });
        const doc = parseXml(d.xml);
        next = {
          doc,
          catalog: attr(schemaOf(doc), 'name'),
          source: { kind: 'proposal', name: d.provider.name, providerKind: d.provider.kind, text: d.provider.text, factTable: d.provider.factTable },
          notes: d.notes || [],
          suggestions: suggestionKeys(doc, d.suggestions),
        };
      } else {
        const d = await api('GET', 'schema', { catalog: what.name });
        next = {
          doc: parseXml(d.xml),
          catalog: d.catalog,
          source: { kind: 'schema', name: d.catalog, file: d.file, changedAt: d.changedAt, changedBy: d.changedBy },
          notes: [],
          suggestions: new Map(),
        };
      }
      next.id = ++counter.current;
      writeHash(what);
      setSession(next);
    } catch (e) {
      writeHash(null);
      setError(`${what.name}: ${e.message}`);
    } finally {
      setOpening('');
    }
  };

  useEffect(() => {
    const what = readHash();
    if (what) open(what);
  }, []);

  if (session) {
    return html`<${Editor} key=${session.id} session=${session}
      onClose=${() => { writeHash(null); setSession(null); }}
      onAccepted=${(source) => writeHash(source)} />`;
  }
  return html`<${Start} onOpen=${open} opening=${opening} error=${error} />`;
}

const root = document.getElementById('app');
root.textContent = '';
render(html`<${App} />`, root);
