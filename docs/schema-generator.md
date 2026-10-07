# Schema generator

Decided on 2026-10-05. The generator takes an arbitrary BW InfoProvider (a HANA-optimised InfoCube or a cube-type
aDSO), proposes a Mondrian schema for it, lets the user edit the proposal in a UI under `/zzxxmla1/schema`, and on
acceptance generates the CDS views the schema names and saves the schema as a file of the server
(`/WEB-INF/schema/<name>.xml`, registered as a catalog in `/WEB-INF/datasources.xml`, see `environment.md`, Catalogs).
It replaces the old "Schema generator" plan of `bw-to-schema-mapping.md`, which read the metadata tables of
`metadata-tables.md`.

## Providers

| | HANA-optimised InfoCube | Cube-type aDSO (template "InfoCube", `RSOADSO-ACTIVATE_DATA` and `CUBEDELTAONLY` set) |
|---|---|---|
| Metadata | `RSDCUBE`, `RSDDIMEIOBJ`, `RSDKYF` | `CL_RSO_ADSO_API=>READ` (objects, aggregation per key figure) |
| Fact table of the schema | `/BIC/F<cube>` | the view `/BIC/A<adso>7` (inbound and active table together, columns `REQTSN`, `RECORDMODE` and the fields) |
| Characteristic columns | `SID_<char>`, the SID | the characteristic value; the field is named after the InfoObject without the leading `0` (`CALMONTH`, `D_NW_CHANN`) |
| Dimension join | `foreignKey` on the SID column, the view's `SID` as key | the value column, the view's key column as key |
| Time characteristics | SIDs: characteristics like the others, on the views of their SID tables; `0CALDAY` has no SID table and is not proposed | plain value columns (`CALDAY` DATS, `CALMONTH` NUMC 6, ...): characteristics like the others, on the views of their SID tables; `0CALDAY` is not proposed |

Generated names are asked from BW, never built: their prefix depends on the BW namespace (`/BIC/` for the customer
namespace, `/BI0/` for SAP's, another prefix for a development namespace). `CL_RSO_ADSO=>GET_TABLNM` gives an aDSO's
tables and views by type (`AQ` inbound, `AT` active, `VR` the 7 view), the function group `RSDN_*` the rest:
`RSD_CHKTAB_GET_FOR_CHA_BAS` (SID, attribute and text tables of a characteristic), `RSD_FACTTAB_GET_FOR_CUBE`,
`RSD_FIELDNM_GET_FROM_IOBJNM` (the field of an InfoObject; `RSDIOBJ-FIELDNM` holds the same name and is what the
reader joins). `ZZXXMLA1_CL_BW_VIEW_GEN` asks `RSD_CHKTAB_GET_FOR_CHA_BAS` for the SID and attribute tables and drops
any namespace from a view column, not only `/BIC/`; a characteristic without attribute table gets a view of its SID
table alone (SID and key). A reference characteristic is asked for by its basic characteristic (`RSDCHA-CHABASNM`; `0D_NW_SOLD` of
`0D_NW_C01` references `0D_NW_CUST`); its fact column stays `SID_<characteristic>`. A characteristic whose tables BW
cannot name, or whose key field is not a column of them, is a note (no SID table, so no view), not a failure.

Which providers: an InfoCube is HANA-optimised when `RSDCUBE` has type `B` and subtype `F` (flat; `ZFMSALES` and
`0D_NW_C01` are), and its fact table must have a `SID_<characteristic>` column per characteristic (the reader refuses
the cube otherwise); a cube-type aDSO has `RSOADSO-ACTIVATE_DATA` and `CUBEDELTAONLY` set. An aDSO's text is the
`RSOADSOT` row of type `EUSR` without column. The package dimension (`DPA`) is left out silently; units and
currencies (`UNI`), fields without InfoObject and time-dependent attributes are notes.

The dimension views come from `ZZXXMLA1_CL_BW_VIEW_GEN` for both kinds: they carry both `SID` and the key, so only the
join column of the schema differs.

## The proposal

The proposal is a flat schema in the reference's format (Mondrian 3 schema XML with eMondrian's `DimensionAttribute`s),
like `reference/schema/FoodmartBW.xml` without its hand-written parts:

