# CLAUDE.md

Project context for Claude Code. This repository is the single source of truth for the project: code, decisions and
procedures live here, not in any per-machine memory.

## Goal

**olap4abap** (https://github.com/arcanist123/olap4abap, Eclipse Public License 2.0): build an XMLA endpoint with its
own MDX engine ("Mondrian in ABAP") that runs on an SAP system and serves cubes defined
on top of SAP BW data. The reference implementation is eMondrian (a Mondrian fork), run locally in Docker. SAP BW's
native MDX/XMLA engine is deliberately NOT used: it supports little of modern MDX and its lexer cannot parse some of it.

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
  exception or a type a class needs is a global object of its own. `scripts/sap-sync.sh pull` refuses a local include
  with code.
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
  `ZZXXMLA1_CL_SCHEMA_API`, the rest of `/schema/...` to `ZZXXMLA1_CL_WEB_APP` (the schema builder's files); otherwise GET returns an HTML description page, POST hands the SOAP body to `ZZXXMLA1_CL_XMLA_HANDLER` (string in, string out; so far only
  DISCOVER_DATASOURCES, anything else is a SOAP fault), other methods 405.
- XMLA tests: `python scripts/xmla_test.py` replays `reference/<case>/` against SAP (see `docs/test-strategy.md`);
  `python scripts/compare-applicable.py` runs Mondrian's test statements on eMondrian and SAP and groups the gaps.
- The model is the catalogs' Mondrian schemas, configured as in Mondrian: the server has files (table `ZZXXMLA1_FILE`,
  `ZZXXMLA1_CL_FILES`), `/WEB-INF/datasources.xml` (`reference/schema/datasources-sap.xml`) lists the data sources and
  their catalogs, read by `ZZXXMLA1_CL_REPOSITORY` (Mondrian's `FileRepository`/`DataSourcesConfig`), and each catalog's
  `<Definition>` is the path of its schema file (`/WEB-INF/schema/FoodmartBW.xml`). A schema or catalog is added with
  `scripts/sap-files.py`, no new ABAP object (`docs/environment.md`, Catalogs).
  `ZZXXMLA1_CL_SCHEMA` (part of Mondrian's `RolapSchema`) reads them and gives the engine and the rowsets their cubes,
  dimensions, hierarchies, levels and measures; data is read with native SQL through ADBC (`ZZXXMLA1_CL_SQL`). The old
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
  supported); a time dimension only if the user marks one. The UI (`web/schema/`, Preact with htm, no build step) is served from
  files of the server below `/schema/` by `ZZXXMLA1_CL_WEB_APP`; the files are in the generated class
  `ZZXXMLA1_CL_WEB_APP_FILES` (`scripts/generate-web-app-abap.py`, run after every change of `web/schema/`) and
  written by the setup (below); it
  edits the schema XML as a DOM (rename, remove, time dimensions, user hierarchies with levels and member properties,
  measures, raw XML), lets the server `check` every change and accepts (`scripts/schema_ui_test.py`).
- Execute: the MDX parser is a port of Mondrian's JavaCC grammar `MdxParser.jj` (`ZZXXMLA1_CL_MDX_TOKEN_MANAGER`,
  `ZZXXMLA1_CL_MDX_PARSER`, tree `ZZXXMLA1_CL_MDX_NODE`). It parses the whole grammar, with Mondrian's error texts, and its
  unit tests carry Mondrian's `ParserTest`. Keep it in step with `MdxParser.jj`: change the grammar there first, then port.
  The validator (`ZZXXMLA1_CL_MDX_VALIDATOR`, Mondrian's `Query.resolve`/`ValidatorImpl`) resolves identifiers
  through `ZZXXMLA1_CL_MDX_SCHEMA_READER` (`SchemaReader`). It resolves functions by signature and conversion cost with
  `ZZXXMLA1_CL_MDX_FUNTABLE` (`BuiltinFunTable`, generated from the jar by `scripts/generate-funtable.py`) and types
  every node (`ZZXXMLA1_CL_MDX_TYPE`). The engine (`ZZXXMLA1_CL_MDX_ENGINE`, Mondrian's `RolapResult`) evaluates the
  resolved tree for SELECTs with measures and members of the model's hierarchies, in the evaluation context
  `ZZXXMLA1_CL_MDX_EVALUATOR` (`RolapEvaluator`: a current member per hierarchy, savepoint/restore, `evaluateCurrent`)
  (all 244 `reference/` cases pass; 394 of the 395 statements of `tests/mdx/applicable.json` give eMondrian's answer,
  #64 differs in the last digits of a sum eMondrian's database adds in another order).
  Hierarchies have levels: the schema's user hierarchies (Store, Product, Customers, Time, Weekly, Promotions) next to
  the attribute hierarchies; members are read as a tree, cells are grouped by the level columns down to a member's
  level. Time is a `TimeDimension` (level types `TimeYears`, ... on all its levels, `DIMENSION_TYPE` 1, the
  `LEVEL_TYPE` codes in the rowsets), so its hierarchy without All member is evaluated with its default member only;
  a hierarchy without All member of another dimension makes the slicer and the axes be evaluated once per root member
  and merged (`RolapResult.evalExecute`).
  Calculated members (`WITH MEMBER`) work: created and resolved by the
  validator, evaluated by the evaluator's calculations (scoped solve order) through `ZZXXMLA1_IF_MDX_CALC` (Mondrian's
  `Calc`, implemented by the engine; calculations see the evaluator as `ZZXXMLA1_IF_MDX_EVALUATOR`, `Evaluator`, and
  its schema reader as `ZZXXMLA1_IF_MDX_SCHEMA_READER`, `SchemaReader`; the compiled calculations of members made while
  the query runs are kept by the root evaluator, `RolapEvaluatorRoot`), with arithmetic, comparisons, logic, `IIf` and string functions. Format strings
  are a port of `mondrian.util.Format` (`ZZXXMLA1_CL_MDX_FORMAT`). `Order` (Mondrian's `Sorter`
  comparators), `Filter`, `TopCount`/`BottomCount`, `:`, `Descendants`, `IsEmpty`, `Cast`, `Aggregate`, the set algebra (`Union`, `Except`,
  `Intersect`, `Head`/`Tail`, `Distinct`, `Item`, `SetToStr`) and the aggregates (`Count`, `Sum`, `Avg`, `Min`, `Max`,
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
  in the order of the operands (our fix of eMondrian, `scripts/patches/multivariant-order.patch`). Execute
  answers carry the query's `DIMENSION PROPERTIES` (olap4j's standard member properties) and `CELL PROPERTIES`.
  Subselects (`FROM (SELECT ... FROM ...)`, Excel's pivot filters) are eMondrian's subcube: the axes of every inner
  SELECT become a predicate that every fact read adds (`Query.getSubcubePredicates`, `ZZXXMLA1_CL_MDX_FACTS=>set_subcube`),
  so totals cover only the subcube; member sets, `-`, `Head`, `CrossJoin`, `Union` and `Members` are understood, `Filter`
  not yet, any other function fails the query as in eMondrian.
  See `docs/test-strategy.md`, section Execute (MDX) cases.
- Schema definition (step 1 of moving the model to Mondrian schema XML, see `docs/mvp-scope.md`, schema decision):
  `ZZXXMLA1_CL_SCHEMA_DEF` reads any Mondrian schema as `MondrianDef` does and writes it back as `toXML` does,
  generated from Mondrian's `MondrianDef.java` (`docs/environment.md`, Mondrian's schema definition). The reference
  schema `reference/schema/FoodmartBW.xml` has no SQL: the fact table is the BW table, the dimension tables are the
  CDS views `ZZXXMLA1_CL_BW_VIEW_GEN` generates per characteristic (`docs/bw-to-schema-mapping.md`); the eMondrian
  reference database holds copies of the BW tables and the same views (`docs/environment.md`, the reference database
  holds the BW tables).
- Setup: program `ZZXXMLA1_SETUP` (`ZZXXMLA1_CL_SETUP`) makes a system ready after the package is imported: the table
  `ZZXXMLA1_FILE` (`ZZXXMLA1_CL_CREATE_TABLES`), the schema builder's files and, if there is none, a
  `/WEB-INF/datasources.xml` without catalogs; with its checkbox also the clinic demo (`docs/clinic-demo.md`): InfoCube
  `ZCLVISIT` and aDSO `ZCLVISITA` with made-up visits of patients to a clinic, their schemas and catalogs
  (`ZZXXMLA1_CL_BW_CLINIC_GEN`). The clinic demo is the project's own demo data; FoodMart stays the test source.
- Reference: eMondrian built from source and running in Docker; captured exchanges are in `reference/`.

## Syncing ABAP code with git

`src/` (abapGit file format) mirrors package `$ZZXXMLA1`; only this local repo writes to the git remote, SAP is where
the code runs. `scripts/sap-sync.sh pull` exports SAP -> `src/` (then review and commit), `scripts/sap-sync.sh push`
imports `src/` -> SAP (creates the package if missing, activates). Changed classes go to SAP with
`scripts/sap-write.py <class>...` run in sapcli's Python (one session per class, closed afterwards; the older
`sap-write.ps1`/`sap-write.sh` leave a session per include open in SM04): one class at a time, no retry loops
(`docs/environment.md`, work processes in PRIV mode). Logon data goes in the git-ignored `.env.sap`
(template `.env.sap.example`). Details and gaps (ICF service not covered) in `docs/environment.md`.
After changing ABAP in SAP, run `pull` before committing so `src/` is current.

## Working agreements

- Do not commit credentials: `.mcp.json` is git-ignored; `.mcp.json.example` shows its shape.
- Authorisations (BW analysis authorisations) are out of scope - do not plan or propose them.
- Third-party reference code (`mondrian/`, `eMondrian/`) is fetched by `scripts/setup-reference.sh`, not committed.
