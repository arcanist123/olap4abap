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
// the catalog proposed for a schema: its name with every other character a _ (/1BW/C01 -> 1BW_C01)
const catalogNameOf = (name) => (name || '').replace(/[^A-Za-z0-9_.-]+/g, '_').replace(/^[_.]+|_+$/g, '');

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

// Our extension (ZZXXMLA1_CL_SCHEMA, c_members_with_facts): a dimension of a cube shows only its members with facts;
// on a DimensionUsage it overrides the shared Dimension's, not on a time dimension.
const MEMBERS_WITH_FACTS = 'olap4abap.membersWithFacts';
const annotationOf = (el, name) => kids(kids(el, 'Annotations')[0], 'Annotation').find((a) => attr(a, 'name') === name);
// sets the annotation's text, or removes it (and its Annotations if that is empty) for null
function setAnnotation(el, name, value) {
  const old = annotationOf(el, name);
  if (value == null) {
    if (!old) return;
    const annotations = old.parentNode;
    old.remove();
    if (!annotations.children.length) annotations.remove();
    return;
  }
  if (old) {
    old.textContent = value;
    return;
  }
  let annotations = kids(el, 'Annotations')[0];
  if (!annotations) {
    annotations = el.ownerDocument.createElement('Annotations');
    el.insertBefore(annotations, el.firstElementChild);
  }
  annotations.appendChild(create(el.ownerDocument, 'Annotation', { name })).textContent = value;
}
// Our extension (ZZXXMLA1_CL_SCHEMA, c_omit_empty_cells): a cube leaves its empty cells but the first out of the answer.
const OMIT_EMPTY_CELLS = 'olap4abap.omitEmptyCells';
const annotatedTrue = (el, name = MEMBERS_WITH_FACTS) => {
  const a = annotationOf(el, name);
  return a ? a.textContent.trim().toLowerCase() === 'true' : null;
};
// The selections of a cube (docs/bw-schema-design-guide.md, section 3.8): annotations olap4abap.filter.<C> (filter
// the cube) and olap4abap.members.<C> (restrict members), their rows as text (I EQ 'K4';E CP '*013'); the
// olap4abap.fixed.<C> = v of a schema fixed before selections is filter the cube with I EQ v. The tables and columns of
// the cube depend on them, so they change only through the server (POST fix, ZZXXMLA1_CL_SCHEMA_FIX), which rewrites
// the schema; the UI replaces the document with its answer. A fixed value is one I EQ row in filter the cube, which the
// dimension's pane sets; other selections are kept as they are.
const FILTER = 'olap4abap.filter.';
const MEMBERS = 'olap4abap.members.';
const FIXED = 'olap4abap.fixed.';
const SINGLE = /^\s*I\s+EQ\s+'([^']*)'\s*$/i;
const selectionsOf = (cube) => kids(kids(cube, 'Annotations')[0], 'Annotation').flatMap((a) => {
  const name = attr(a, 'name');
  const prefix = [FILTER, MEMBERS, FIXED].find((p) => name.startsWith(p));
  if (!prefix) return [];
  const text = a.textContent.trim();
  return [{ characteristic: name.slice(prefix.length), mode: prefix === MEMBERS ? 'members' : 'filter',
    rows: prefix === FIXED ? `I EQ '${text}'` : text }];
});
const isFixed = (s) => s.mode === 'filter' && SINGLE.test(s.rows);
const fixedOf = (cube) => selectionsOf(cube).filter(isFixed)
  .map((s) => ({ characteristic: s.characteristic, value: s.rows.match(SINGLE)[1] }));
const fixedParams = (fixed) => Object.fromEntries((fixed || []).map((f) => [`fixed.${f.characteristic}`, f.value]));
// the parameters of POST fix: the cube's whole new selection, filter.<C> or members.<C> = its rows
const selectionParams = (selections) => Object.fromEntries(selections.map((s) => [`${s.mode}.${s.characteristic}`, s.rows]));
// the cube's selections with fixed values (filter the cube, I EQ v) in place of the selections of their
// characteristics, without the dropped characteristics
const withFixed = (cube, fixed, dropped = []) => [
  ...selectionsOf(cube).filter((s) => !dropped.includes(s.characteristic) && !fixed.some((f) => f.characteristic === s.characteristic)),
  ...fixed.map((f) => ({ characteristic: f.characteristic, mode: 'filter', rows: `I EQ '${f.value}'` }))];
