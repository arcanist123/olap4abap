# CLAUDE.md

Project context for Claude Code. This repository is the single source of truth for the project: code, decisions and
procedures live here, not in any per-machine memory.

## Goal

**olap4abap** (https://github.com/arcanist123/olap4abap, Eclipse Public License 2.0): build an XMLA endpoint with its
own MDX engine ("Mondrian in ABAP") that runs on an SAP system and serves cubes defined
on top of SAP BW data. The reference implementation is eMondrian (a Mondrian fork), run locally in Docker. SAP BW's
native MDX/XMLA engine is deliberately NOT used: it supports little of modern MDX and its lexer cannot parse some of it.
Long term the project is also transpiled to JavaScript with the abaplint transpiler, with a plugin of ours for simple
CDS views as a transpilation and execution target (`docs/next-steps.md`, Later).

**The BW cube `ZFMSALES` (FoodMart Sales, InfoArea `ZFOODMART`, generated and loaded by
`ZZXXMLA1_CL_BW_FOODMART_GEN`) is the main data source of this project.** Develop and test the engine against it first:
the Mondrian tests and eMondrian's expected results use FoodMart names and numbers, so they apply to it directly. The
SAP demo cube `0D_NW_C01` was only used for the initial BW table analysis; do not build on it.

Read before designing anything:
- `docs/mvp-scope.md` - what is in/out of scope and why
- `docs/bw-to-schema-mapping.md` - how BW tables map to Mondrian's model
- `docs/test-strategy.md` - how correctness is verified
- `docs/mondrian-hierarchies-and-time-dependency.md` - background on Mondrian's modelling
- `docs/environment.md` - systems, ports, build procedures, tool quirks
- `docs/next-steps.md` - what to do next, in which order, and the open decisions
- `docs/known-issues.md` - debt (what is wrong within the built scope), deliberate deviations and the reference's
  known wrong answers; read before comparing answers. Not-yet-built features are scope, not issues

## Conventions

- ABAP development objects live in package `$ZZXXMLA1` (local package; created by the user in ADT/SE80 because
  creating packages through the ABAP FS tool fails with "Parameter recordChanges could not be found").
- **Naming:** every development object uses the first 8 letters of its package name (without `$`) as prefix, i.e.
  `ZZXXMLA1_...`. Example: `ZZXXMLA1_CL_HTTP_HELLOWORLD`, `ZZXXMLA1_MAIN_ENDPOINT`.
- **Target release is NetWeaver 7.50** (`docs/mvp-scope.md`): write 7.50 syntax only, and run `scripts/abaplint.sh`
  after changes; the 2025 development system accepts newer syntax that 7.50 rejects.
- After every ABAP edit run the diagnostics check (`get_abap_diagnostics`) and then activate. The editor's checker can
  be stale after multi-step edits; a small re-save of the changed line forces a resync.
- **No local includes in classes:** a class has only its global source and, if it has tests, its test include
  (`.clas.testclasses.abap`); no local definitions/implementations (`locals_def`/`locals_imp`). A helper class, an
  exception or a type a class needs is a global object of its own.
- **No circular dependencies** between classes and interfaces (abaplint's `cyclic_oo`, run by `scripts/abaplint.sh`):
  a class defines the structures and tables it needs itself, even as a copy of another class's (structurally equal
  types are compatible); a call back goes through an interface, where the reference has one its port (`Evaluator`,
  `SchemaReader`). Not `TYPE REF TO object` with a cast, and no `GLOBAL FRIENDS` for helpers that call back.
- Put logic in small private methods and test those in the class's local test include
  (`.clas.testclasses.abap`, created with `abapfs_create_test_include`); `IF_HTTP_SERVER` is awkward to fake.
- ABAP SQL via the SQL tool: keep statements multi-line, use `ORDER BY ... ASCENDING/DESCENDING`, functions need
  spaces inside parentheses.
- **License header:** every ABAP include with code starts with `scripts/abap-license-header.txt` (EPL-2.0, credit to
  Mondrian); the generators add it. New files get it too; `LICENSE` and `NOTICE` are at the root.
- **No Mondrian in the code:** comments name the Java classes they port (`RolapEvaluator`, `MdxParser.jj`) and call
  Mondrian/eMondrian "the reference" / "the reference server"; the name Mondrian appears only in the license header.
  Where the reference server names itself in an answer, olap4abap writes its own name (`olap4abap Error:`, faultactor
  `olap4abap`, `olap4abap.EvaluationException`, `olap4abap.SchemaDef$...`, provider name); `scripts/reference_texts.py`
  maps the reference's texts to these, and the comparison scripts and generators go through it. A new such text
  needs a rule there.

## Current state

- `ZZXXMLA1_CL_HTTP_HELLOWORLD` - hello world HTTP handler with a passing unit test (a leftover `ZCL_HTTP_HELLOWORLD`
  still exists in `$TMP` and can be deleted).
- `ZZXXMLA1_MAIN_ENDPOINT` - `IF_HTTP_EXTENSION` handler behind ICF service `/zzxxmla1`: `/schema/api/...` goes to
  `ZZXXMLA1_CL_SCHEMA_API`, the rest of `/schema/...` to `ZZXXMLA1_CL_WEB_APP` (the schema builder's files, from the code),
  `/bw/...` to `ZZXXMLA1_CL_BW_MDX_API` (BW's MDX on InfoProviders, `POST bw/check?user=&keyDate=`: the
  authorisation result of a user for a statement in BW's names, never data; so far it resolves the statement,
  `ZZXXMLA1_CL_MDX_SCHEMA_READER=>for_bw_cube`; `docs/next-steps.md`, Next: BW's MDX on InfoProviders); otherwise GET returns the start page (links to the schema builder, MDX console, time master data and trace, and the XMLA URL
  with `sap-client` for clients), POST hands the SOAP body to `ZZXXMLA1_CL_XMLA_HANDLER` (string in, string out; so far only
  DISCOVER_DATASOURCES, anything else is a SOAP fault), other methods 405.
- XMLA tests: `python scripts/xmla_test.py` replays `reference/<case>/` against SAP (see `docs/test-strategy.md`);
  `python scripts/compare-applicable.py` runs Mondrian's test statements on eMondrian and SAP and groups the gaps.
  BW hierarchies: `python scripts/bw_hierarchy_test.py` compares with BW's own MDX, asked live
  (`ZZXXMLA1_CL_BW_HIERARCHY_PROBE`). Shared nodes: `python scripts/ssas_compare.py` asks SAP's `ZCLHIER` the
  `execute_ssasmd_*` statements in olap4abap's names and compares the values with SSAS's. Analysis authorisations:
  `python scripts/auth_probe.py` records BW's answers per test user in `reference/auth/` (the oracle of the check).
- The model is the catalogs' Mondrian schemas, configured as in Mondrian: the server has files (table `ZZXXMLA1_FILE`,
  `ZZXXMLA1_CL_FILES`), `/WEB-INF/datasources.xml` (`reference/schema/datasources-sap.xml`) lists the data sources and
  their catalogs, read by `ZZXXMLA1_CL_REPOSITORY` (Mondrian's `FileRepository`/`DataSourcesConfig`), and each catalog's
  `<Definition>` is the path of its schema file (`/WEB-INF/schema/FoodmartBW.xml`). A schema or catalog is added with
  `scripts/sap-files.py`, no new ABAP object (`docs/environment.md`, Catalogs).
  `ZZXXMLA1_CL_SCHEMA` (part of Mondrian's `RolapSchema`) reads them and gives the engine and the rowsets their cubes,
  dimensions, hierarchies, levels and measures, loading only the catalogs a request needs (`load`: an Execute's
  catalog, the catalogs a rowset's Catalog property and restrictions select; the schema builder's check loads all); data is read with native SQL through ADBC (`ZZXXMLA1_CL_SQL`). The old
  model tables and their generator are deleted (`docs/metadata-tables.md` keeps their rules).
- BW cube `ZFMSALES` with the complete FoodMart 1997 data (86,837 facts, totals equal FoodMart's), regenerated by one
  class run; the data is embedded in the six `ZZXXMLA1_CL_FM_DATA_*` classes. Procedure in `docs/environment.md`.
  These classes and `ZZXXMLA1_CL_BW_FOODMART_GEN` belong to a private repository, not to olap4abap: they are in SAP and
  a pull writes them into `src/`, but `.gitignore` keeps them out of this repository.
  The same run creates the cube-type aDSO `ZFMSALESA` (same facts, standard time characteristics `0CAL*`, reporting
  view `/BIC/AZFMSALESA7`) and regenerates the CDS views of the characteristics, which it deletes first.
- Schema generator (in progress, `docs/schema-generator.md`): proposes a schema for an InfoCube or cube-type aDSO,
  edited in a Preact UI under `/zzxxmla1/schema`, accepted into views and a schema file. Done: the provider reader
  `ZZXXMLA1_CL_BW_PROVIDER` (BW metadata, all names from BW) and the proposal `ZZXXMLA1_CL_SCHEMA_PROPOSAL` (schema
  XML read back through `ZZXXMLA1_CL_SCHEMA_DEF`) and the API `ZZXXMLA1_CL_SCHEMA_API` under
  `/zzxxmla1/schema/api` (providers, proposal, schemas/schema to reopen an accepted one, check, accept: checks all
  catalogs, generates the views, writes the schema file and the catalog; remove: a catalog and its schema file;
  `scripts/schema_api_test.py`). Each cube is served from its own catalog for the MVP (`docs/mvp-scope.md`, Catalog
  decision); an aDSO is proposed as an InfoCube is: every characteristic,
  the time ones too, a dimension on its CDS view (no dimensions on fact columns; `0CALDAY` has no SID table and is not
  supported); a time dimension only if the user marks one, but for the fiscal defaults below. The proposal follows `docs/bw-schema-design-guide.md`
  (BW's model): technical names as identifiers, texts as captions; per characteristic a flat unnamed hierarchy
  (members keyed by SID, named by the key: the level's `nameColumn` `KEY_NAME`, `COMPOUND_KEY` or the key; captioned
  by the EN text, the key attribute's `NameColumn` the medium, else long, else short text, `KEY_CAPTION` without
  texts, the view's caption columns `captionColumns` of the API; the key display, Excel showing only captions, is
  the builder's: per dimension "Key display" text as caption and key as property `Key`, key as caption (`KEY_CAPTION`)
  and text as property `Text`, or key only, with the text field, and on the cube pane a slider that sets every
  dimension, greyed out while they differ, read from the XML, no annotation; the key as member property `Key`, the display attributes as member properties, key and text, no `Text`
  property of the characteristic itself) and a flat hierarchy `<char>__<attribute>` per navigation attribute the
  provider switches on, captioned by the attribute's text; no attribute hierarchies, no user hierarchies (the user
  makes them in the UI), no BW hierarchies (offered per dimension as `bwHierarchies` of the API, the ones `RSHIEDIR`
  has for its characteristic, `ZZXXMLA1_CL_BW_HIERARCHY_COPY=>offered`; the dimension pane's "BW hierarchies", filtered by words or to the ticked ones, ticks
  them, a ticked one a `<Hierarchy>` annotated `olap4abap.bwHierarchy`, captioned by BW's text; a version-dependent
  one per version, named `<name>_<version>` (`ZCLDOC_ORG_001`) and annotated `olap4abap.bwHierarchyVersion` too; of
  an entirely time-dependent one the slice valid to 9999-12-31, as the texts; a time-dependent structure cannot be
  ticked; an aDSO's too); a default drill-through action with each characteristic's value, which the UI's
  "Double-click columns" adjusts; every dimension of the cube annotated
  `olap4abap.membersWithFacts`, which the UI's "Members with facts" switches per dimension (not on time ones); the cube
  annotated `olap4abap.omitEmptyCells`, which the cube pane's "Omit empty cells" switches. The views (`ZZXXMLA1_CL_BW_VIEW_GEN`, one per basic
  characteristic) carry the EN texts (every text field its own column, `TXTMD`, `TXTLG`, `TXTSH`, an attribute's
  `<ATTR>_TXTMD`, ... and its preferred `<ATTR>_TXT`, blank where BW has none), the key as name (`KEY_NAME`, `''` for
  SID 0, of a NUMC, DATS or TIMS key) and as caption (`KEY_CAPTION`, `#` for SID 0) and the time-dependent attributes
  at 9999-12-31, and every column as BW holds it,
  NUMC with its zeros, each NUMC column followed by its number `COLUMN_INT`: the proposal names BW's values (`0042`,
  String), FoodMart's schemas name the numbers (`docs/mvp-scope.md`, NUMC decision; "As numbers" left the UI). A
  compounded characteristic (`0FISCPER` with `0FISCVARNT`) is named and ordered by `COMPOUND_KEY` of its view
  (`K4/2024001`, SID 0 `''`; `KEY_CAPTION` `#/#`; the level's `nameColumn`, the key attribute's `OrderByColumn`), and
  an aDSO with one is read from its fact view
  (`ZZXXMLA1_CL_BW_VIEW_GEN=>generate_fact_view`: the reporting view with `SID_<field>` per compounded characteristic,
  placeholder `ZZXXMLA1_F_<aDSO>` until accept), so it is keyed by the SID as on an InfoCube
  (`docs/bw-schema-design-guide.md`, section 3.7). A cube can restrict characteristics by a selection, a BW range
  table each (section 3.8, `ZZXXMLA1_CL_BW_SELECTION`), in mode filter the cube or restrict members; a fixed value is
  filter the cube with one `I EQ` row. It is an edit of the schema: "Fixed value" and "Selection" (the rows, the mode, presets) on a dimension's pane (values from
  `GET values`), `POST fix?filter.0FISCVARNT=I EQ 'K4'` (also `members.C=<rows>`, `fixed.C=v`;
  `ZZXXMLA1_CL_SCHEMA_FIX`) rewrites the cube's tables and columns for the new selection and leaves the user's work;
  the proposal restricts nothing but its fiscal defaults (`ZZXXMLA1_CL_SCHEMA_DEFAULTS`, called by `GET proposal`): a
  provider with `0FISCYEAR` or `0FISCPER` gets `0FISCVARNT` filtered on `I EQ 'K4'`, `0FISCPER` restricted to the
  regular periods and the members of both to BW's interval of RSRHIERARCHYVIRT (`RSADMINS`; time dimensions cannot
  have members with facts), `I BT '1995' '2029'`, `I BT '1995010' '2029012'` with `E CP '*000'`, `'*013'` ... `'*016'`,
  and both as time dimensions (facts outside the interval leave a member restriction out, with a note); if the probe finds period 000 or special
  periods in the facts, the period is neither restricted nor time (a note: `0CALMONTH` is the time there)
  (`bw-schema-design-guide.md`, section 3.8, Fiscal time; `scripts/fiscal_default_test.py`). The cube is annotated `olap4abap.filter.<characteristic>` or
  `olap4abap.members.<characteristic>` with the rows (`olap4abap.fixed.<characteristic>` = `v` of older schemas is
  read as filter `I EQ 'v'`), the restricted characteristic keeps its dimension with the members of its selection (its
  view filtered on it), the facts are a fact view filtered on the filter-the-cube ones (an InfoCube's too; restricting
  members leaves the facts, and the probe `ZZXXMLA1_CL_SCHEMA_PROBE` refuses it on `POST fix`, accept and
  `check?probe=true` while the facts hold a value the selection excludes; `POST probe` probes every catalog) and a characteristic
  compounded with it a view filtered on it, so `0FISCPER` under one `I EQ` value of its variant is not compounded there
  (`2024001`, still keyed by its SID); the engine is not changed. Every generated view is a row of table `ZZXXMLA1_VIEW`
  (kind, characteristic or provider, selection), by which the generator finds it; accept and remove delete the
  filtered views no catalog's schema names (`scripts/fixed_selection_test.py`) and the BW hierarchy copies (tables,
  not-assigned view, copies) of the characteristics no catalog's schema names a BW hierarchy of, also generated
  objects the registry `ZZXXMLA1_HIETAB` does not name (`ZZXXMLA1_CL_BW_HIERARCHY_COPY=>delete_unused`, answered as
  `deletedHierarchyCopies`). Program `ZZXXMLA1_DELETE_ORPHANS` (SE38, test run by default;
  `ZZXXMLA1_CL_SCHEMA_API=>orphans`) deletes every generated object no catalog's schema names: also the plain and
  fact views accept and remove keep and the generator's DDL sources without row of `ZZXXMLA1_VIEW`; nothing if a
  schema cannot be read. The UI (`web/schema/`, Preact with htm, no build step) is served from
  the code below `/schema/` by `ZZXXMLA1_CL_WEB_APP`: the generated class `ZZXXMLA1_CL_WEB_APP_FILES` has a method per
  file returning its text (`scripts/generate-web-app-abap.py`, run after every change of `web/schema/`, then
  `sap-write.py` the class; nothing is uploaded or written by the setup); it
  edits the schema XML as a DOM (rename, remove, time dimensions, user hierarchies with levels and member properties,
  measures, raw XML), lets the server `check` every change and accepts (`scripts/schema_ui_test.py`).
