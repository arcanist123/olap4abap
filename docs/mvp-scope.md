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
  DDIC-based CDS views (7.50 has no view entities); database view `ZZXXMLA1V` + 7 digits, the name the
  schema uses (decided 2026-10-04: always a number, 16 characters do not fit the prefix and a characteristic), DDL
  source `ZZXXMLA1_C` + the same digits (decided 2026-10-06: a namespace's slashes are not allowed in it). **NUMC columns are delivered as BW holds them**, each followed
  by its number `COLUMN_INT` (decided 2026-10-13, replacing "all NUMC columns as numbers" of 2026-10-04): BW's value
  (`0042`) is the default, a number as the member's key or name is a choice of the schema, which names the `_INT`
  column (the schema builder's "As numbers" per dimension). The reference's schema format names columns only, no
  expressions, and a view is shared by every schema of its characteristic, so the view has both. FoodMart's schemas
  name the numbers (`1997`, Store Sqft), the schema builder proposes BW's values. The eMondrian reference database holds copies of the BW tables and the same views, with
  HANA's view SQL (HSQLDB 2.3.2 accepts it and `/` in quoted names; checked 2026-10-04), so the data is identical.
- **The engine reads data with native HANA SQL through ADBC** (Mondrian's `SqlQuery` with a dialect), not with
  ABAP SQL: `<SQL>` variants are raw SQL embedded in the statement. Compile-time checks of table and column names are
  given up; correctness comes from integration tests that run the same way against SAP and eMondrian.

## Member decision (2026-10-12)

- **The target is BW on HANA, and a characteristic can have many millions of members.** The engine never reads a
  whole hierarchy or level into ABAP unless the query really asks for all of its members; whatever HANA can do on
  members is pushed down to it, as the facts are: the children of a member, a member by name or key, a member's
  parent, the members of a range, the number of children, and, under a non-empty evaluator, only the members with
  facts in the context and the subcube (one grouped query, not a filter of members already read).
- Members are read as the reference's `SqlMemberSource` reads them (by parent, by key, by name) and kept for the
  request in the schema reader's member cache (`MemberCache`); nothing is kept between requests yet (Session
  decision).
- Hierarchy order is the order of a member's keys from the first level (`RolapMemberBase.compareTo`, children by
  key), compared in ABAP, not a position in a list of all members.
- Deviation: `DrilldownLevel` and `DrilldownMember` under a non-empty evaluator read only the children with facts in
  the context, as `Children` does (`SqlContextConstraint`); the reference reads all children there. A NON EMPTY axis
  removes the others anyway, except where a calculated measure has a value without facts (which `Children` under a
  non-empty evaluator does not show in the reference either).
- Cell values are read only for the members asked for, in passes as the reference reads them (`CellRequest`,
  `FastBatchingCellReader`), never grouped over the whole fact table. As in the reference, a level column with more
  than `MaxConstraints` (1,000) keys is not constrained (`Aggregation.optimizePredicates`). Deviations: the reference
  also drops constraints by its bloat estimate (it needs column cardinalities), this is not ported; `Order`/`TopCount` do not sort in a pass that missed
  cells (its result is thrown away; the values are still asked for); a cell whose evaluation missed none is kept
  instead of being evaluated again in the next pass.

## Members with facts decision (2026-10-13)

- **A BW characteristic is shared by many providers**, and its master data (the SID table, the view) has many more
  values than one InfoCube or aDSO uses: customers, materials, cost centres of the whole company. Without NON EMPTY,
  MDX lists every member of a level, so Excel's filter lists and member browsers show all of them.
- The reference schema has nothing for this: a level's members are the rows of its dimension table. The views must
  stay as they are: they are shared by every provider of the characteristic (one view per basic characteristic) and
  joined in every fact query, which must stay a cheap 1:1 join (`bw-schema-design-guide.md`); a filter against the
  facts in the view would cost a fact scan per query and a view per provider.
- **Our extension, per dimension of a cube:** the annotation `olap4abap.membersWithFacts` (`true`) on a
  `DimensionUsage` (or on the `Dimension`; the usage's overrides it) makes the cube's members of that dimension only
  the rows of the dimension table whose key (the column the foreign key refers to) is in the fact table
  (`ZZXXMLA1_CL_SCHEMA=>c_members_with_facts`, `ZZXXMLA1_CL_MODEL=>member_table`): every member read (levels,
  children, by name, ranges, `Lag`/`Lead`, children counts, `LEVEL_CARDINALITY`, the operands of native
  `TopCount`/`Order`) reads from `( SELECT * FROM <view> WHERE <key> IN ( SELECT <foreign key> FROM <fact table> ) )`.
  Fact queries still join the view itself; the facts restrict it anyway. The reference ignores annotations, so the
  schema stays valid for it, but its answers differ: a member without facts is not a member at all (it cannot be
  named, `MDX object ... not found`), also where a calculated member would give it a value.
- The restriction is against all facts of the cube, not the query's context: a member with facts only in 2024 is a
  member in a query on 2025 (that is what NON EMPTY is for).
- **Time dimensions: to be decided later.** A period without facts (a month without sales, a future month) should
  probably stay a member: `ParallelPeriod`, `Lag`, `PeriodsToDate` and ranges count positions along a level, and a
  gap changes their answers. Until then the annotation is refused on a `TimeDimension`; the aDSO's calendar
  dimensions (standard dimensions over `0CALYEAR`, ...) are not annotated in the clinic demo either.
- Tested on the clinic demo (`clinic-demo.md`, `scripts/clinic_test.py`), whose patients include 300 registered
  without a visit; FoodMart (`ZFMSALES`) stays without the annotation, so the reference's answers still apply.
- The schema generator proposes the annotation on every dimension of the cube (on by default, 2026-10-13); the UI
  switches it per dimension in the cube pane and removes it from a dimension marked as time.
- Open: HANA's plan for the semi-join on a large provider (a fact scan per member read, kept for the request by the member cache) not measured.

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
- **Key-date logic** (see `mondrian-hierarchies-and-time-dependency.md` for how it could be added later: a key-date
  view per characteristic). Time-dependent attributes and texts are read as one snapshot, valid on 9999-12-31
  (`bw-schema-design-guide.md`, decided 2026-10-08), as BW shows them with that key date.
- **Authorisations** - BW analysis authorisations are not enforced; reading BW tables directly bypasses them. Decided
  out of scope, do not plan an authorisation layer.
- Key figures with MIN/MAX, exception aggregation (AV0/AV1/LAS) or non-cumulative behaviour; mixed
  currency/unit handling (the demo cube has a single currency and unit); the package dimension and other technical
  characteristics; Composite/MultiProviders; non-HANA cubes (F+E table union); aggregate tables, roles, virtual
  cubes, ragged hierarchies. (Drillthrough was out of scope too, but Excel offers it on every cell, so it is done:
  `DRILLTHROUGH`, with the cube's default `DrillThroughAction` when there is no `RETURN`.)

## Open points

- SID 0 ("not assigned", the initial key): it is a member like any other, the empty member. FoodMart data was extended
  so that every dimension has one (id 0, see `environment.md`), and BW SIDs equal the FoodMart ids, id 0 being SID 0.
  Member counts include it. A cube whose facts never use SID 0 would still list it as long as the master data has the
  record; a rule "only if facts use it" is not implemented.
- Text language handling (demo characteristic is language independent, others are not).
