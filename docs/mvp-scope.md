# MVP scope and decisions

Decisions taken by the project owner on 2026-10-02, with reasons.

## Architecture decision

- **Own MDX/XMLA engine in ABAP; SAP BW's native engine is not used.** The BW engine supports little of modern MDX
  and its lexer does not even parse some modern MDX, so patching in functions would not be enough. The ICF service
  `/sap/bw/xml/soap/xmla` exists on the system (answers 401) but is ruled out.
- BW is used as the **data source** (HANA-optimised InfoCubes, and aDSOs), not as the OLAP engine.

## Reference data

- **The FoodMart Sales cube `ZFMSALES` in BW is the main data source** (decision 2026-10-03). It is the target of the
  engine's tests and the first cube the model generator must handle; the demo cube `0D_NW_C01` is not a target. Details
  in `environment.md`.

## Target release (2026-10-04)

- **The ABAP code must run on SAP NetWeaver 7.50** (and later releases). The development system is ABAP Platform 2025,
  so activation there proves nothing about 7.50: `scripts/abaplint.sh` checks `src/` against the 7.50 syntax
  (`abaplint.json`). Not available in 7.50, for example: `RAISE EXCEPTION NEW` (7.52), `&&=` (7.54), `PCRE` (7.55),
  CDS view entities (`define view entity`, 7.55) and XCO; CDS views are DDIC-based (`define view` with
  `@AbapCatalog.sqlViewName`, at most 16 characters).

## Schema decision (2026-10-04)

- **The cube model is a Mondrian schema XML document**, stored as is and parsed by the engine into typed structures
  generated from Mondrian's meta-model `mondrian/mondrian/src/main/java/mondrian/olap/Mondrian.xml` (89 elements, 221
  attributes, including eMondrian's `DimensionAttribute`; `mondrian.xsd` is out of date and is not the reference). This
  replaces the model tables `ZZXXMLA1_CUBE/_DIM/_HIER/_LEVEL/_MEAS`. Parsing performance is dealt with only once it is
  shown to be a problem (then: cache the parsed schema). Stored, since 2026-10-05, as Mondrian stores it: a **file** of
  the server, named by a catalog of the data sources file `/WEB-INF/datasources.xml` (rows of table `ZZXXMLA1_FILE`,
  `docs/environment.md`, Catalogs), so a schema or a catalog is added without a new ABAP object. Until then a catalog
  was a generated class; the reason against a table, that the anonymous endpoint cannot take uploads, holds still:
  the files are written by `scripts/sap-files.py` as a logged-on developer, never through the endpoint.
- Everything the meta-model allows is parsed; what the engine does not support is rejected when the schema loads, with
  an error, never silently ignored.
- **Comparable layouts only:** a schema is in scope if its tables have a layout a BW star schema can provide (fact
  table with SID foreign keys, SID/attribute tables of characteristics). The test is: the same schema in eMondrian
  (FoodMart tables) and in SAP (BW tables) gives the same answers on the same data.
- **No generation of BW objects from arbitrary schemas.** The use case is exposing an existing BW star schema within
  what Mondrian can express (so no key date / time-dependent attributes).
- **SQL dialect `hana`:** `<SQL>` in `<View>`/`<Table>` is chosen as Mondrian's `SqlQuery.CodeSet.chooseQuery` does, with
  `hana` as the engine's dialect and `generic` as the fallback. Mondrian has no HANA dialect, so eMondrian takes the
  `generic` (or `hsqldb`) variant of the same schema.
- **One schema, the same table names in both systems; no binding layer, no SQL in the schema.** The fact table is the
  BW table itself (`/BIC/F<cube>`); a dimension's table is a **generated CDS view per characteristic** (SID table
  joined with the active attributes; `ZZXXMLA1_CL_BW_VIEW_GEN`, see `bw-to-schema-mapping.md`). The views are
  DDIC-based CDS views (7.50 has no view entities); DDL source `ZZXXMLA1_C_<characteristic>`, database view
  `ZZXXMLA1V` + 7 digits, the name the schema uses (decided 2026-10-04: always a number, 16 characters do not fit the
  prefix and a characteristic). **All NUMC columns are delivered as numbers** (decided 2026-10-04), so members read
  `1997`, not `000...1997`. The eMondrian reference database holds copies of the BW tables and the same views, with
  HANA's view SQL (HSQLDB 2.3.2 accepts it and `/` in quoted names; checked 2026-10-04), so the data is identical.
- **The engine reads data with native HANA SQL through ADBC** (Mondrian's `SqlQuery` with a dialect), not with
  ABAP SQL: `<SQL>` variants are raw SQL embedded in the statement. Compile-time checks of table and column names are
  given up; correctness comes from integration tests that run the same way against SAP and eMondrian.

## Catalog decision (2026-10-06, may be revisited)

- Mondrian's levels are **data source → catalog → schema → cube**: `/WEB-INF/datasources.xml` lists data sources, each
  with catalogs; a catalog's `<Definition>` is one schema file (catalog and schema are 1:1, XMLA still shows both as
  `CATALOG_NAME` and `SCHEMA_NAME`), and the schema defines the cubes. A cube object belongs to exactly one catalog, but
  Mondrian lets the same cube name (or the same schema file) appear in several catalogs as independent cubes.