- MDX console: `/zzxxmla1/schema/console.html` (`web/schema/console.js`, served from the same generated class as the schema builder)
  sends Execute and Discover requests to the endpoint itself. A catalog's cubes, measures, hierarchies and levels are
  listed from the schema rowsets (a click inserts the unique name); an answer of up to two axes is a grid (Axis0 the
  columns, Axis1 the rows, spanning headers), one of more axes a flat table (a column per hierarchy, highest axis first,
  a row per cell) (`scripts/console_ui_test.py`). Tabs next to the result show the SOAP response and request and,
  with "Trace SQL" on, the query plan and the SQL statements the Execute ran (rows, time, error, phase and element;
  as they ran or slowest first; copied or downloaded as one script or each statement alone, formatted by
  `web/schema/sql-format.js`): the console sends the header `X-olap4abap-Trace: true`, the endpoint traces the call
  whatever the user's trace and answers `X-olap4abap-Trace-Id`, and the console reads
  `GET trace/entry?id=...&response=false`. The query plan is the resolved tree (formulas, subselects, slicer, axes)
  with each element's type, its planner mark and the statements it and its arguments read, and the engine's phases
  (Resolve, Slicer, AxisN, Axes, NON EMPTY, Cells, Finish) with theirs, downloadable as text or JSON: while statements are logged the engine
  explains the query (`ZZXXMLA1_CL_MDX_EXPLAIN`, JSON kept with the trace's statements) and sets
  `ZZXXMLA1_CL_SQL=>log_phase` and `log_node` (the node `evaluate_set`, `evaluate_member`, ... evaluate: wrappers of
  the `*_node` methods), which every logged statement keeps. A batch of missed cells belongs to its phase, no node. Format (Shift+Alt+F, `web/schema/mdx-format.js`) lays out the
  statement or the selection: a line per clause and axis, bracket groups broken where they exceed 100 characters,
  keywords upper case, quoted formulas too; only white space and keyword case change.
- Time master data: `/zzxxmla1/schema/time.html` (`web/schema/time.js`) and `GET time`, `POST time/fill` of the schema
  API fill the SID and attribute tables of the calendar characteristics (`0CALYEAR`, `0CALQUARTER`, `0CALMONTH`,
  `0CALWEEK` and the ones without year) and of `0FISCYEAR` and `0FISCPER` (as `0CALYEAR` and
  `0CALMONTH`, for K4: its periods 001 to 012 are the months; BW's SID conversion adds 000 and the special periods of
  each year) for BW's interval of RSRHIERARCHYVIRT (`RSADMINS`) or a given one
  (`ZZXXMLA1_CL_TIME_MD`). BW fills neither: its Recreate button leaves them empty on the trial system. It also writes the text tables (`0CALMONTH`, `0CALQUARTER`, `0CALMONTH2`, `0CALQUART1`, `0WEEKDAY1`,
  `0FISCYEAR`) in English with the wording BW's queries show and BW does not store (`0CALMONTH`:
  `JAN 1997`, `January 1997`; the initial value `Not assigned`), and `GET time/missing` (the page's "Show missing")
  lists the values a characteristic misses a SID, attribute row or text for. Filling adds members to every time view;
  see `docs/time-master-data.md`.
- Trace: `/zzxxmla1/schema/trace.html` (`web/schema/trace.js`) switches the trace of XMLA calls on and off per SAP
  user (table `ZZXXMLA1_TRCUSR`) and lists the traced calls (table `ZZXXMLA1_TRACE`, `ZZXXMLA1_CL_TRACE`): per call
  the SOAP request, Discover with its rowset or Execute with its MDX statement, status, fault, runtime, the SQL
  statements it ran and their time (`ZZXXMLA1_CL_SQL`'s statistics), client address and User-Agent, the SOAP
  response gzipped (`cl_abap_gzip`) and the statements themselves with their rows, time and error (`statement_log`,
  gzipped XML, the first 10,000, each with its phase and element) and an Execute's query plan
  (`ZZXXMLA1_CL_MDX_EXPLAIN`, in the same XML); the call's tabs "Query plan" and "SQL statements" are the MDX
  console's views (`web/schema/query-plan.js`), whether the user's trace or the console's header traced the call.
  "Open in MDX Console" hands an Execute to the console (URL fragment `statement`, `catalog`, `trace`): its statement
  in the editor and the traced call as the result (the answer as sent, request, query plan, SQL statements), not run
  again. `ZZXXMLA1_MAIN_ENDPOINT` writes and commits the row
  before the handler runs (a call that dumps is traced without response) and adds the answer after it; a request with
  the header `X-olap4abap-Trace: true` (the MDX console's) is traced while the user's trace is off too. A trace is
  on for 2 hours after it is switched on (`c_active_hours`); switching one on deletes the calls older than 7 days
  (`c_retention_days`) and the expired users' rows. "Delete all" on the page deletes every traced call. The list is the newest calls, filtered on the server by user,
  by toggles Discover/Execute (`method`) and limited by "Show N newest" (`max`, 200 by default, at most 10,000). The user is sy-uname, the user of the call's basic authentication (the node has no logon data since 2026-10-24). API: `GET trace`,
  `trace/entry`, `trace/response`, `POST trace/on`, `trace/off`, `trace/clear` (`scripts/trace_test.py`).
- Discover cache: `ZZXXMLA1_CL_XMLA_HANDLER` answers a Discover request it answered before from table
  `ZZXXMLA1_DSCACHE` (`ZZXXMLA1_CL_DISCOVER_CACHE`, gzipped, valid 12 hours, keyed by `discover_key`: type, URL,
  restrictions, properties), without reading the schemas; only answers without fault are kept. Every write or delete
  of a server file (`ZZXXMLA1_CL_FILES`) and the time master data fill clear it; BW master data and fact loads do not
  yet (`docs/mvp-scope.md`, Discover cache decision).
- Execute: the MDX parser is a port of Mondrian's JavaCC grammar `MdxParser.jj` (`ZZXXMLA1_CL_MDX_TOKEN_MANAGER`,
  `ZZXXMLA1_CL_MDX_PARSER`, tree `ZZXXMLA1_CL_MDX_NODE`). It parses the whole grammar, with Mondrian's error texts, and its
  unit tests carry Mondrian's `ParserTest`. Keep it in step with `MdxParser.jj`: change the grammar there first, then port.
  The validator (`ZZXXMLA1_CL_MDX_VALIDATOR`, Mondrian's `Query.resolve`/`ValidatorImpl`) resolves identifiers
  through `ZZXXMLA1_CL_MDX_SCHEMA_READER` (`SchemaReader`), the query's aliases, named sets and calculated members
  before the cube (`Util.lookupCompound`: a query's name wins, and it costs no member read). It resolves functions by signature and conversion cost with
  `ZZXXMLA1_CL_MDX_FUNTABLE` (`BuiltinFunTable`, generated from the jar by `scripts/generate-funtable.py`) and types
  every node (`ZZXXMLA1_CL_MDX_TYPE`). The engine (`ZZXXMLA1_CL_MDX_ENGINE`, Mondrian's `RolapResult`) evaluates the
  resolved tree for SELECTs with measures and members of the model's hierarchies, in the evaluation context
  `ZZXXMLA1_CL_MDX_EVALUATOR` (`RolapEvaluator`: a current member per hierarchy, savepoint/restore, `evaluateCurrent`)
  (all 277 `reference/` cases pass; 394 of the 395 statements of `tests/mdx/applicable.json` give eMondrian's answer,
  #64 differs in the last digits of a sum eMondrian's database adds in another order).
  Hierarchies have levels: the schema's user hierarchies (Store, Product, Customers, Time, Weekly, Promotions) next to
  the attribute hierarchies; cells are grouped by the level columns down to a member's level. Members are never read
  as a whole hierarchy (a characteristic can have millions; `docs/mvp-scope.md`, Member decision): the schema reader
  reads them by SQL as needed (`SqlMemberSource` in `ZZXXMLA1_CL_MODEL=>read_members`: children of a member, a member
  by name, key or path, a parent, `Lag`/`Lead` and ranges along a level, children counts grouped) and keeps them for
  the request (`MemberCache`); a level is read whole only where the query asks for all of its members. A dimension annotated `olap4abap.membersWithFacts` on its
  `DimensionUsage` (our extension, not on time dimensions yet; `docs/mvp-scope.md`, Members with facts decision) has
  only the members whose key is in the cube's fact table (`ZZXXMLA1_CL_MODEL=>member_table`, every member read goes
  through it, except members read by paths that come from the facts, `get_members_by_paths`: the restriction is a
  semi-join over the whole fact table per query); tested on the clinic demo with `scripts/clinic_test.py`, FoodMart is not annotated. Cells are read
  as the reference reads them (`FastBatchingCellReader`, `CellRequest`): each phase (slicer, axes, named sets, cells) is
  evaluated with a batching reader that records the cells it misses (0 for the pass), they are read with one query per
  pattern of hierarchies and levels constrained to the keys asked for (`ZZXXMLA1_CL_MDX_FACTS=>load_aggregations`,
  a column of more than 1,000 keys not constrained, `MaxConstraints`), and the phase is evaluated again until it misses none (`RolapResult.phase`). Hierarchy
  order is a member's order key, its typed keys from the first level (`RolapMemberBase.compareTo`), numbers ordered
  as numbers where the column is a number in HANA's catalog. Time is a `TimeDimension` (level types `TimeYears`, ... on all its levels, `DIMENSION_TYPE` 1, the
  `LEVEL_TYPE` codes in the rowsets), so its hierarchy without All member is evaluated with its default member only;
  a hierarchy without All member of another dimension makes the slicer and the axes be evaluated once per root member
  and merged (`RolapResult.evalExecute`).
  Calculated members (`WITH MEMBER`) work: created and resolved by the
  validator, evaluated by the evaluator's calculations (scoped solve order) through `ZZXXMLA1_IF_MDX_CALC` (Mondrian's
  `Calc`, implemented by the engine; calculations see the evaluator as `ZZXXMLA1_IF_MDX_EVALUATOR`, `Evaluator`, and
  its schema reader as `ZZXXMLA1_IF_MDX_SCHEMA_READER`, `SchemaReader`; the compiled calculations of members made while
  the query runs are kept by the root evaluator, `RolapEvaluatorRoot`), with arithmetic, comparisons, logic, `IIf` (also of sets, members, tuples, levels and dimensions: typed by the
  common type of its branches, `TypeUtil.computeCommonType`, as Excel's filter lists need) and string functions. Format strings
  are a port of `mondrian.util.Format` (`ZZXXMLA1_CL_MDX_FORMAT`). `Order` (Mondrian's `Sorter`
  comparators), `Filter`, `TopCount`/`BottomCount`, `:`, `Descendants`, `IsEmpty`, `Cast`, `Aggregate`, the set algebra (`Union`, `Except`,
  `Intersect`, `Head`/`Tail`, `Distinct`, `Item`, `SetToStr`, `NonEmpty`) and the aggregates (`Count`, `Sum`, `Avg`, `Min`, `Max`,
  `Rank`), named sets (`WITH SET`, aliases `AS`, `Current`, `CurrentOrdinal`), `Generate` and the member
  functions (`Parent`, `Lag`, `Ancestor`, `ParallelPeriod`, `PeriodsToDate`, `UniqueName`, `OrderKey`, ..., with the
  null member `[Hierarchy].[#null]`), the operators `IN`, `MATCHES` (Mondrian's UDFs, in the funtable from
  `GlobalFunTable`; Java regular expressions translated to POSIX), `IS`, `IS NULL`, `IS EMPTY`, and `Existing`/`Exists`
  (`FunUtil.existsInTuple`) work, and slicers of
  several tuples (Mondrian's `CompoundSlicerRolapMember` placeholders, eMondrian patched for them, `docs/environment.md`); an evaluation error (`ZZXXMLA1_CX_MDX_EVALUATION`,
  `MondrianEvaluationException`) is the value of its cell only. Also `VisualTotals` (visual total members, found by
  their `calc_name`), `CurrentDateMember`, `Parameter` (its default), `DrilldownLevel`, `DrilldownMember`, `AddCalculatedMembers`,
  `CalculatedChild`, `LastNonEmpty`, `.Properties`, `Format` (also of dates), `Mod`, `CInt`, `CoalesceEmpty`, `CASE`,
  `OpeningPeriod`/`ClosingPeriod`, `Ytd`/`Qtd`/`Mtd`/`Wtd` and `Subset`. An infinite recursion of calculated members is
  found as `RolapEvaluator.checkRecursion` finds it (the evaluator's command stack has Mondrian's shape and widths), with
  Mondrian's context stack in the message.
  Members have a name and a caption, by the reference's rule (`RolapLevel.createFromXml`; test catalog `ZFMCAPT`,
  `reference/schema/FoodmartBWCaption.xml`): a `sourceAttribute` level is named by its own `nameColumn` (else the
  attribute's key) and captioned by the attribute's `NameColumn`, an attribute's hierarchy named by the key and
  captioned by its `NameColumn`, a `column` level captioned by its `captionColumn` (refused on a `sourceAttribute`
  level, which the reference ignores); the model reads the caption column with the members (`members_of_rows`),
  lookups, `.Name` and the unique names use the name, `.Caption`, `MEMBER_CAPTION` and the label conditions (subcube,
  native label filter) the caption; a measure's `caption` is its caption. The proposal writes the key attribute's
  `NameColumn` as the level's `nameColumn` too, so members are named by their BW key.
  Member properties of levels (the schema's `<Property>`, FoodMart's on Store Name and the customer Name level) are read
  with the members; they are listed in `MDSCHEMA_PROPERTIES` (PROPERTY_TYPE 1) and `DBSCHEMA_COLUMNS`, typed and
  evaluated by `.Properties`, written for `DIMENSION PROPERTIES [Store].[Store Name].[Store Sqft]` (olap4j's
  `MondrianOlap4jProperty`: its hierarchy only, `xsi:type`), and an identifier ending in a property is a property call
  (`Util.lookup` with allowProp).
  A crossjoin larger than the result limit (`ZZXXMLA1_CL_MDX_ENGINE=>result_limit`, 1,000,000 tuples, Mondrian's
  `mondrian.result.limit`) fails before it is built, so no query can use up the memory of the instance. While the
  evaluator is non-empty (NON EMPTY axes, `NonEmptyCrossJoin`) a crossjoin is native (`RolapNativeCrossJoin` with
  eMondrian's multi-variant expansion): its tuples are the combinations with facts in the context, read with one grouped
  query of `ZZXXMLA1_CL_MDX_FACTS=>non_empty_paths`, in hierarchy order; the variants of a split operand are put back
  in the order of the operands (our fix of eMondrian, `scripts/patches/multivariant-order.patch`). A NON EMPTY axis
  is eMondrian's `NonEmpty(<axis>, {the measures the query names})` (`Query.compile`): each axis is filtered on its
  own before the cells are evaluated, then empty positions are removed as before. Under a non-empty evaluator
  `Members`/`AllMembers` (a level of more than 300 members, `LevelPreCacheThreshold`), `Children` and `Descendants`
  read only the members with facts in the context (`SqlContextConstraint`, `context_members`): their paths from one
  grouped fact query, then the members of these paths, no level read first; `DrilldownLevel` and `DrilldownMember`
  too (the reference reads all children there). `TopCount`/`BottomCount` by a stored measure of a crossjoin (`CrossJoin`
  or `*`) of level members, `Children` or `Descendants` is native (`RolapNativeTopCount`, `native_top_count`,
  `ZZXXMLA1_CL_MDX_FACTS=>top_count`): the members' crossjoin left-joined to the grouped facts, ordered by the value
  and limited in HANA (`docs/next-steps.md`, step 9). `Order` with `BASC`/`BDESC` keys that are the `OrderKey` of a
  current member (or of its `Ancestor` at a level) or a stored measure (also through calculated measures that only
  name it) of a set the native crossjoin reads (also through named sets and an identity `Generate`) is native too, our
  extension (`native_order`, `ZZXXMLA1_CL_MDX_FACTS=>ordered_paths`), and `Head` of it is its `LIMIT`; any other
  `Order` sorts in ABAP, break keys evaluated once per tuple into a table and the indexes merge-sorted (step 8).
  `Filter` of such a crossjoin by a condition of stored measures (`AND`, `OR`, comparisons, `+`, `-`, `*`) that is
  false for every tuple without facts is native too (`RolapNativeFilter`, `native_filter`, the condition from
  `ZZXXMLA1_CL_MDX_PLANNER=>filter_condition` as a `WHERE` of `ordered_paths`). `Filter` of a level's members
  (`Members`, `Children`, `Descendants`, also in `AddCalculatedMembers` of a hierarchy without calculated members) by
  the labels of the current member (the subcube's label conditions: `=`, `<`, `>`, `Left`, `Right`, `InStr` of Name,
  Caption or Key with `AND`, `OR`, `NOT`; `CurrentMember` there is the filtered level, `InStr` ignores case as
  `Vba.inStr` does) is one read of the members with the condition as `WHERE`, our extension (`native_label_filter`,
  `ZZXXMLA1_CL_MDX_SCHEMA_READER=>get_level_members_where`, Excel's member search); not
  while the evaluator is non-empty. `Count` (`INCLUDEEMPTY`) and `.Count` of a member's `Children` (also in
  `AddCalculatedMembers` of a hierarchy without query calculated members) is a count query, not a read of the
  children, our extension (`children_count`, `get_children_count`; the first one in the cells counts the children of
  every member of the axes); not while the evaluator is
  non-empty. `NonEmpty` (also with a second
  set) is one grouped read (`non_empty_groups`), no evaluator call (query planning step 6). Execute
  answers carry the query's `DIMENSION PROPERTIES` (olap4j's standard member properties) and `CELL PROPERTIES`; when
  these show no cell's value (Excel's member lists ask for `CELL_ORDINAL` only), no axis is NON EMPTY and no member is
  calculated, the cells are not evaluated (`cells_needed`, our shortcut; the answer is the same). When no member of
  the context, the slicer or the axes is calculated or null, the cells are not evaluated one by one either
  (`fast_cells`, our shortcut, same answer): per combination of the axes' level patterns one grouped fact query
  (`ZZXXMLA1_CL_MDX_FACTS=>cross_values`), each group put at the positions of its tuples, every other cell empty
  (query planning step 3). A relational query whose NON EMPTY
  axes (at most two) are each a level's members with facts (`DrilldownLevel` of the All member, `Level.Members`, the
  All member's `Children`) is cells first (query planning step 4, `cells_first`, our shortcut, same answer): one
  grouped fact statement (`ZZXXMLA1_CL_MDX_FACTS=>grid`, `GROUPING SETS` for the All members) gives the axes (its
  keys, read as members and hierarchized) and the cells (`cell_values` and `cell_refs` of the result, each distinct
  cell written once). Excel's expanded members on a BW hierarchy (`Hierarchize` of nested
  `DrilldownMember` down to `DrilldownLevel` of the All member, NON EMPTY; on one or both axes, each axis such an
  outline, a level's members or a crossjoin of them, Excel's several fields on an axis, at most six; under a slicer
  of any dimensions, a compound slicer or a subselect) are cells first too (`outline_first`, our extension): the
  outlines are known from the MDX, and one statement (`ZZXXMLA1_CL_MDX_FACTS=>outline`: the facts grouped by the
  closure of each outline's members, a `UNION ALL` branch per combination of outlines at their All member) gives
  both axes' members, made from its columns without a member read, and the cells (`docs/query-planning.md`, Cells
  first of an outline; `scripts/outline_first_test.py`). A cube annotated `olap4abap.omitEmptyCells` (`true`, our
  extension, `docs/mvp-scope.md`, Empty cells decision) leaves its empty cells but the first out of the answer.
  Subselects (`FROM (SELECT ... FROM ...)`, Excel's pivot filters) are eMondrian's subcube: the axes of every inner
  SELECT become a predicate that every fact read adds (`Query.getSubcubePredicates`, `ZZXXMLA1_CL_MDX_FACTS=>set_subcube`),
  so totals cover only the subcube; member sets, `-`, `Head`, `CrossJoin`, `Union`, `Members` and `Filter` on the
  name, caption or key of the current member (`addFilterToSubcubePredicates`; also `member_caption`, Excel's "equals"
  label filter, our fix of eMondrian, `scripts/patches/subcube-filter-member-caption.patch`) are understood, and all of
  Excel's label filters: `<`, `<=`, `>`, `>=` (between, not between), `Left`/`Right(..., Len("s")) = "s"` (begins, ends
  with) and `InStr(1, ..., "s") > 0`/`= 0` (contains, ignoring case), as comparisons and `LIKE` on the level's column (our extension of
  eMondrian, `scripts/patches/subcube-filter-label.patch`, `ZZXXMLA1_CL_MDX_ENGINE=>label_predicate`), the level the
  `Filter` filters (`<Level>.AllMembers`, also an upper level; the reference compares the lowest); any other
  function or condition fails the query as in eMondrian. On a BW hierarchy a NON EMPTY axis also keeps only the
  members related to those a subselect names as a member set (them, their ancestors and descendants), as SSAS does
  where values are shared (`restrict_to_subcube`, `scripts/ssas_compare.py`).
  `DRILLTHROUGH` (Excel's double click on a cell, `MAXROWS`, `FIRSTROWSET`, `RETURN`) gives the fact rows of the
  query's first cell as a tabular rowset (`ZZXXMLA1_CL_MDX_ENGINE=>drill_through`, `RolapCell.drillThroughInternal`;
  `ZZXXMLA1_CL_MDX_FACTS=>drill_through`, `DrillThroughQuerySpec`; `ZZXXMLA1_CL_XMLA_TABULAR`, `TabularRowSet`): every
  level column of the cube's star (named by the first level that uses it, in hierarchy order) and the measure, the
  levels of the cell's members constrained, the subcube and a compound slicer applied, column types from HANA's catalog.
  Without `RETURN` the cube's default `DrillThroughAction` (`ZZXXMLA1_CL_SCHEMA=>drill_through_columns`,
  `RolapCube.getDefaultDrillThroughAction`) gives the columns and their names: levels, measures and columns of a
  dimension's table (`sourceAttribute`); test catalog `ZFMDRILL` (`reference/schema/FoodmartBWDrill.xml`). A
  dimension's table is joined only for a column other than the one its foreign key refers to; that one (the SID of an
  InfoCube, the value of an aDSO, cast to the view's type) is read from the fact table: BW has master data for every
  value of a fact, so the join removes no row.
  What the engine does not implement fails the query rather than giving a wrong number: a value of a measure whose
  aggregator is not `sum` or `count` (`ZZXXMLA1_CL_MODEL=>check_aggregator`, where the evaluator, the fast and
  cells-first cells and the native `TopCount`, `Filter` and `Order` read one), and any query of a cube with
  `CalculatedMember`s in the schema (`ty_cube-calculated_members`; the schema API's check and accept refuse them too).
  MDX data definition the grammar does not know (`CREATE SESSION CUBE`, which Excel sends to group members of a
  PivotTable, `CREATE SUBCUBE`, `ALTER CUBE`, `DROP CUBE`) is answered with a fault "... statements are not supported"
  before parsing (`ZZXXMLA1_CL_XMLA_HANDLER=>unsupported_statement`); the reference gives a syntax error there.
  See `docs/test-strategy.md`, section Execute (MDX) cases.
  Query planning (`docs/query-planning.md`, in progress): `ZZXXMLA1_CL_MDX_PLANNER` marks every node of a resolved
  query static, relational or computed and plans its axes, slicer and cells. The engine plans every query after
  `resolve_query`; when the plan is relational (switch `ZZXXMLA1_CL_MDX_ENGINE=>planning`) its NON EMPTY axes are
  filtered by their cells instead of `non_empty_axis`, and the cells of all combinations of patterns come from one
  `GROUP BY GROUPING SETS` statement (`ZZXXMLA1_CL_MDX_FACTS=>cross_values`), a compound slicer of disjoint tuples
  as an ORed predicate (`docs/next-steps.md`, query planning step 2). Step 3: the facts roll a pattern up from a
  finer segment read before (`roll_up`), so the axes' reads of members with facts feed the cells; a one-axis query's
  read also sums under the default members it leaves out (Time's 1997; the filter list is one fact statement); the
  NON EMPTY axes `axis_filter_needed` finds are filtered by groups of the cells' statement (the evaluator only for a
  calculated measure of the query); `python scripts/planning_measure.py` measures from the trace. The grouped
  statements join every dimension of their patterns: BW has master data for every fact.
- Schema definition (step 1 of moving the model to Mondrian schema XML, see `docs/mvp-scope.md`, schema decision):
  `ZZXXMLA1_CL_SCHEMA_DEF` reads any Mondrian schema as `MondrianDef` does and writes it back as `toXML` does,
  generated from Mondrian's `MondrianDef.java` (`docs/environment.md`, Mondrian's schema definition). The reference
  schema `reference/schema/FoodmartBW.xml` has no SQL: the fact table is the BW table, the dimension tables are the
  CDS views `ZZXXMLA1_CL_BW_VIEW_GEN` generates per characteristic (`docs/bw-to-schema-mapping.md`), in `$TMP` unless
  its caller names a package, so that they are not objects of the installed package; the eMondrian
  reference database holds copies of the BW tables and the same views (`docs/environment.md`, the reference database
  holds the BW tables).