- one `Dimension` per characteristic of the provider, on its generated view, the characteristic as the key attribute
  and every time-independent attribute as a further `DimensionAttribute`. Only the key attribute is a hierarchy: the
  others get `attributeHierarchyEnabled="false"` and serve as the levels and properties of the hierarchies the user
  makes (decided on 2026-10-06, after the reference's `FoodMart.xml`: each dimension there has one hand-written
  hierarchy, most columns are member properties, and only a few, Gender or Store Type, were made dimensions by hand;
  an attribute hierarchy per attribute gave dozens of hierarchies per cube). BW's standard time characteristics
  (`0CALWEEK`, ..., `0FISCVARNT`) keep their attributes' hierarchies. Names are the InfoObject texts; the key attribute is named
  like its dimension; a repeated name gets the InfoObject in brackets (`Country (ZFMCNTRY2)`). On an InfoCube the key
  attribute is keyed by the view's `SID` and named by the value (`NameColumn`, which `ZZXXMLA1_CL_SCHEMA` reads for
  this), so members are named by the characteristic, not by BW's numbers; on an aDSO it is keyed by the value. A view
  not generated yet is named by a placeholder (`ZZXXMLA1_C_<characteristic>`, no DDIC name), which acceptance replaces;
- no user hierarchies: BW's metadata does not say which attributes nest in which order (FoodMart's Store and Product
  hierarchies were written by hand). The UI builds them from the attributes;
- key figures with aggregation SUM, MIN or MAX become measures with that aggregator. Exception aggregation and
  non-cumulative key figures are listed as not proposed rather than mapped wrongly. The first measure is the default.

### Time

Decided on 2026-10-06: an aDSO is modelled exactly as an InfoCube. Conceptually both are a fact table with
characteristics, and every dimension of the proposal is joined to the CDS view of its characteristic on top of what
BW has; no dimension is built on the fact table's own columns, and the proposal has no time hierarchies.

- **Standard BW time characteristics** (`0CALWEEK`, `0CALMONTH`, `0CALQUARTER`, `0CALYEAR`, `0FISCPER`, `0FISCYEAR`,
  `0FISCVARNT`) are characteristics like the others, on both kinds: each a dimension on the view of its SID table
  (whose attribute table holds only the initial row, so the view is a left outer join, see Implementation), joined
  on the SID column (InfoCube) or the value column (aDSO). Their level type is a suggestion. `0CALDAY` has no SID
  table, so it has no view and is not proposed (a note): not supported, on either kind. Member names are BW's values
  (`19971`, `199701`). The aDSO joins compare the view's key (NUMC cast to a number) with the fact column (NUMC
  text); HANA converts, checked with queries on `ZFMSALESA` (quarters, months, weeks and stores give FoodMart's
  numbers).