// The rows of a range table (ZZXXMLA1_CL_BW_SELECTION): sign, option, low and, for BT and NB, high; as text
// SIGN OPTION 'low' ['high'] separated by ;. The server checks them (POST fix).
const OPTIONS = ['EQ', 'NE', 'GT', 'GE', 'LT', 'LE', 'BT', 'NB', 'CP', 'NP'];
const RANGE = ['BT', 'NB'];
const ROW = /^\s*([IE])\s+([A-Z]{2})\s+'([^']*)'(?:\s+'([^']*)')?\s*$/i;
const parseRows = (text) => text.split(';').map((r) => r.match(ROW)).filter(Boolean)
  .map(([, sign, option, low, high]) => ({ sign: sign.toUpperCase(), option: option.toUpperCase(), low, high: high || '' }));
const rowsText = (rows) => rows.map((r) => `${r.sign} ${r.option} '${r.low}'${RANGE.includes(r.option) ? ` '${r.high}'` : ''}`).join(';');
// selections offered with a click, per characteristic: the regular fiscal periods of K4 (the proposal's default,
// docs/bw-schema-design-guide.md, section 3.8, fiscal time)
const PRESETS = {
  '0FISCPER': [{ label: 'Regular periods 001–012', mode: 'members',
    rows: Array.from({ length: 12 }, (_, i) => ({ sign: 'I', option: 'CP', low: `*${String(i + 1).padStart(3, '0')}`, high: '' })) }],
};
// a characteristic and those compounded with it, which are fixed only together with it
function unfixed(name, characteristics) {
  const gone = new Set([name]);
  for (let grown = true; grown;) {
    grown = false;
    for (const c of characteristics) {
      if (!gone.has(c.name) && c.compounding.some((n) => gone.has(n))) { gone.add(c.name); grown = true; }
    }
  }
  return [...gone];
}
// The characteristic of the provider a dimension is on: the one whose fact column a usage of it (or the private
// dimension itself) has as foreign key.
function characteristicOf(doc, dim, characteristics) {
  const keys = isShared(dim) ? usagesOf(doc, dim).map(({ usage }) => attr(usage, 'foreignKey')) : [attr(dim, 'foreignKey')];
  return characteristics.find((c) => keys.includes(c.foreignKey));
}
const membersWithFacts = (usage, dim) => annotatedTrue(usage) ?? annotatedTrue(dim) ?? false;
function setMembersWithFacts(usage, dim, on) {
  if (on) setAnnotation(usage, MEMBERS_WITH_FACTS, 'true');
  else if (annotatedTrue(dim)) setAnnotation(usage, MEMBERS_WITH_FACTS, 'false');
  else setAnnotation(usage, MEMBERS_WITH_FACTS, null);
}

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

// The columns of the views that can caption a characteristic's members (ZZXXMLA1_CL_BW_VIEW_GEN): the key as a caption
// (KEY_CAPTION, # for BW's initial value) and its texts, per table in the server's order.
function captionKeys(captionColumns) {
  const keys = new Map();
  for (const c of captionColumns || []) keys.set(c.table, [...(keys.get(c.table) || []), c.column]);
  return keys;
}
const CAPTION_LABELS = { KEY_CAPTION: 'Key', TXTMD: 'Medium text', TXTLG: 'Long text', TXTSH: 'Short text' };
const keyAttributeOf = (dim) => attributesOf(dim).find((a) => attr(a, 'usage') === 'Key');
// the column that captions the dimension's members: its key attribute's NameColumn (the levels over it are named by
// their nameColumn, docs/next-steps.md, Now: texts and captions)
const captionOf = (dim) => attr(kids(keyAttributeOf(dim), 'NameColumn')[0], 'columnName');
function setCaption(doc, dim, column) {
  const key = keyAttributeOf(dim);
  let name = kids(key, 'NameColumn')[0];
  if (!name) {
    name = create(doc, 'NameColumn', {});
    key.appendChild(name);
  }
  name.setAttribute('dataType', 'String');
  name.setAttribute('columnName', column);
}

function setTimeDimension(dim, on, suggestions) {
  const attributes = attributesOf(dim);
  if (on) {
    dim.setAttribute('type', 'TimeDimension');
    // the server refuses members with facts on a time dimension (not supported yet)
    setAnnotation(dim, MEMBERS_WITH_FACTS, null);
    if (isShared(dim)) usagesOf(dim.ownerDocument, dim).forEach(({ usage }) => setAnnotation(usage, MEMBERS_WITH_FACTS, null));
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
        if (attr(usage, 'name') === old) {
          usage.setAttribute('name', name);
          renameActionDimension(cube, old, name);
        }
      }
    }
  } else {
    renameActionDimension(dim.parentNode, old, name);
  }
  for (const h of hierarchiesOf(dim)) {
    const member = attr(h, 'defaultMember');
    if (member.startsWith(`[${old}]`)) h.setAttribute('defaultMember', `[${name}]${member.slice(old.length + 2)}`);
  }
}