- Setup: program `ZZXXMLA1_SETUP` (`ZZXXMLA1_CL_SETUP`) makes a system ready after the package is imported (the table
  `ZZXXMLA1_FILE` comes with it, `src/zzxxmla1_file.tabl.xml`, and so do `ZZXXMLA1_VIEW`, `ZZXXMLA1_TRACE`,
  `ZZXXMLA1_TRCUSR` and `ZZXXMLA1_DSCACHE`, which `pull` exports and sapcli's `push` does not import): it deletes
  the schema builder's old copies below `/schema/` and, if there is none, writes a
  `/WEB-INF/datasources.xml` without catalogs; with its checkbox also the clinic demo (`docs/clinic-demo.md`): InfoCube
  `ZCLVISIT` and aDSO `ZCLVISITA` with made-up visits of patients to a clinic (every characteristic with EN texts),
  their schemas and catalogs (`ZZXXMLA1_CL_BW_CLINIC_GEN`; the schema generator's proposals, accepted through the schema
  API; the InfoCube, the aDSO or both, as its checkboxes ask: a run deletes all of the demo either way); its room `ZCLROOM` is compounded with the site `ZCLSITE`, its fiscal year and period with the
  variant `ZCLFISCVR`. 300 of its patients are registered without a visit, and its schemas annotate every
  dimension `olap4abap.membersWithFacts` (the proposal marks none as time). The clinic demo is the
  project's own demo data; FoodMart stays the test source.
  For looking into BW's analysis authorizations its physician `ZCLDOC` is authorization relevant and has two
  hierarchies, `ZCLDOC_ORG` and `ZCLDOC_SITE` (two names are needed for authorization tests): version dependent,
  entire hierarchy time dependent, two versions of two time slices each (served per version, the slice valid to
  9999-12-31: `ZCLDOC_ORG_001`, `_002`, `ZCLDOC_SITE_001`, `_002`, ticked by the setup); the diagnosis `ZCLDIAG` is authorization
  relevant with the plain hierarchy `ZCLDIAG_ICD`, for authorizations that combine the two characteristics. With a
  further checkbox (and a password field) the analysis authorization scenarios (`ZZXXMLA1_CL_BW_AUTH_GEN`,
  `docs/clinic-demo.md`, Authorization scenarios): 21 analysis authorizations `ZCLA_*` written with BW's
  `RSEC_*_API`, each assigned directly to its service user `ZZXXMLA1_A01` ... `A21` (profile `ZZXXMLA1_REP`;
  without password a generated one, no logon), deleted by every clinic run. BW keeps authorization values in
  `RSECVAL_STRING` and `RSECHIE_STRING`, not `RSECVAL`/`RSECHIE`. The
  patient `ZCLPAT` has the plain hierarchy `ZCLPAT_PRG` (care programs) with link nodes (subtrees under two parents,
  recursively), duplicate and link leaves (patients in two programs) and postable nodes (parents with their
  children in family care), the test case of shared nodes (`docs/clinic-demo.md`).
  The service `ZCLSERV` (52 services, a dimension of both providers) has the plain hierarchy `ZCLSERV_CAT` of
  intervals of codes: overlapping ones, a linked text node with its interval and a linked interval.
  With another checkbox the wide demo (`docs/wide-demo.md`, `ZZXXMLA1_CL_BW_WIDE_GEN`): InfoCube
  `ZXMLWIDE` and aDSO `ZXMLWIDEA` with 100 characteristics `ZXMLAD00`-`ZXMLAD99` of 1,000 members each (`ZXMLAD00`
  100,000), one key figure
  and 1,000,000 made-up records (another number on request), without schema or catalog; the reference has no copy of it.
- BW hierarchies (in progress, waiting for the texts, `docs/next-steps.md`, Then: time-independent BW hierarchies; analysis authorisations are the active work, Now: analysis authorisations, then the texts and captions, Now: texts and captions): part one, the copies, is
  done. `ZZXXMLA1_CL_BW_HIERARCHY_COPY` keeps per InfoObject a node table and a closure table (generated DDIC tables
  in `$TMP`, `ZZXXMLA1H`/`ZZXXMLA1C` and 7 digits, registered in `ZZXXMLA1_HIETAB`, made by `create_tables`) holding
  all its hierarchies, keyed by BW's `HIESID` and `SVER` (directory `ZZXXMLA1_HIEDIR`, a row per copy): the
  occurrences of `/BIC/I` with BW's node SIDs, depth-first numbers and subtree ends, and per inner node the distinct
  SIDs below it plus an identity row per leaf, so every member is an ancestor. A view per InfoObject (`ZZXXMLA1R`, the
  same digits, a CDS view) adds the not-assigned values live for the copies whose hierarchy shows them
  (`RSHIEDIR-NORESTNODES`): REST_H, the All member and the identity row per SID under no leaf; a query reads the view
  for such a hierarchy, else the table (`ty_hierarchy-closure`). `current` looks for a copy of BW's current row of
  `RSRHIEDIR_OLAP` (`HIESID`, `SVER`, `TIMESTMP`) and refills a missing one in the database under `ENQUEUE_E_TABLE`,
  cross-checked with BW's correction factors; a copy lives as long as BW keeps its version. The refill keeps the
  copy's shape in its directory row (`DEPTH`, the levels where a SID repeats `REPEATED`, the external InfoObjects
  `NODE_IOBJS`; a row without it is refilled once), so building a schema reads no copy table. The refusals are faults
  of the query (`ZZXXMLA1_CX_BW_HIERARCHY`). `values_of` gives a member's SIDs as a statement with bound parameters
  (`ZZXXMLA1_CL_SQL`'s `params`) (`scripts/hierarchy_copy_test.py`). Program `ZZXXMLA1_HIERARCHY_COPY` (SE38)
  creates the objects (node, closure and path table, not-assigned view) of the characteristics selected and copies their hierarchies (`run`), listing per hierarchy the
  copy or its refusal and its counts. The schema names a BW hierarchy by a `<Hierarchy>` annotated
  `olap4abap.bwHierarchy` (its name, `RSHIEDIR-HIENM`, of the characteristic of the dimension's view,
  `ZZXXMLA1_CL_BW_VIEW_GEN=>characteristic_of_view`) without levels: `ZZXXMLA1_CL_SCHEMA` reads the copy's `current`
  and makes `Level 01` to `Level nn` from its `depth`, the model carries the copy (`bw_hierarchy`) and counts a
  level's members in it (`level_cardinality`), so `MDSCHEMA_HIERARCHIES` and `MDSCHEMA_LEVELS` show it. Its members
  are read from the copy as from a level hierarchy (step 7.2): `member_table` is the derived table
  `ZZXXMLA1_CL_BW_HIERARCHY_COPY=>levels_sql` over the copy's path table (`ZZXXMLA1P`, a row per occurrence and level
  of its path, filled by the refill; the joins the same whatever the depth, the member's own `MEMBER_SID`,
  `MEMBER_DEPTH` and `MEMBER_PARENT` columns reach the table, `docs/next-steps.md` step 9), a row per member
  occurrence (node or leaf) with per level of its path
  `Lnn_SID` (the key), `Lnn_NAME` (a node's `NODE_NAME`, a leaf named as the characteristic's member: the view's
  column the level over the key attribute names it by, SID 0 too, `''` by `KEY_NAME`), `Lnn_POS` (the ordinal, BW's
  order) and, where the key attribute's `NameColumn` captions the members, `Lnn_CAPTION` (a text node's text of BW's
  `RSTHIERNODE` in English, medium, else long, else short, else its name, read live; a postable node's and a leaf's
  caption from the view; REST_H `Not Assigned <characteristic's text> (s)` as BW's MDX; `node_rows_sql`,
  `rest_caption`), the levels below it NULL (a level read asks for its column not NULL); REST_H
  follows the roots with its values below it when shown; a level's `uniqueMembers` is false where a SID repeats
  (`repeated_levels`). A member's unique name is the key of its path as SSAS names it, `Lnn_IOBJ` (a node's
  `NODE_IOBJ`, REST_H's `1HIER_REST`, a leaf's the characteristic) and `Lnn_NAME` per level:
  `[ZCLSERV.ZCLSERV_LOC].[Level 02].&[0HIER_NODE]&[LOCATIONS]&[ZCLSITE]&[NORTH]`, so siblings of one name and
  different InfoObjects differ (decided 2026-10-17, checked on SSAS; `docs/next-steps.md`, Multiple parents); the
  schema reader finds it by that key with or without the level (`lookup_bw_member_by_key`), a path of names finds the
  first member of each name, also in `MDSCHEMA_MEMBERS` (`bw_member_names`); `xmla_test.py` and `ssas_compare.py`
  compare it as the path of names (`scripts/bw_names.py`). The facts are read through the closure (step 7.3): a fact read joins, per BW hierarchy, the
  members of the level it groups or filters by with the SIDs below each (`ZZXXMLA1_CL_MODEL=>fact_join_table` with
  the level: `levels_sql`'s rows of that level joined to the closure, the SID as the key column), so a member's value
  is the sum over its distinct values; a set in the subcube, a compound slicer or a drill-through is a semi-join on
  the closure (`bw_member_condition`, `bw_members_condition` for label conditions). On a dimension keyed by the value
  (an aDSO's, whose facts hold it) these joins map the closure's SID to the value on the characteristic's view
  (`bw_fact_value`: the view joined on `SID`, its key column the one the facts refer to). Never a parent from its children:
  no `roll_up` across a BW hierarchy's levels, no grouping set of other levels of it in one statement (`bw_pattern`),
  no defaults of it, no cells-first grid on it (Excel's outline of it is cells first: `outline_first`). Its levels are no drill-through columns (a `RETURN` of one is a
  fault). The schema API's check and accept create the copy tables of an InfoObject one of whose hierarchies the
  schema names (`create_hierarchy_tables`). The clinic setup ticks every one BW serves (`tick_hierarchies`:
  `ZCLDIAG_ICD`, `ZCLPAT_PRG`, `ZCLSERV_CAT` on `ZCLVISIT` and `ZCLVISITA`; `bw_hierarchy_test.py --catalog ZCLVISITA
  --names` passes).
  The reference serves `ZCLDIAG_ICD` as a balanced level hierarchy (`Level 01`-`Level 04` on the flattened table
  `ZZXXMLA1_HL_ZCLDIAG_ICD`; catalog and cube `ZCLHIER`, `reference/schema/ClinicBW.xml`, built by
  `build-bw-reference-db.py` from an export of the InfoCube and the copy, checked against BW by
  `bw_hierarchy_test.py --reference`). The reference cannot model REST_H, so `ZCLDIAG_ICD` assigns every value (the
  initial one as leaf `#` under `NOT_RECORDED` > `NO_DIAGNOSIS`) and suppresses the not-assigned node (decided
  2026-10-16). Its 71 cases (`execute_hier_*`, `members_hier_*`, `mdschema_*_hier`; the Excel ones from a live
  session against it) are what the engine work has to pass, on the test catalog `ZCLHIER` of SAP, which the clinic
  generator deploys with the InfoCube (`ZZXXMLA1_CL_BW_CLINIC_GEN=>test_schema`; the generator builds everything the
  SAP side tests need, as its provider checkboxes ask): `ZCLVISIT`'s schema with its BW hierarchies (olap4abap's form,
  annotation `olap4abap.bwHierarchy`, no levels), catalog and cube named `ZCLHIER`, without `membersWithFacts` and
  `omitEmptyCells`, so it is `ClinicBW.xml` but for the hierarchies' form; `ZCLPAT_PRG`, `ZCLSERV_CAT` and
  `ZCLSERV_LOC` no case names (`bw_hierarchy_test.py --catalog ZCLHIER --names` checks all four against BW's MDX)
  (`docs/next-steps.md`, Reference scenario); the demo's own catalogs `ZCLVISIT` and `ZCLVISITA` have the four
  hierarchies as the setup ticks them (`bw_hierarchy_test.py --catalog ZCLVISIT --names` passes). `ZCLSERV_LOC`
  (Service Locations) has nodes of the external characteristics `ZCLSITE` and `ZCLROOM` (compounded): olap4abap names
  them and captions them as the characteristic's members (`NORTH/R01`, Consultation Room 1; BW captions them by the
  short text, its text properties give the medium one; the site `NORTH` has a text node `NORTH` as sibling), from its
  view on the SID BW gives the node (`VALUE_SID`, `/BIC/K-OSID`; `ZZXXMLA1_CL_BW_HIERARCHY_COPY=>externals`)
  (`docs/clinic-demo.md`). Decided 2026-10-16 after Excel failed on the parent-child form: the
  reference is the oracle for everything but parent-child hierarchies and is not patched any more: its patches stay
  as they are, an answer it gets wrong (Expand Entire Field, Top 10 value filter, a label filter on an upper level)
  waits for SSAS (2016, the version olap4abap reports), the spec for hierarchies and Excel's behaviour; olap4abap puts each member of a BW hierarchy on the level of its depth, as SSAS does (Excel
  needs it); BW's MDX is the oracle for hierarchies without a level form.