- **Any dimension can be marked as time** in the UI, like `ZFMDATE` of the reference schema: a switch writes
  `type="TimeDimension"`, every attribute gets a level type (pre-selected from the suggestions, else `TimeUndefined`,
  because Mondrian requires one on every level of a time dimension, the attribute hierarchies included), hierarchies
  get level types, `hasAll` and a default member (`ZFMDATE`'s main hierarchy has no All member and defaults to
  `[Time].[1997]`, because BW's empty member, SID 0, would come first). A user hierarchy such as year > quarter >
  month needs the levels as attributes of one dimension, i.e. a characteristic whose attributes are those values (as
  `ZFMDATE` has); separate dimensions per time characteristic do not nest.
- The generator only suggests level types, it never switches a time dimension on: a standard time characteristic
  suggests its type, a DATS key or attribute suggests `TimeDays`. A DATS characteristic alone is no reason for a time
  dimension: delivery dates, birth dates and validity dates are dates too.

## Implementation (step 3)

- `ZZXXMLA1_CL_BW_PROVIDER`: `providers( )` lists the InfoCubes and aDSOs, `read( name )` gives one provider's
  metadata (fact table, characteristics with fact column, view, key column and attributes, key figures with
  aggregation, notes). Only reads; errors are
  `ZZXXMLA1_CX_BW_PROVIDER`. Its tests read `ZFMSALES` and `ZFMSALESA`.
- `ZZXXMLA1_CL_SCHEMA_PROPOSAL`: `propose( provider )` gives the schema definition, its XML, the notes and the
  time suggestions. It writes schema XML and reads it with `ZZXXMLA1_CL_SCHEMA_DEF=>parse`, so the definition holds
  Mondrian's defaults (a Boolean left unset in a hand-built definition would be written as `false`). Its tests use
  hand-built metadata, and two load the real `ZFMSALES` and `ZFMSALESA` proposals through `ZZXXMLA1_CL_SCHEMA`. Run the class (F9,
  or `sapcli class execute`) to print the proposals of the FoodMart providers.

- `ZZXXMLA1_CL_BW_VIEW_GEN`: the view joins the SID table with the attribute table as a left outer join, the key
  taken from the SID table, so every value with a SID is a member, with or without attributes. An inner join lost
  the time characteristics' values: their SID tables hold the values in use, their attribute tables only the initial
  row.

Also: `ZZXXMLA1_CL_SCHEMA` gives an attribute hierarchy the attribute's name as `hier_name`, so an attribute named like
its dimension and an unnamed `Hierarchy` of that dimension share it; the UI must not create that (or the reader must
tell them apart). Compounded characteristics are not handled (the key alone is not unique).

## The API (step 4)

`ZZXXMLA1_CL_SCHEMA_API` (`handle`: method, path below the ICF node, query parameters, body in; status, content type,
body and `Allow` out), routed by `ZZXXMLA1_MAIN_ENDPOINT` for every path below `/schema/api/`; anything else stays the
XMLA endpoint. Answers are JSON written by hand (`escape( ... e_json_string )`, there is no JSON library on every 7.50);
a refused request is `{"error": "..."}` with 400 (the request is wrong), 404 (no such resource or provider), 405 (with
`Allow`) or 500.

- `GET providers`: `{"providers": [{name, kind, text, infoarea}]}`.
- `GET proposal?provider=X`: `{provider: {name, kind, text, infoarea, factTable}, xml, outline, notes: [{iobjnm,
  reason}], suggestions: [{dimension, attribute, levelType}]}`. The outline is the schema as the UI lists it:
  `{name, dimensions: [dimension], cubes: [{name, caption, factTable, defaultMeasure, dimensions: [{name, source,
  foreignKey} | {name, foreignKey, dimension}], measures: [{name, column, aggregator, formatString}]}]}`, a dimension
  being `{name, type, table, attributes: [{name, usage, keyColumn, nameColumn, levelType}], hierarchies: [{name,
  hasAll, defaultMember, levels: [{name, sourceAttribute, levelType}]}]}`. The XML is what the UI edits and sends back.
- `GET schemas`: `{"schemas": [{catalog, dataSource, file, exists, changedAt, changedBy}]}`, the catalogs of the data
  sources file, each name once with its first definition (the one the XMLA endpoint reads); `changedAt` is UTC ISO
  8601 or null.
- `GET schema?catalog=X`: `{catalog, dataSource, file, changedAt, changedBy, xml, outline}`, an accepted schema to edit
  again (404 if the catalog or its file is missing).
- `POST check?catalog=X`: the body is the edited schema XML; the checks of `accept` (Accepting, steps 1 to 3), nothing
  is written. Answer `{catalog, file, newCatalog, views: [characteristic]}`: the file `accept` would write, whether it
  adds the catalog, and the characteristics whose views it would generate. The UI calls it while the user edits, to
  show the reader's errors early.
- `POST accept?catalog=X`: the body is the edited schema XML (no JSON to parse on the server); without `catalog` the
  schema's name is the catalog. Answer `{catalog, file, views: [{characteristic, ddlName, viewName}], xml}`, the XML
  as written.
- `POST remove?catalog=X`: removes the catalog and its cubes (Removing). Answer `{catalog, removedFiles: [path]}`;
  404 if no data source has the catalog.

The schema file of an existing catalog is its `<Definition>`, so a schema reopened with `GET schema` goes back to its
own file (`FoodmartBW.xml` for `ZFOODMART`); `accept` under an existing catalog therefore replaces its schema, and the
UI has to say so (`check` answers `newCatalog: false`). A new catalog gets `/WEB-INF/schema/<catalog>.xml`, so its name
is also a file name (letters, digits, `_`, `-`, `.`).

## Accepting

On acceptance the server checks everything before it changes anything, so nothing is saved that the engine would
reject later:
1. the body parses as a Mondrian schema (`ZZXXMLA1_CL_SCHEMA_DEF`), and the catalog name is valid;
2. the schema file is the catalog's `<Definition>` if the catalog exists, else `/WEB-INF/schema/<catalog>.xml`; the
   data sources file gets the catalog: added to the `<Catalogs>` of the first data source (inserted as text, so
   the file keeps its comments and layout, then read back to confirm), unchanged if a data source has it with this
   file, refused if one has it with another file;
3. all catalogs of that file are loaded together in `ZZXXMLA1_CL_SCHEMA`, this one with the edited schema, as the XMLA
   endpoint will load them; the reader's errors are returned (a time level without level type, a dimension without
   table, a cube name another catalog has, an unnamed `Hierarchy` in a dimension with an attribute of the dimension's
   name, ...).