function renameAttribute(doc, dim, attribute, name) {
  const old = attr(attribute, 'name');
  attribute.setAttribute('name', name);
  for (const { cube, name: dimName } of placesOf(doc, dim)) {
    columnsOfDimension(cube, dimName).filter((c) => attr(c, 'sourceAttribute') === old)
      .forEach((c) => c.setAttribute('sourceAttribute', name));
  }
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

// The drill-through action: the columns of the fact rows a double click on a cell shows (the cell's measure is added
// unless the action names measures). Without a default action every level column of every dimension is shown.
const defaultAction = (cube) => kids(cube, 'DrillThroughAction').find((a) => attr(a, 'default') === 'true');
const actionColumns = (cube, tag) => kids(cube, 'DrillThroughAction').flatMap((a) => kids(a, tag));
// the cubes a dimension is in, with its name there: a shared one's usages, a private one's cube
const placesOf = (doc, dim) => (isShared(dim)
  ? usagesOf(doc, dim).map(({ cube, usage }) => ({ cube, name: attr(usage, 'name') }))
  : [{ cube: dim.parentNode, name: attr(dim, 'name') }]);
const columnsOfDimension = (cube, name) =>
  actionColumns(cube, 'DrillThroughAttribute').filter((c) => attr(c, 'dimension') === name);
function renameActionDimension(cube, old, name) {
  columnsOfDimension(cube, old).forEach((c) => c.setAttribute('dimension', name));
}
function renameActionMeasure(cube, old, name) {
  actionColumns(cube, 'DrillThroughMeasure').filter((c) => attr(c, 'measure') === old).forEach((c) => c.setAttribute('measure', name));
}
// the name a new column gets: the dimension's caption for its value, "(Text)" after it for its text
function columnName(dimCaption, attribute) {
  if (attribute.endsWith(' Key')) return dimCaption;
  if (attribute.endsWith(' Text')) return `${dimCaption} (Text)`;
  return attribute;
}

const required = (what) => (value) => (value.trim() ? '' : `${what} needs a name`);
const unique = (what, others) => (value) =>
  required(what)(value) || (others.includes(value) ? `${what} '${value}' exists already` : '');

// ------------------------------------------------------------------------------------------------- components

function TextField({ value = '', onCommit, validate, placeholder, mono, readOnly, list, title, size, label }) {
  const [text, setText] = useState(value);
  const [error, setError] = useState('');
  // only a new value replaces the text: Preact runs effects after the paint, so one on mounting would also wipe out
  // what was typed in between
  const shown = useRef(value);
  useEffect(() => {
    if (shown.current === value) return;
    shown.current = value;
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
      placeholder=${placeholder} list=${list} size=${size} title=${error || title || ''} aria-label=${label}
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
    <div class="topbar"><h1>Schema Builder</h1><span class="muted">Mondrian schemas for BW InfoProviders</span>
      <span class="spacer"></span><a href=${`console.html${location.search}`}>MDX Console</a><a href=${`time.html${location.search}`}>Time Master Data</a><a href=${`trace.html${location.search}`}>Trace</a></div>
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
      <header><h3>Notes</h3></header>
      <div class="body"><ul class="plain">${notes.map((n) => html`<li><span class="mono">${n.iobjnm}</span>: ${n.reason}</li>`)}</ul></div>
    </section>`}
  </div>`;
}

function CubePane({ doc, edit, cube, select, characteristics }) {
  const measures = kids(cube, 'Measure');
  const usages = kids(cube, 'DimensionUsage');
  const privates = kids(cube, 'Dimension');
  const known = ['Table', 'DimensionUsage', 'Dimension', 'Measure', 'Annotations', 'DrillThroughAction'];
  const others = [...cube.children].filter((c) => !known.includes(c.tagName)).map((c) => c.tagName);
  const measureNames = measures.map((m) => attr(m, 'name'));
  const dimNames = [...usages, ...privates].map((u) => attr(u, 'name'));
  const defaultMeasure = attr(cube, 'defaultMeasure');

  const removeMeasure = (m) => edit(() => {
    const name = attr(m, 'name');
    actionColumns(cube, 'DrillThroughMeasure').filter((c) => attr(c, 'measure') === name).forEach((c) => c.remove());
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
      ${selectionsOf(cube).length > 0 && html`<label>Selection</label>
        <span title="Fixed values filter the cube as a query's fixed filter; restrict members leaves the facts: change them on the dimension's pane">${selectionsOf(cube).map((s, i) => {
          const c = characteristics.find((x) => x.name === s.characteristic);
          const di = c && c.shared ? sharedDims(doc).findIndex((d) => attr(d, 'name') === c.dimension) : -1;
          const pi = c && !c.shared ? kids(cube, 'Dimension').findIndex((d) => attr(d, 'name') === c.dimension) : -1;
          const label = html`<span class="mono">${isFixed(s) ? `${s.characteristic} = ${s.rows.match(SINGLE)[1]}`
            : `${s.characteristic}: ${s.rows}${s.mode === 'members' ? ' (members)' : ''}`}</span>`;
          return html`${i > 0 && ', '}${di >= 0 ? html`<button class="link" onClick=${() => select({ kind: 'dim', ci: null, di })}>${label}</button>`
            : pi >= 0 ? html`<button class="link" onClick=${() => select({ kind: 'dim', ci: cubesOf(doc).indexOf(cube), di: pi })}>${label}</button>`
              : label}`;
        })}</span>`}
      <label>Default measure</label>
      <${Select} value=${defaultMeasure} options=${measureNames} onChange=${(v) => edit(() => setAttr(cube, 'defaultMeasure', v))} />
      <label>Empty cells</label>
      <span class="row">
        <${Check} checked=${annotatedTrue(cube, OMIT_EMPTY_CELLS) ?? false} label="Omit empty cells"
          onChange=${(on) => edit(() => setAnnotation(cube, OMIT_EMPTY_CELLS, on ? 'true' : null))} />
        <span class="muted small">only the cells with a value are sent (olap4abap.omitEmptyCells); a client takes a missing cell as empty. Off: every cell, as the reference sends it</span>
      </span>
    </div>

    <section class="section">
      <header><h3>Measures</h3><span class="spacer"></span><span class="muted small">key figures of the fact table</span></header>
      <div class="body scroll-x"><table>
        <thead><tr><th>Name</th><th>Column</th><th>Aggregator</th><th>Format string</th><th>Visible</th><th></th></tr></thead>
        <tbody>${measures.map((m, i) => html`<tr key=${i}>
          <td><${TextField} value=${attr(m, 'name')} validate=${unique('A measure', measureNames.filter((n) => n !== attr(m, 'name')))}
            onCommit=${(v) => edit(() => {
              if (defaultMeasure === attr(m, 'name')) cube.setAttribute('defaultMeasure', v);
              renameActionMeasure(cube, attr(m, 'name'), v);
              m.setAttribute('name', v);
            })} /></td>
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
        <thead><tr><th>Name in the cube</th><th>Dimension</th><th>Foreign key</th>
          <th title="Only the members whose key is in the cube's fact table (olap4abap.membersWithFacts); not on a time dimension">Members with facts</th>
          <th></th></tr></thead>
        <tbody>
          ${usages.map((u, i) => {
            const di = sharedDims(doc).findIndex((d) => attr(d, 'name') === attr(u, 'source'));
            const def = sharedDims(doc)[di];
            const facts = html`<td>${def && isTime(def) ? html`<span class="muted small">time</span>`
              : html`<input type="checkbox" checked=${membersWithFacts(u, def)} aria-label="Only members with facts"
                  onChange=${(e) => edit(() => setMembersWithFacts(u, def, e.target.checked))} />`}</td>`;
            return html`<tr key=${'u' + i}>
              <td><${TextField} value=${attr(u, 'name')} validate=${unique('A dimension', dimNames.filter((n) => n !== attr(u, 'name')))}
                onCommit=${(v) => edit(() => { renameActionDimension(cube, attr(u, 'name'), v); u.setAttribute('name', v); })} /></td>
              <td>${di >= 0 ? html`<button class="link" onClick=${() => select({ kind: 'dim', ci: null, di })}>${attr(u, 'source')}</button>`
                : html`<span class="field-error">${attr(u, 'source')} (missing)</span>`}</td>
              <td class="mono small">${attr(u, 'foreignKey')}</td>
              ${facts}
              <td class="actions"><button class="icon danger" title="Remove from the cube (the dimension stays)"
                onClick=${() => confirm(`Remove '${attr(u, 'name')}' from cube '${attr(cube, 'name')}'?`) && edit(() => {
                  columnsOfDimension(cube, attr(u, 'name')).forEach((c) => c.remove());
                  u.remove();
                })}>✕</button></td>
            </tr>`;
          })}
          ${privates.map((d, i) => html`<tr key=${'p' + i}>
            <td>${attr(d, 'name')}</td>
            <td><button class="link" onClick=${() => select({ kind: 'dim', ci: cubesOf(doc).indexOf(cube), di: i })}>private dimension</button></td>
            <td class="mono small">${attr(d, 'foreignKey')}</td>
            <td>${isTime(d) ? html`<span class="muted small">time</span>`
              : html`<input type="checkbox" checked=${annotatedTrue(d) ?? false} aria-label="Only members with facts"
                  onChange=${(e) => edit(() => setAnnotation(d, MEMBERS_WITH_FACTS, e.target.checked ? 'true' : null))} />`}</td>
            <td></td>
          </tr>`)}
        </tbody>
      </table></div>
    </section>
    <${DrillThroughSection} doc=${doc} edit=${edit} cube=${cube} />
    ${others.length > 0 && html`<div class="notice warn">The cube also has ${[...new Set(others)].join(', ')}; edit them on the XML tab.</div>`}
  </div>`;
}

// The cube's default drill-through action: what a double click on a cell (Excel's "Show Details") shows.
function DrillThroughSection({ doc, edit, cube }) {
  const action = defaultAction(cube);
  // the cube's dimensions with their definitions and captions
  const dims = [
    ...kids(cube, 'DimensionUsage').map((u) => {
      const def = sharedDims(doc).find((d) => attr(d, 'name') === attr(u, 'source'));
      return { name: attr(u, 'name'), caption: attr(u, 'caption') || attr(def, 'caption') || attr(u, 'name'), def };
    }),
    ...kids(cube, 'Dimension').map((d) => ({ name: attr(d, 'name'), caption: attr(d, 'caption') || attr(d, 'name'), def: d })),
  ];
  const measureNames = kids(cube, 'Measure').map((m) => attr(m, 'name'));
  const columns = action ? [...action.children].filter((c) => c.tagName.startsWith('DrillThrough')) : [];
  const names = columns.map((c) => attr(c, 'name'));
  const reads = (c) => {
    if (c.tagName === 'DrillThroughMeasure') return html`measure <span class="mono">${attr(c, 'measure')}</span>`;
    const target = attr(c, 'sourceAttribute') || [attr(c, 'hierarchy'), attr(c, 'level')].filter(Boolean).join(' › ') || 'first level';
    const dim = dims.find((d) => d.name === attr(c, 'dimension'));
    const attribute = dim && attributesOf(dim.def).find((a) => attr(a, 'name') === attr(c, 'sourceAttribute'));
    return html`${attr(c, 'dimension')} · ${target}${attribute && html` <span class="mono small muted">${keyColumn(attribute)}</span>`}`;
  };
  const add = (value) => edit(() => {
    const [kind, target, source] = value.split('|');
    const base = kind === 'm' ? target : columnName(dims.find((d) => d.name === target).caption, source);
    let name = base;
    for (let n = 2; names.includes(name); n++) name = `${base} ${n}`;
    action.appendChild(kind === 'm'
      ? create(doc, 'DrillThroughMeasure', { name, measure: target })
      : create(doc, 'DrillThroughAttribute', { name, dimension: target, sourceAttribute: source }));
  });
  const create_ = () => edit(() => insertAfterLast(cube, create(doc, 'DrillThroughAction', { name: 'Details', default: 'true' }),
    ['Measure', 'CalculatedMember', 'NamedSet']));

  return html`<section class="section">
    <header><h3>Double-click columns</h3><span class="spacer"></span>
      <span class="muted small">the columns of the fact rows a double click on a cell shows, with the cell's measure</span></header>
    <div class="body">
      ${!action ? html`<div class="row">
          <span class="muted">No default drill-through action: a double click shows every level column of every dimension,
            one join per dimension.</span>
          <button onClick=${create_}>Choose the columns</button>
        </div>` : html`
        ${columns.length > 0 && html`<div class="scroll-x"><table>
          <thead><tr><th>Column</th><th>Reads</th><th></th></tr></thead>
          <tbody>${columns.map((c, i) => html`<tr key=${i}>
            <td><${TextField} value=${attr(c, 'name')} validate=${unique('A column', names.filter((n) => n !== attr(c, 'name')))}
              onCommit=${(v) => edit(() => c.setAttribute('name', v))} /></td>
            <td>${reads(c)}</td>
            <td class="actions">
              <button class="icon" title="Up" disabled=${i === 0} onClick=${() => edit(() => action.insertBefore(c, columns[i - 1]))}>↑</button>
              <button class="icon" title="Down" disabled=${i === columns.length - 1} onClick=${() => edit(() => action.insertBefore(columns[i + 1], c))}>↓</button>
              <button class="icon danger" title="Remove the column" onClick=${() => edit(() => c.remove())}>✕</button>
            </td>
          </tr>`)}</tbody>
        </table></div>`}
        ${!columns.length && html`<div class="muted">No columns: a double click shows the cell's measure only.</div>`}
        <div class="row">
          <select value="" aria-label="Add a column" onChange=${(e) => {
            const value = e.target.value;
            e.target.value = '';
            if (value) add(value);
          }}>
            <option value="">Add a column…</option>
            ${dims.filter((d) => d.def).map((d) => html`<optgroup label=${d.caption === d.name ? d.name : `${d.caption} (${d.name})`}>
              ${attributesOf(d.def).map((a) => html`<option value=${`a|${d.name}|${attr(a, 'name')}`}>${attr(a, 'name')}</option>`)}
            </optgroup>`)}
            <optgroup label="Measures (shown in every row instead of the cell's)">
              ${measureNames.map((m) => html`<option value=${`m|${m}`}>${m}</option>`)}
            </optgroup>
          </select>
          <span class="spacer"></span>
          <button class="danger" title="Without the action a double click shows every level column of every dimension"
            onClick=${() => confirm('Remove the drill-through action?') && edit(() => action.remove())}>Remove action</button>
        </div>`}
    </div>
  </section>`;
}

// Fixes the characteristic of a dimension to one value, as a query's fixed filter (POST fix): the cube then reads only
// the facts of that value and the dimension has one member; the rest of the schema stays. A compounded characteristic
// is fixed only once its compounding is; un-fixing one un-fixes those compounded with it.
function FixedField({ doc, dim, characteristics, onFix }) {
  const c = characteristicOf(doc, dim, characteristics);
  const cube = isShared(dim) ? usagesOf(doc, dim)[0]?.cube : dim.parentNode;
  const fixed = cube ? fixedOf(cube) : [];
  const current = c && fixed.find((f) => f.characteristic === c.name);
  // a selection other than a fixed value: shown, replaced by fixing or removed
  const other = c && cube && !current ? selectionsOf(cube).find((s) => s.characteristic === c.name) : null;
  const [text, setText] = useState(current ? current.value : '');
  // the values it can be fixed to: { loading } | { values, more } | { error }
  const [values, setValues] = useState(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  useEffect(() => setText(current ? current.value : ''), [current && current.value]);
  if (!c || !cube) return null;
  const lacking = c.compounding.filter((n) => !fixed.some((f) => f.characteristic === n));
  const dependents = characteristics.filter((x) => x.compounding.includes(c.name) && fixed.some((f) => f.characteristic === x.name));
  const load = () => {
    if (values) return;
    setValues({ loading: true });
    api('GET', 'values', { characteristic: c.name, ...fixedParams(fixed.filter((f) => c.compounding.includes(f.characteristic))) })
      .then((d) => setValues(d), (e) => setValues({ error: e.message }));
  };
  const run = (selection, dropped = []) => {
    setBusy(true);
    setError('');
    onFix(attr(cube, 'name'), withFixed(cube, selection, dropped)).catch((e) => setError(e.message)).finally(() => setBusy(false));
  };
  const unfix = () => {
    const gone = unfixed(c.name, characteristics);
    run(fixed.filter((f) => !gone.includes(f.characteristic)), gone);
  };
  const value = text.trim();
  const id = `fixed-values-${c.name}`;
  return html`<label>Fixed value</label>
    <span>
      <span class="row">
        ${lacking.length ? html`<span class="muted">compounded with <span class="mono">${lacking.join(', ')}</span>: ${`fix ${lacking.length > 1 ? 'them' : 'it'} first`}</span>`
          : html`<input type="text" class="mono" value=${text} list=${id} size="14" aria-label=${`Fixed value of ${c.name}`}
              placeholder=${values && values.values && values.values.length ? `e.g. ${values.values[0]}` : 'not fixed'}
              onFocus=${load} onInput=${(e) => setText(e.target.value)}
              onKeyDown=${(e) => { if (e.key === 'Enter' && value && value !== (current && current.value)) run([...fixed.filter((f) => f.characteristic !== c.name), { characteristic: c.name, value }]); }} />
            <datalist id=${id}>${((values && values.values) || []).map((v) => html`<option value=${v} />`)}</datalist>
            <button disabled=${busy || !value || value === (current && current.value)}
              onClick=${() => run([...fixed.filter((f) => f.characteristic !== c.name), { characteristic: c.name, value }])}>
              ${busy ? 'Fixing…' : current ? 'Change' : 'Fix'}</button>`}
        ${current && html`<button disabled=${busy} onClick=${unfix}
          title=${dependents.length ? `Also un-fixes ${dependents.map((x) => x.name).join(', ')}` : 'The cube reads the facts of every value again'}>Unfix</button>`}
      </span>
      <div class="muted small"><span class="mono">${c.name}</span> ${c.text}: ${current
        ? `the cube reads only the facts of ${current.value}; this dimension has that one member`
        : other ? 'restricted by the selection below; fixing a value replaces it'
        : 'fixed to a value, the cube reads only its facts and this dimension has one member'}${values && values.more ? ` (the first ${values.values.length} values are listed)` : ''}</div>
      ${values && values.error && html`<div class="field-error">${values.error}</div>`}
      ${error && html`<div class="field-error">${error}</div>`}
    </span>`;
}

// The selection of the characteristic of a dimension (docs/bw-schema-design-guide.md, section 3.8): a BW range table
// (rows of sign, option, low and high) in one of two modes, filter the cube (members and facts) or restrict members
// (its members only; the server probes the facts and refuses the selection if they hold a value it excludes). Edited
// as a draft and applied with POST fix, which rewrites the schema (one edit, undone as any other); a fixed value is the
// one row I EQ v in filter the cube. Removing it removes the fixed values compounded with it too.
function SelectionField({ doc, dim, characteristics, onFix }) {
  const c = characteristicOf(doc, dim, characteristics);
  const cube = isShared(dim) ? usagesOf(doc, dim)[0]?.cube : dim.parentNode;
  const current = c && cube ? selectionsOf(cube).find((s) => s.characteristic === c.name) : null;
  const key = current ? `${current.mode}:${current.rows}` : '';
  const initial = () => (current ? { mode: current.mode, rows: parseRows(current.rows) } : { mode: 'members', rows: [] });
  const [draft, setDraft] = useState(initial);
  const [values, setValues] = useState(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  useEffect(() => { setDraft(initial()); setError(''); }, [key, c && c.name]);
  if (!c || !cube) return null;
  const text = rowsText(draft.rows);
  const changed = !current ? draft.rows.length > 0 : draft.mode !== current.mode || text !== rowsText(parseRows(current.rows));
  const incomplete = draft.rows.some((r) => r.low === '' || (RANGE.includes(r.option) && r.high === ''));
  const load = () => {
    if (values) return;
    setValues({ loading: true });
    api('GET', 'values', { characteristic: c.name }).then((d) => setValues(d), (e) => setValues({ error: e.message }));
  };
  const run = (selections) => {
    setBusy(true);
    setError('');
    onFix(attr(cube, 'name'), selections).catch((e) => setError(e.message)).finally(() => setBusy(false));
  };
  const apply = () => run([...selectionsOf(cube).filter((s) => s.characteristic !== c.name),
    { characteristic: c.name, mode: draft.mode, rows: text }]);
  const remove = () => {
    const fixed = fixedOf(cube).map((f) => f.characteristic);
    const gone = unfixed(c.name, characteristics).filter((n) => n === c.name || fixed.includes(n));
    run(selectionsOf(cube).filter((s) => !gone.includes(s.characteristic)));
  };
  const setRow = (i, change) => setDraft((d) => ({ ...d, rows: d.rows.map((r, j) => (j === i ? { ...r, ...change } : r)) }));
  const id = `selection-values-${c.name}`;
  return html`<label>Selection</label>
    <span>
      <div class="row">
        <label class="switch"><input type="radio" name=${`mode-${c.name}`} checked=${draft.mode === 'filter'}
          onChange=${() => setDraft((d) => ({ ...d, mode: 'filter' }))} />Filter the cube</label>
        <label class="switch"><input type="radio" name=${`mode-${c.name}`} checked=${draft.mode === 'members'}
          onChange=${() => setDraft((d) => ({ ...d, mode: 'members' }))} />Restrict members</label>
        ${(PRESETS[c.name] || []).map((p) => html`<button class="link small"
          onClick=${() => setDraft({ mode: p.mode, rows: p.rows.map((r) => ({ ...r })) })}>${p.label}</button>`)}
      </div>
      ${draft.rows.length > 0 && html`<table class="selection" aria-label=${`Selection of ${c.name}`}>
        <thead><tr><th>Sign</th><th>Option</th><th>Low</th><th>High</th><th></th></tr></thead>
        <tbody>${draft.rows.map((r, i) => html`<tr key=${i}>
          <td><${Select} value=${r.sign} options=${['I', 'E']} title="I include, E exclude" onChange=${(v) => setRow(i, { sign: v })} /></td>
          <td><${Select} value=${r.option} options=${OPTIONS} title="CP and NP take BW's pattern: * any string, + one character"
            onChange=${(v) => setRow(i, { option: v, high: RANGE.includes(v) ? r.high : '' })} /></td>
          <td><input type="text" class="mono" size="12" value=${r.low} list=${id} aria-label=${`Low value of row ${i + 1}`}
            onFocus=${load} onInput=${(e) => setRow(i, { low: e.target.value })} /></td>
          <td>${RANGE.includes(r.option) && html`<input type="text" class="mono" size="12" value=${r.high} list=${id}
            aria-label=${`High value of row ${i + 1}`} onFocus=${load} onInput=${(e) => setRow(i, { high: e.target.value })} />`}</td>
          <td><button class="link small" title="Remove the row"
            onClick=${() => setDraft((d) => ({ ...d, rows: d.rows.filter((_, j) => j !== i) }))}>✕</button></td>
        </tr>`)}</tbody>
      </table>`}
      <datalist id=${id}>${((values && values.values) || []).map((v) => html`<option value=${v} />`)}</datalist>
      <div class="row">
        <button onClick=${() => setDraft((d) => ({ ...d, rows: [...d.rows, { sign: 'I', option: 'EQ', low: '', high: '' }] }))}>Add row</button>
        <button class="primary" disabled=${busy || !changed || !draft.rows.length || incomplete} onClick=${apply}>${busy ? 'Applying…' : 'Apply'}</button>
        ${changed && html`<button disabled=${busy} onClick=${() => { setDraft(initial()); setError(''); }}>Reset</button>`}
        ${current && html`<button class="danger" disabled=${busy} onClick=${remove}
          title="The cube reads every value again; fixed values compounded with it go too">Remove selection</button>`}
      </div>
      <div class="muted small">${draft.mode === 'filter'
        ? 'filter the cube: the facts outside the selection are not in the cube, and this dimension has the selected members'
        : 'restrict members: this dimension has the selected members, the facts are not filtered; refused while the facts hold a value it excludes'}${
        current ? '' : '; no selection now'}${values && values.more ? ` (the first ${values.values.length} values are listed)` : ''}</div>
      ${values && values.error && html`<div class="field-error">${values.error}</div>`}
      ${error && html`<div class="field-error">${error}</div>`}
    </span>`;
}

function DimensionPane({ doc, edit, dim, sel, select, suggestions, captions, characteristics, onFix }) {
  const time = isTime(dim);
  const captionColumns = keyAttributeOf(dim) ? captions.get(attr(dim, 'table')) || [] : [];
  const caption = captionOf(dim) || '';
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
      placesOf(doc, dim).forEach(({ cube, name }) => columnsOfDimension(cube, name).forEach((c) => c.remove()));
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
      <${FixedField} key=${JSON.stringify(selectionsOf(isShared(dim) ? usagesOf(doc, dim)[0]?.cube : dim.parentNode))}
        doc=${doc} dim=${dim} characteristics=${characteristics} onFix=${onFix} />
      <${SelectionField} doc=${doc} dim=${dim} characteristics=${characteristics} onFix=${onFix} />
      <label>Time</label>
      <span class="row">
        <${Check} checked=${time} label="Time dimension" onChange=${(on) => edit(() => setTimeDimension(dim, on, suggestions))} />
        <span class="muted small">enables the time functions (Ytd, ParallelPeriod, …); every level then needs a time level type</span>
      </span>
      ${captionColumns.length > 0 && html`<label>Member caption</label>
      <span class="row">
        <select value=${caption} title="The column that captions the members (the key attribute's NameColumn); they stay named by their key"
          onChange=${(e) => edit(() => setCaption(doc, dim, e.target.value))}>
          ${!captionColumns.includes(caption) && html`<option value=${caption}>${caption || '–'}</option>`}
          ${captionColumns.map((c) => html`<option value=${c}>${CAPTION_LABELS[c] || c} (${c})</option>`)}
        </select>
        <span class="muted small">members are named by their key; the caption is what reports show</span>
      </span>`}
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
              onCommit=${(v) => edit(() => renameAttribute(doc, dim, a, v))} /></td>
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
              onClick=${() => edit(() => {
                for (const { cube, name } of placesOf(doc, dim)) {
                  columnsOfDimension(cube, name).filter((c) => attr(c, 'sourceAttribute') === attr(a, 'name')).forEach((c) => c.remove());
                }
                a.remove();
              })}>✕</button></td>
          </tr>`;
        })}</tbody>
      </table></div>
    </section>

    <section class="section">
      <header>
        <h3>Hierarchies</h3><span class="spacer"></span>
        <button onClick=${addHierarchy}>Add hierarchy</button>
      </header>
      <div class="body">
        ${!hierarchies.length && html`<span class="muted">None. A hierarchy has attributes as levels, top level first; a user hierarchy nests several.</span>`}
        ${hierarchies.map((h, i) => html`<${HierarchyEditor} key=${i} doc=${doc} edit=${edit} dim=${dim} h=${h}
          others=${[...attrNames, ...hierarchies.filter((o) => o !== h).map((o) => attr(o, 'name'))]} />`)}
      </div>
    </section>

    <div class="row"><button class="danger" onClick=${remove}>Remove dimension</button></div>
  </div>`;
}

// A level over an attribute is named by its key unless it names a column (the reference's RolapLevel: the
// attribute's NameColumn only captions it): one over an attribute another level is over is named as that one is (the
// proposal's level over the key attribute by KEY_NAME or COMPOUND_KEY), else by the key.
function setLevelSource(dim, level, attribute) {
  level.setAttribute('sourceAttribute', attr(attribute, 'name'));
  const other = hierarchiesOf(dim).flatMap((h) => kids(h, 'Level'))
    .find((l) => l !== level && attr(l, 'sourceAttribute') === attr(attribute, 'name'));
  const nameColumn = other && attr(other, 'nameColumn');
  if (nameColumn) level.setAttribute('nameColumn', nameColumn);
  else level.removeAttribute('nameColumn');
}

function HierarchyEditor({ doc, edit, dim, h, others }) {
  const [open, setOpen] = useState({});
  const time = isTime(dim);
  const levels = kids(h, 'Level');
  const attributes = attributesOf(dim);
  const attrNames = attributes.map((a) => attr(a, 'name'));
  const hasAll = isTrue(h, 'hasAll', true);
  const name = attr(h, 'name');
  // an unnamed hierarchy is [dimension], as is one named like the dimension and an attribute of the dimension's name
  const clash = (!name || name === attr(dim, 'name')) && (others.includes('') || others.includes(attr(dim, 'name')));
  const levelNames = levels.map((l) => attr(l, 'name'));

  const addLevel = (source) => edit(() => {
    const a = attributes.find((x) => attr(x, 'name') === source);
    let levelName = source;
    for (let n = 2; levelNames.includes(levelName); n++) levelName = `${source} ${n}`;
    const level = create(doc, 'Level', {
      name: levelName,
      uniqueMembers: levels.length === 0 ? 'true' : 'false',
      sourceAttribute: source,
      levelType: time ? attr(a, 'levelType') || 'TimeUndefined' : '',
    });
    if (a) setLevelSource(dim, level, a);
    h.appendChild(level);
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
      ${clash && html`<div class="notice warn">Name the hierarchy: the dimension has another unnamed hierarchy or one (or an attribute)
        named '${attr(dim, 'name')}', and an unnamed hierarchy (or one named like the dimension) would share its unique name.</div>`}
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
            <td><${Select} value=${attr(l, 'sourceAttribute')} options=${attrNames} onChange=${(v) => edit(() => {
              const a = attributes.find((x) => attr(x, 'name') === v);
              if (a) setLevelSource(dim, l, a); else l.setAttribute('sourceAttribute', v);
            })} /></td>
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
  // accept puts the views in place of the placeholders the caption columns were keyed by
  const [captions, setCaptionKeys] = useState(session.captions);
  // fixing replaces the tables the suggestions are keyed by
  const [suggestions, setSuggestions] = useState(session.suggestions);
  // the characteristics of the cube's provider with their foreign keys, which fixing changes (POST fix answers them)
  const [characteristics, setCharacteristics] = useState(session.characteristics);
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
  // fixes the cube's characteristics on the server, which rewrites the schema: one edit, undone as any other
  const fix = useCallback(async (cube, selections) => {
    const d = await api('POST', 'fix', { cube, ...selectionParams(selections) }, serialize(doc));
    const next = parseXml(d.xml);
    setCharacteristics(d.characteristics);
    setCaptionKeys((old) => new Map([...old, ...captionKeys(d.captionColumns)]));
    setSuggestions((old) => {
      const keys = new Map(old);
      for (const { from, to } of d.tables) {
        for (const [key, levelType] of old) if (key.startsWith(`${from}|`)) keys.set(`${to}|${key.slice(from.length + 1)}`, levelType);
      }
      return keys;
    });
    replace(next);
  }, [doc, replace]);
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

  // an undo or the XML tab can change the selection: the foreign keys of the characteristics are asked again (POST fix
  // with the cube's own selection, the schema is not replaced)
  const firstCube = cubesOf(doc)[0];
  const docSelection = JSON.stringify(selectionsOf(firstCube).map((s) => `${s.mode}:${s.characteristic}=${s.rows}`).sort());
  const knownSelection = JSON.stringify(characteristics.filter((c) => c.mode).map((c) => `${c.mode}:${c.name}=${c.selection}`).sort());
  useEffect(() => {
    if (!characteristics.length || !firstCube || docSelection === knownSelection) return;
    api('POST', 'fix', { cube: attr(firstCube, 'name'), ...selectionParams(selectionsOf(firstCube)) }, serialize(doc))
      .then((d) => setCharacteristics(d.characteristics), () => {});
  }, [docSelection, knownSelection]);

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
      setCaptionKeys(captionKeys(result.captionColumns));
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
          : shownSel.kind === 'cube' ? html`<${CubePane} key=${JSON.stringify(shownSel)} doc=${doc} edit=${edit} cube=${target} select=${setSel}
              characteristics=${characteristics} />`
            : shownSel.kind === 'dim' ? html`<${DimensionPane} key=${JSON.stringify(shownSel)} doc=${doc} edit=${edit} dim=${target} sel=${shownSel}
                select=${setSel} suggestions=${suggestions} captions=${captions} characteristics=${characteristics} onFix=${fix} />`
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
          catalog: catalogNameOf(attr(schemaOf(doc), 'name')),
          source: { kind: 'proposal', name: d.provider.name, providerKind: d.provider.kind, text: d.provider.text, factTable: d.provider.factTable },
          characteristics: d.characteristics || [],
          notes: d.notes || [],
          suggestions: suggestionKeys(doc, d.suggestions),
          captions: captionKeys(d.captionColumns),
        };
      } else {
        const d = await api('GET', 'schema', { catalog: what.name });
        next = {
          doc: parseXml(d.xml),
          catalog: d.catalog,
          source: { kind: 'schema', name: d.catalog, file: d.file, changedAt: d.changedAt, changedBy: d.changedBy },
          characteristics: d.characteristics || [],
          notes: [],
          suggestions: new Map(),
          captions: captionKeys(d.captionColumns),
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