- Reference: eMondrian built from source and running in Docker; captured exchanges are in `reference/`.

## Syncing ABAP code with git

`src/` (abapGit file format) mirrors package `$ZZXXMLA1`; only this local repo writes to the git remote, SAP is where
the code runs. `scripts/sap-sync.sh pull` exports SAP -> `src/` with vsp (`vsp export`: abapGit's serializer on the
system, so `src/` is what abapGit writes; then review and commit), `scripts/sap-sync.sh push` imports `src/` -> SAP
with sapcli (creates the package if missing, activates). Changed classes go to SAP with
`scripts/sap-write.py <class>...` (also interfaces and programs) run in sapcli's Python (one session per class, closed afterwards; the older
`sap-write.ps1`/`sap-write.sh` leave a session per include open in SM04): one class at a time, no retry loops
(`docs/environment.md`, work processes in PRIV mode). Logon data goes in the git-ignored `.env.sap`
(template `.env.sap.example`). Details and gaps (ICF service not covered) in `docs/environment.md`.
After changing ABAP in SAP, run `pull` before committing so `src/` is current.

## Working agreements

- Do not commit credentials: `.mcp.json` is git-ignored.
- SAP's license (`docs/environment.md`, SAP license): no timings of the SAP system or comparisons involving it in
  commits, docs, issues or PRs (measurements go in the git-ignored `.local/`); tracked files name SAP's tables and
  documented interfaces and say what we observed, never how SAP's code works inside (unless a public source shows it,
  cited); do not read SAP's standard source unless the user asks for a named question, and copy none of it.
  `scripts/license-scan.py` checks this and the naming rule on every commit (`git config core.hooksPath .githooks`).