The last one is a trap of the proposal: it names the key attribute like its dimension, so a user hierarchy added
without a name clashes with it. eMondrian gives both the same unique name (`HierarchyBase`: an unnamed hierarchy and
one named like its dimension are both `[Dimension]`) and loads an ambiguous cube; the reader refuses it instead, with
a message naming both and asking for a hierarchy name. Renaming one of them would invent names eMondrian does not
have.

Then the views of the tables named by a placeholder (`ZZXXMLA1_C_<characteristic>`) are generated
(`ZZXXMLA1_CL_BW_VIEW_GEN->generate`, numbered: `ZZXXMLA1_C0000026` / `ZZXXMLA1V0000026`), and the placeholders
in the schema (dimension tables, hierarchy `Table`s) are replaced by their database views; the schema is written as sent if no name changed, else as Mondrian's toXML. Last
the schema file and, for a new catalog, the data sources file are written and the work is committed.
The next XMLA request reads the new catalog. View generation runs as the anonymous user of the node, too (checked).

Each cube is served from its own catalog for now (`mvp-scope.md`, Catalog decision): a proposal is one schema with one
cube, accepted as one catalog; a cube is moved to another catalog by removing its catalog and accepting it again.

## Removing

`remove` takes a catalog out of the server (decided 2026-10-06), checked before anything changes:
1. the data sources file without the catalog: every `<Catalog>` of that name, in any data source, is cut out of the
   text with its own line (so the file keeps its comments and layout), then the file is read back: refused unless the
   catalog is gone and every other catalog is unchanged; 404 if no data source has it;
2. the schema files of the removed entries are deleted, except one another catalog still names (and never the data
   sources file itself).
Then the data sources file is written, the schema files deleted and the work is committed; the next XMLA request no
longer has the catalog's cubes. The views stay: they are per characteristic, and other schemas (or the FoodMart
regeneration) use them. A data source may be left with no catalog (`<Catalogs>` allows none).
Removing `ZFOODMART` breaks the reference tests until `python scripts/sap-files.py deploy` writes it back from git.

## UI

`ZZXXMLA1_MAIN_ENDPOINT` routes `/zzxxmla1/schema/api/...` to a service class (string in, string out, like
`ZZXXMLA1_CL_XMLA_HANDLER`, so it is unit-testable and testable from Python):

- `GET providers`: the InfoCubes and cube-type aDSOs;
- `GET proposal?provider=X`: the proposed schema as XML (`ZZXXMLA1_CL_SCHEMA_DEF`) plus a JSON outline for the UI;
- `GET schemas`, `GET schema?catalog=X`: the accepted schemas, to edit one again;
- `POST check`: the checks of accept, nothing written;
- `POST accept`: the edited schema; checks, generates the views, saves the file, registers the catalog;
- `POST remove`: removes a catalog and its schema file.

The UI edits the schema XML in the browser (DOMParser/XMLSerializer) and shows the outline; the server never parses
JSON.

Identity (decided 2026-10-06): the API runs with the same identity as the XMLA endpoint, i.e. the anonymous logon of
the `/zzxxmla1` node, `accept` included. This is work in progress: anonymous calls will be prohibited later, together
with authorisation, which are both out of scope now.

`/zzxxmla1/schema/` serves the app itself from the code (`ZZXXMLA1_CL_WEB_APP_FILES`, generated from the plain files
in git; decided 2026-10-07, before that they were files of the server in `ZZXXMLA1_FILE` that had to be uploaded). The app is Preact with htm, vendored as one ES module of about
10 KB, without a build step: what is in git is what the server serves, identical on every release.