- **For the MVP each cube is served from its own catalog**: the schema generator proposes one schema with one cube
  per provider, accepted as one catalog. A server is hardly going to have more than one or a few cubes, so several
  cubes per catalog and moving a cube between catalogs are not supported in the UI (the XML tab can still put more
  cubes into one schema). A cube "moves" by removing its catalog and accepting the schema again under another name.
- Stricter than Mondrian: cube names are unique across all catalogs of the server (`ZZXXMLA1_CL_SCHEMA`,
  "Cube '...' is defined twice"), so two catalogs cannot have a cube of the same name, nor name the same schema file.
- Catalogs can be removed (`schema-generator.md`, Removing).
- **Revisit** when a server needs several cubes in one catalog or the same cube name in two catalogs: then cubes are
  keyed by catalog and name in `ZZXXMLA1_CL_SCHEMA` and everything that looks a cube up by its name only, and the UI
  gets "add to catalog X" next to a new catalog for a proposal.

## Session decision (2026-10-05, may be revisited)

- **XMLA sessions are stateless**: the server stores nothing per session. `BeginSession` gets a new id (a GUID),
  `Session` and `EndSession` get the client's id back unchecked, and an Execute without statement (Excel opens its
  session so) gets an empty answer. Reason: the server only reads, and what Mondrian keeps per session is credentials
  (out of scope) and session-scoped `CREATE MEMBER`/`CREATE SET`, which Excel does not need (its calculated measures
  and named sets arrive as `WITH` in each query). Clients only need the protocol: the `Session` header in the answer.
- Differences from Mondrian that follow: an id the server never gave or one already ended is accepted (Mondrian
  faults: "Session with id ... does not exist"); there is no idle timeout; `DISCOVER_SESSIONS` lists nothing.
- **Revisit** when a client needs state across requests: `CREATE MEMBER`/`CREATE SET`/`DROP` (session calculations,
  `mondrian.xmla.XmlaHandler` `CalculatedFormula`), per-session properties such as a catalog or locale chosen once, or
  a reason to cache per session (members, results). Then: a session store keyed by the id (a table or shared memory,
  since every HTTP request may reach another work process), with Mondrian's checks and an idle timeout
  (`mondrian.server.Session`, `IdleOrphanSessionTimeout`). The code to change is
  `ZZXXMLA1_CL_XMLA_REQUEST=>CHECK_HEADER` and `ZZXXMLA1_CL_XMLA_HANDLER->WITH_SESSION`.

## In scope (MVP)

- Cubes over HANA-optimised InfoCubes / aDSOs (see `bw-to-schema-mapping.md`).
- **Only SUM key figures**: `RSDKYF` standard aggregation (`AGGRGEN`) = SUM, exception aggregation (`AGGREXC`) = SUM,
  and not non-cumulative (`NCUMFL` initial). On the dev system this is 135 of 181 key figures; all 3 key figures of
  `ZFMSALES` (and all 6 of the demo cube `0D_NW_C01`) qualify.
- **Time-independent, flat attributes.**
- **Mondrian level-based hierarchies built over flat attribute columns** (for example Year > Quarter > Month from flat
  time characteristics, Country > State > City from flat navigational attributes). They need only schema XML and
  engine support, nothing from BW's hierarchy tables.

## Out of scope (MVP)

- **BW external hierarchies** (`/BI0/H...` tables) and Mondrian **parent-child hierarchies** (these need a closure
  table).
- **Time-dependent attributes** and key-date logic (see `mondrian-hierarchies-and-time-dependency.md` for how it could
  be added later: a key-date view per characteristic).
- **Authorisations** - BW analysis authorisations are not enforced; reading BW tables directly bypasses them. Decided
  out of scope, do not plan an authorisation layer.
- Key figures with MIN/MAX, exception aggregation (AV0/AV1/LAS) or non-cumulative behaviour; mixed
  currency/unit handling (the demo cube has a single currency and unit); the package dimension and other technical
  characteristics; Composite/MultiProviders; non-HANA cubes (F+E table union); aggregate tables, roles, virtual
  cubes, drillthrough, ragged hierarchies.

## Open points

- SID 0 ("not assigned", the initial key): it is a member like any other, the empty member. FoodMart data was extended
  so that every dimension has one (id 0, see `environment.md`), and BW SIDs equal the FoodMart ids, id 0 being SID 0.
  Member counts include it. A cube whose facts never use SID 0 would still list it as long as the master data has the
  record; a rule "only if facts use it" is not implemented.
- Text language handling (demo characteristic is language independent, others are not).