- BW analysis authorisations are in scope since 2026-10-22, as the probe `ZZXXMLA1_BW_AUTH_PROBE` defines them: flat
  and hierarchy values, hierarchies matched by name and version (node by name and node type, never `HIEID`), a node's
  values from the slice valid at the key date (queries use 9999-12-31, the tests compare the check with the probe at
  several key dates), variables not supported (a user with one is not authorised: a fault of the query), for the user `sy-uname` (identity is the
  SICF node's, not olap4abap's; read with `RSEC_GET_USERNAME`) (`docs/mvp-scope.md`, Authorisation decision, with
  BW's rules: flat sets refused, values outside unknown, `:` for aggregates, hierarchies restricted to the user's
  subtree, AND within and OR over authorisations). The scenarios and test users exist, and BW's answers per test
  user and key date are recorded in `reference/auth/` (`python scripts/auth_probe.py [--verify 1]`; the probe,
  `GET auth/probe?user=...`, runs as BW's "Execute as Other User", `RSEC_SET_USERNAME`, verified against a logon of
  the user through BW's XMLA service) (`docs/next-steps.md`, steps 1 and 2). The region of a user and the check of a
  selection exist (`ZZXXMLA1_CL_BW_AUTH`, step 3) and agree with the oracle at every key date (step 4:
  `python scripts/auth_check_test.py`, `GET auth/check?user=...&keyDate=...`, `ZZXXMLA1_CL_BW_AUTH_QUERIES` asks the
  probe's queries as selections; a line's flat values from the slice of its date, a type 3 line the complete
  hierarchy). The same check in HANA (`ZZXXMLA1_CL_BW_AUTH_SQL`, step 5's engine: the profile per node, each
  hierarchy line expanded on the path table of the copy of its slice at the key date and at its own date, one
  statement per query, a crossjoin as its factors) agrees with the oracle at every key date too
  (`auth_check_test.py --engine sql`, `GET auth/check?...&engine=sql`); nothing is enforced yet (step 5a, 5b). For it
  the copies hold any slice (`current` with a key date; a slice's copy is deleted once BW has the slice no more) and
  name a leaf by the characteristic and its key (`NODE_IOBJ`, `NODE_NAME`; copies filled before
  `c_layout_since` are refilled once).
- Third-party reference code (`mondrian/`, `eMondrian/`) is fetched by `scripts/setup-reference.sh`, not committed.