Implemented (2026-10-06):

- `ZZXXMLA1_CL_WEB_APP` serves the app's files below `/schema/` from the code (only GET, content type by extension, no `..`, nothing
  outside `/schema/`): `/schema` redirects to `/schema/` (keeping the query string, e.g. `sap-client`), so the app's
  relative URLs (`app.js`, `api/...`) resolve below the node; a folder serves its `index.html`. ICF gives
  `~path_info` without the trailing `/`, so `ZZXXMLA1_MAIN_ENDPOINT` takes it from `~request_uri`. Answers carry
  `Cache-Control: no-cache`, so a new version of the class is seen at once.
- `web/schema/`: `index.html`, `app.css` (light and dark), `app.js` and `vendor/htm-preact-standalone.mjs` (htm
  3.1.1 from unpkg, unchanged); nothing is built. They are code of the package: `ZZXXMLA1_CL_WEB_APP_FILES`, generated
  by `scripts/generate-web-app-abap.py` after every change, has a method per file returning its text (`app_js`, ...)
  and `file( path )` choosing it, so the app needs no deployment of its own and is always the one of the code it
  calls. Changing it is: edit `web/schema/`, generate, `scripts/sap-write.py zzxxmla1_cl_web_app_files`.
- The start page lists the accepted schemas (`GET schemas`) and the providers with a filter (`GET providers`). Opening
  one gives an editor on the schema XML (`GET proposal`/`GET schema`); `#proposal/<provider>` or `#schema/<catalog>`
  in the URL reopens it after a reload. The outline (a tree of cubes and dimensions) edits the DOM: schema name and
  description; cube name, caption, default measure, dimension usages (rename, remove); measures (rename, aggregator,
  format string, visible, order, remove); dimensions (rename, which renames their usages and default members,
  caption, remove with their usages); attributes (rename, which renames the levels and properties on them, whether
  the attribute is a hierarchy of its own, `attributeHierarchyEnabled`, not offered off for a dimension's last
  hierarchy, remove if unused); the time switch (`type="TimeDimension"`, level types from the proposal's suggestions else
  `TimeUndefined`, removed again when switched off); user hierarchies (name, All member and its name, default
  member, levels from attributes with level type, unique members and order, member properties). The XML tab edits
  everything else as text. Undo (Ctrl+Z) keeps the last 100 states.
- Every change is sent to `check` (debounced, the last request wins); its refusal is shown in full under the top bar
  and keeps Accept disabled. Accept shows what `check` answered (the file, new or replaced catalog, the views to
  generate) before it calls `accept`, then reopens the schema as written (DDL names replaced by views).
- Each accepted schema on the start page has Remove…: a dialog names the catalog, its data source and schema file
  and that the views are kept, then calls `remove` and lists the files deleted; the list is read again.
- Only what the server evaluates is offered: aggregators `sum` and `count` (the engine sums every other measure), no
  calculated members (`ZZXXMLA1_CL_SCHEMA` does not read the schema's); the XML tab can still write them.
- The UI warns about the unnamed-hierarchy clash before the server refuses it, and about a hierarchy without All
  member and without default member (BW's empty member may come first).

Not chosen: SAPUI5. The UI5 a system serves depends on its release and UI add-on (1.136 on the development system,
far older on a plain 7.50), bundling OpenUI5 means tens of megabytes, and a CDN needs internet access from the
browser. Also not: RAP/Fiori elements (not on 7.50), SEGW OData (a generated entity model for what are a few
RPC-style calls, and a UI5 repository upload outside our sync), Web Dynpro and BSP.

## Test provider

`ZZXXMLA1_CL_BW_FOODMART_GEN` creates, next to the InfoCube `ZFMSALES`, the cube-type aDSO `ZFMSALESA` with the same
facts: the FoodMart characteristics `ZFMPROD`, `ZFMCUST`, `ZFMSTORE`, `ZFMPROMO`, the standard time characteristics
`0CALDAY`, `0CALWEEK`, `0CALMONTH`, `0CALQUARTER`, `0CALYEAR` in place of `ZFMDATE` (so the standard time path is under
test), and the three key figures (`environment.md`, FoodMart data for the BW cube). Its numbers compare with
eMondrian's; only the time member names differ.
