# Next steps

State on 2026-10-05, after the set functions, compound slicers, the aggregates and set algebra, named sets,
`Generate`, the member functions, the operators `IN`, `IS`, `MATCHES` and `Existing`, the remaining functions
(`VisualTotals`, `CurrentDateMember`, `Parameter`, ...), the native crossjoin, the member properties of levels and the
period functions: all 244 `reference/` cases pass, and of the 395 statements of Mondrian's tests that run on our schema
(`tests/mdx/applicable.json`) 394 give eMondrian's answer. eMondrian sometimes answers "Internal Error null" while several statements run at once (#2, #171,
#237, #348 in some runs); run such a statement again on its own. Measure progress with

    python scripts/compare-applicable.py                 # eMondrian and SAP side by side, gaps grouped
    python scripts/compare-applicable.py 46 124 126      # some statements

No statement stops at a function the engine does not evaluate any more; #64 differs in the last digits of a sum
eMondrian's database adds in another order (`docs/test-strategy.md`). The run (three statements at once) takes about
two minutes; #85 takes 1 s with the native `Order` (step 8, 105 s before), #46 2.3 s with the native `TopCount` (step
9); everything else is below 10 s.

## Now: query planning

Decided 2026-10-14 (`query-planning.md`): a planner between the validator and the engine marks every node static,
relational or computed; the static and relational parts are answered from the schema, the member reads and grouped
SQL (`GROUPING SETS`, measured on HANA in the note), and the evaluator runs only for the computed ones. Every step
keeps the answers: both test suites give the same answers with planning on and off.

0. Done (2026-10-14): baseline at 3b4ef55. `xmla_test.py`: 272 of 274 cases pass; `dbschema_schemata` and
   `session_discover_schemadata` fail because the server's `/WEB-INF/datasources.xml` lists more catalogs than the
   capture (`0D_NW_C01`, `1BW_C01`, `NWCOMPANY`, `NWPRODUCT`, the clinic demo's), not the engine.
   `compare-applicable.py`: 394 of 395 the same, #64 as known; 157 s with 3 workers, SAP 291 s in total, slowest #333
   41.9 s, #263 17.3 s, #264 15.5 s, the rest below 7.1 s.
1. Done (2026-10-14): the marking, `ZZXXMLA1_CL_MDX_PLANNER` (static, relational, computed per node; the plan of
   the axes, the slicer and the cells), 19 unit tests on `ZFMSALES`; used by the engine since step 2. The rules are in
   `query-planning.md`, The marking.
2. Done (2026-10-14): all-relational queries. Decided with the user: `cross_values` of `ZZXXMLA1_CL_MDX_FACTS` is
   extended (no parallel reader): it takes all the patterns of the axes' combinations and reads the ones no segment
   covers with one `GROUP BY GROUPING SETS` statement (`load_sets`; `GROUPING_ID` tells the sets apart, the WHERE is
   the OR of their constraints, a group outside its own set's constraint is dropped; one pattern, or more than 62
   columns, as before). The planner runs in `execute` right after `resolve_query`; when the plan of the query is
   relational (`ZZXXMLA1_CL_MDX_ENGINE=>planning`, the switch, on by default):
   - the axes are evaluated as before, but a NON EMPTY axis is not filtered by `non_empty_axis`; its cells filter it
     (`remove_empty_positions`). Kept where that would keep other positions (`axis_filter_needed`: a calculated
     measure in the query, or a member of another axis outside its hierarchy's non-All default member, Time's 1997
     with `[Time].[1998]` on the columns), and where the axes are evaluated once per root member of a hierarchy
     without All member;
   - `fast_cells` reads all combinations with one `cross_values` call, and a compound slicer of plain, disjoint
     tuples (at most 200, the measure not varying) is a predicate of every read, its tuples ORed (`compound_predicate`,
     the drill-through's `slicer_predicate`; read without the cache). Overlapping tuples (`{[Q1], [Q1].[1]}`) are
     still rolled up by the evaluator.
   Tests: unit tests `grouping_sets` and `slicer_predicate` (facts), `planning_on_and_off` (engine: six statements
   the same with the switch on and off). With planning on and off (the switch deployed both ways):
   `xmla_test.py` 272 of 274 (the two datasources cases), `compare-applicable.py` 394 of 395 (#64), SAP 271 s and
   269 s in total. HANA's plan cache shows the `GROUPING SETS` statements, the filter list's as in
   `query-planning.md`, and #218's compound slicer as one read with `CA OR OR`. Not changed: the evaluator's reads
   while the axes are evaluated (`DrilldownLevel`'s context members, the native crossjoin, TopCount, Order).
3. Retire `non_empty_axis`' evaluator loop and the repeated reads of the same groups; measure.
4. Mixed queries: the relational inputs of computed nodes read as one batch before the first pass.
5. More set nodes relational: `Filter` on a stored measure (`RolapNativeFilter`), `NonEmpty` with a second set.

## Paused: fixed selections

Not a priority since 2026-10-14; the open steps (13, 19, 20, and 21's fiscal hierarchy) wait.

Decided 2026-10-13; the model is in `bw-schema-design-guide.md`, section 3.8. A cube fixes characteristics of its
provider to one value each (`0FISCVARNT = K4`); a characteristic whose compounding is all fixed is then not
compounded (`0FISCPER` named `2024001`), and the fixed characteristic is a dimension with one member. The selection
is in generated views, the engine is not changed. Since 2026-10-13 fixing is an edit of the schema (steps 9 to 12
below), no longer a parameter of the proposal; a default selection in the proposal (the only variant with facts,
...) is open.

1. Done: table `ZZXXMLA1_VIEW` (kind, object, selection; view and DDL source), `src/zzxxmla1_view.tabl.xml`.
   `ZZXXMLA1_CL_BW_VIEW_GEN` finds and registers views through it, a plain view of an older run by its description.
2. Done: views with a selection: a characteristic's view filtered on its fixed compounding (no `COMPOUND_KEY` when all of
   it is fixed); a provider's fact view filtered on the fixed characteristics, on an InfoCube too (inner join to the
   SID tables), with `SID_<field>` only for the characteristics still compounded.
3. Done (replaced by steps 9 to 11): provider and proposal: `ZZXXMLA1_CL_BW_PROVIDER=>read` and the proposal take the selection; the proposal drops
   the fixed dimensions, treats the fully fixed compounded ones as plain and writes the annotations
   `olap4abap.fixed.<characteristic>` on the cube. A value without SID, or a compounded characteristic fixed without
   its compounding, is refused.
4. Done (the selection moved to `POST fix`, step 10): API: `GET proposal?provider=X&fixed.<characteristic>=<value>`; accept generates the views of the cube's selection
   for the placeholders; check refuses views of another selection than the cube's annotations and a dimension shared
   by cubes with different selections; accept and remove delete the views with a selection no schema file names.
5. Done: test data. The clinic demo has its own fiscal time in `ZCLVISIT` and `ZCLVISITA` (`clinic-demo.md`): the
   variant `ZCLFISCVR` (K1, K2, K4, each visit under one), the period `ZCLFISCPR` and the year `ZCLFISCYR` compounded
   with it. Not BW's `0FISC*`: BW checks their values against the source system's fiscal year variants, and
   the warehouse's truth is its SID and fact tables. Its hand-written schemas have the fiscal time as dimensions
   (variant, year and period compounded), and the setup deploys a second catalog per provider with the variant fixed
   to K4 (`ZCLVISIT_K4`, `ZCLVISITA_K4`; 2026-10-13), so the demo shows both without a call of the API.
   `scripts/fixed_selection_test.py` (2026-10-13, all passed): the plain catalogs as oracle (periods `K1/2024001`
   ...), the K4 catalogs (11,318 visits, periods `2024001` ... `2025012`, no variant), then the proposal with K4
   fixed accepted into a test catalog and removed, the filtered views kept as the K4 catalogs name them;
   `schema_api_test.py` checks the refusals and `GET values`.
6. Done (2026-10-13, replaced by step 11): the UI. A proposal's section "Fixed characteristics" picks characteristics (with their
   compounding) and values (`GET values`, the SID table) and proposes again; an accepted cube shows its fixed
   characteristics read only (`schema-generator.md`, UI; `scripts/schema_ui_test.py`).
7. Done (2026-10-13, step 22 below): a default selection in the proposal: K4 fixed when the provider has `0FISCYEAR`
   or `0FISCPER`.
8. Done for `0FISCYEAR` and `0FISCPER` (2026-10-13, step 22); later: the rest of (`time-master-data.md`, open step 6 of compounded
   characteristics); a fiscal year > period hierarchy on a fiscal period.

### Fixing as an edit (decided 2026-10-13)

Steps 3, 4 and 6 made the selection part of the proposal: it was chosen before the schema existed, and changing it
proposed again and discarded the edits. Now a selection is an ordinary edit of the cube, made on the dimension's pane,
which the server applies to the schema as it is. Decided with the user:

- **A proposal is always the plain one** (revised 2026-10-13: but for the fiscal defaults, step 22) (no `fixed.` parameters, no "Propose again", no selection in the URL). The
  catalog keeps its default name, the provider's: a selection never renames it (five fixed characteristics would make
  an unusable name). Who wants the plain and a fixed cube side by side names one catalog differently.
- **A fixed characteristic keeps its dimension, with one member**: its view is filtered on its value too, so every
  hierarchy of it has that member under All, and the user's hierarchies, properties and double-click columns stay. The
  facts are the filtered fact view, so totals hold whatever MDX asks. Removing the dimension from the cube stays an
  ordinary edit. This replaces "a fixed characteristic has no dimension" (`bw-schema-design-guide.md`, section 3.8).
- **The server rewrites the schema** (option c): `POST fix?cube=X&fixed.C=v...`, body the current XML and the whole
  new selection, answer the new XML; the UI replaces the document, which is one edit (undo). It needs BW's metadata:
  which views the cube reads, the compounding, the fact view's column names.
- **Views are found or generated on accept** through table `ZZXXMLA1_VIEW` (kind, characteristic or provider,
  selection), as now: schemas that fix the same values reuse one view, another selection gets its own. The cleanup of
  unused views after accept and remove stays for now (its runtime is the thing to watch: it reads every schema file).

Steps:

9. Done: views: a fixed characteristic's own view is filtered on its value (`WHERE key = v`, selection `C=v` with the
   fixed compounding); `fixed_compounding` becomes `view_selection` (the characteristic itself included). An aDSO's
   compounded characteristic is keyed by its SID in the fact view also when all its compounding is fixed (until now by
   its value), so fixing changes no attribute name, only columns. Not filtered: a reference characteristic (its view
   is its basic one's, which other characteristics share); fixing a basic characteristic that another characteristic
   of the provider references is refused.
10. Done: proposal and API: the proposal keeps the fixed characteristics' dimensions; `GET proposal` takes no selection.
    `POST fix?cube=X&fixed.C=v` (new class `ZZXXMLA1_CL_SCHEMA_FIX`): the provider found from the cube's fact table
    (placeholder, registered fact view or BW's fact table), read for the old selection (the cube's annotations) and the
    new one; then the annotations, the fact table, the measure columns, the foreign keys (a usage found by the old
    one) and the tables of the dimensions found so are replaced, and a characteristic whose compounding becomes all
    fixed is named by its own key (`COMPOUND_KEY` replaced by the key column, its `OrderByColumn` removed) or the
    other way. The answer has the XML, the outline, the tables replaced and the new tables' NUMC numbers. `GET
    proposal`, `GET schema` and `POST fix` list the cube's characteristics (name, text, compounding, the dimension
    that is on it, the fixed value), which the UI needs to offer fixing on a dimension.
11. Done: UI: the dimension pane of a characteristic has "Fixed value" (values from `GET values`, a compounded one only
    once its compounding is fixed; un-fixing a characteristic un-fixes those compounded with it); the cube pane lists
    the fixed characteristics, read only, with links to their dimensions. The proposal's section goes.
12. Done: tests (2026-10-13, all passed): unit tests of the views and of `ZZXXMLA1_CL_SCHEMA_FIX` (fix, round trip,
    refusal, the characteristics); `fixed_selection_test.py` (44 checks) fixes K4 on the plain proposal through
    `POST fix`, accepts, queries (11,318 visits, periods by their own key, the variant with one member), un-fixes (the
    plain tables back) and removes; `schema_api_test.py` checks the refusals of `POST fix`; `schema_ui_test.py` fixes,
    undoes, refuses a value and un-fixes on the dimension's pane; `clinic_test.py` passes. The clinic demo's K4
    catalogs have the variant as a dimension with one member (the demo regenerated). A fix takes about 0.4 s (two
    provider reads).

Open questions, to revisit after the current scope (2026-10-13: accepted for now, the user disagrees with both long
term):

- **aDSO keyed by SID when the compounding is all fixed.** An aDSO's compounded characteristic stays keyed by its SID
  (`SID_<field>` in the fact view) even when all its compounding is fixed and its value alone would identify it.
  Chosen so that fixing never renames the key attribute (`C SID` ↔ `C Key`), only columns. Costs a join to the SID
  table per such characteristic in the fact view. Long term: key it by its value, and have `POST fix` rename the key
  attribute and what refers to it (levels, properties, double-click columns).
- **Reference characteristics and fixing.** A fixed reference characteristic (`0SOLD_TO` → `0CUSTOMER`) keeps its basic
  characteristic's unfiltered view, because the view is per basic characteristic and other characteristics share it;
  it shows one member only with members with facts on. Fixing a basic characteristic that another characteristic of
  the provider references is refused for the same reason. Long term: views (and placeholders) per characteristic and
  selection, so a reference characteristic gets its own filtered view and both cases work.

### Selections (decided 2026-10-13)

Fixing is not enough to make `0FISCPER` a time dimension: its SID table holds the special periods 013 to 016 when
any provider posts to them, and the positional time functions (`Lag(12)`, `ParallelPeriod`, `ClosingPeriod`) count
them. Usually the cube's own facts have the twelve regular periods only. Decided with the user, the model in
`bw-schema-design-guide.md`, section 3.8:

- **A fixed value is one case of a selection**: a BW range table per characteristic (`I`/`E`, `EQ` ... `CP`, `NP`,
  BW's patterns), in one of two modes: **filter the cube** (members and facts, as fixing does now; the fixed value is
  `I EQ v`) or **restrict members** (only the characteristic's view; the facts are not filtered at query time).
- **The facts must agree with restricted members**: a probe of the facts (distinct values of the fact column against
  the SID table with the negated selection) refuses the schema whenever the facts hold an excluded value, always, not
  only for time dimensions; no unsynced schema is written. A fiscal period whose facts have special periods is not
  time in that cube; the calendar characteristics are, or the cube is filtered.
- **Not chosen:** folding the special periods into period 012 in the fact view (a computed column over hundreds of
  millions of rows on every query, and period 012 no longer BW's); excluding them from the facts by default (silently
  changes BW's year totals); `olap4abap.membersWithFacts` (a semi-join over the facts per query, not allowed on time,
  and it drops regular periods without facts, which breaks the positional functions as much).
- **A global probe** in the schema builder's start page runs the probes of all catalogs, because a load after the
  accept can bring an excluded value into the facts.

Steps:

13. Selection class: a global class (`ZZXXMLA1_CL_BW_SELECTION`) with the range table type, parsing and writing the
    annotation text, the canonical text for `ZZXXMLA1_VIEW`, the SQL condition (CDS and native; `CP`/`NP` to `LIKE`
    with `%`/`_` escaped, `NB`, `NE`), its negation for the probe, "one `I EQ` value" for the uncompounding rule, and
    the checks (`EQ` needs a SID, `BT`/`NB` a high value, no quote). Unit tests.
14. Done: table `ZZXXMLA1_VIEW`: `SELECTION` is a CHAR 255 key field, too short for range tables. It becomes an `SSTRING`
    of 1,333 (enough for now; the table is read with ABAP SQL only, not through ADBC), no longer key: 1,333
    characters do not fit the table's key length, so the key is `DDL_NAME` (one row per view anyway), and the
    generator finds a view by kind, object and selection in the `WHERE` as now. The existing rows keep their values.
    Decided 2026-10-13: no hash. A view is found by its selection's canonical text, which only the selection class
    writes (characteristics sorted, rows sorted by sign, option, low, high and without duplicates, one format per
    row, one `I EQ` row written `C=v`); a hash would only be a shorter form of the same text. Selections equal in
    meaning but written differently (`I BT '001' '012'`, `E CP '*013'`...) get views of their own, a duplicate and
    never a wrong one. Uniqueness is the generator's: it looks the view up before it generates one.
15. Done (2026-10-13): views: a characteristic's view filtered on the selections of its key fields (both modes); the
    fact view filtered on the filter-the-cube characteristics only, and none when there are none.
    `ZZXXMLA1_CL_BW_VIEW_GEN` takes a selection (`ty_t_selection`, `ZZXXMLA1_CL_BW_SELECTION`'s characteristics with
    mode and rows) instead of fixed values: `WHERE` with the selection class's condition on the key field; only a
    single `I EQ` value of the compounding leaves `COMPOUND_KEY`. An InfoCube's fact view joins the SID table of a
    filtered characteristic on the SID alone and has the condition in `WHERE` (a condition of several rows is no join
    condition; the demo's K4 view regenerated gives the same visits). The callers still speak fixed values until step
    16 and passed `selection_of( fixed )` (filter the cube, one `I EQ` row each; same canonical text, so the existing
    rows of `ZZXXMLA1_VIEW` stay valid). Checked on SAP: views of the clinic demo for `ZCLFISCVR` in K1 or K4 with a
    period range in restrict members (`I BT`, `E EQ`), and for K4 with the period filtered (`I CP`, `E NB`), activate,
    the period views have the rows of their SID table under the same condition and the aDSO's fact views the aDSO's
    visits.
16. Done (2026-10-13): schema and API: annotations `olap4abap.filter.<characteristic>` and
    `olap4abap.members.<characteristic>` (the rows as `ZZXXMLA1_CL_BW_SELECTION=>rows_text` writes them), the old
    `olap4abap.fixed.` read as filter `I EQ` and rewritten by `POST fix` (`ZZXXMLA1_CL_SCHEMA_FIX=>cube_selection`,
    refused if a characteristic has two); `POST fix` and `GET values` take `filter.C=<rows>`, `members.C=<rows>` and
    `fixed.C=v`; the uncompounding rule on one `I EQ` value in either mode (the view generator's, unchanged);
    `characteristics` of the answers carry `mode` (`filter`, `members` or null), `rows`, `selection` (their text) and
    still `fixed`/`value` for one `I EQ` value; check and accept work on selections (only filter-the-cube
    characteristics need a fact view) and refuse different selections of a shared dimension as for fixed values.
    `ZZXXMLA1_CL_BW_PROVIDER` reads for a selection (`read( selection = ... )`, `ty_provider-selection`) and
    `check_selection` replaces `check_fixed`: the rows checked by the selection class, an `EQ` value needs a SID
    under the selection of its compounding where that is restricted. A compounded characteristic no longer needs its
    compounding restricted (section 3.8: its rows compare its own key under every value of its compounding), and
    `GET values` of it answers under every value of its compounding without parameters. `selection_of`,
    `selection_text( fixed )` and `ty_t_fixed` of the view generator are gone; the clinic generator writes the new
    annotation (the demo's existing K4 catalogs keep the old one, which is read the same). The UI reads the new
    annotations and passes selections other than fixed values through `POST fix` unchanged (its selection editor is
    step 18). Tests: unit tests of `ZZXXMLA1_CL_SCHEMA_FIX` (old annotation, restrict members, two selections);
    `schema_api_test.py` (refusals of rows, two selections, `EQ` without SID under the compounding, restrict members
    through `POST fix`), `fixed_selection_test.py`, `schema_ui_test.py` and `clinic_test.py` pass.
17. Done (2026-10-13): the probe (`ZZXXMLA1_CL_SCHEMA_PROBE`): per cube and restrict-members characteristic, the
    excluded values in its facts with their counts (at most 20, by value; a compounded one as `K4/2024013`). Run by
    `POST fix` (400 with the values), accept and `check?probe=true` (400 on a refusal, else the answer has `probe`),
    and `POST probe[?catalog=X]` (every catalog, or one: `{catalogs: [{catalog, ok, cubes: [{cube, ok,
    characteristics: [{name, ok, values: [{value, facts}]}]}]}], runtime}`, runtime in ms, nothing written).
    Decided with the user (2026-10-13): the probe reads the cube's facts as the cube reads them, the facts filtered on
    the filter-the-cube characteristics, so values outside the cube refuse nothing; a catalog `POST probe` cannot
    probe (its schema file missing or unreadable, a cube that restricts members not on a BW provider's tables) is an
    entry with `error` and no cubes, the other catalogs are probed. Built: the facts are read from BW's tables as the
    fact view is made of them (`ZZXXMLA1_CL_BW_VIEW_GEN->fact_metadata`), not from the fact view, so the probe needs
    no generated view and runs before accept (on `POST fix` the view of a new selection is only a placeholder): an
    InfoCube's SIDs grouped, then joined to the SID table with the negated selection on the key field; an aDSO's
    reporting view grouped on the values where the negated selection holds. A cube without restrict-members
    characteristic is not looked at (FoodMart's catalogs probe as ok). Measured on the wide demo (1,000,000 facts):
    the probe adds 0.2 to 0.4 s to a `POST fix` (which takes 1.4 to 1.8 s there, the provider of 100 characteristics
    read twice); all ten catalogs of the server probe in 65 ms (none restricts members). A bigger load is still to
    measure (`ZXMLWIDE` with more records, members with facts step 4). Tests: unit tests of the statements (InfoCube
    with a filter, aDSO, no field) and the refusal; `schema_api_test.py` (refusals of `POST fix` on both providers,
    also under a filter on K4, `POST probe` of all catalogs and of one, 404, 405); `fixed_selection_test.py`,
    `clinic_test.py` and `schema_ui_test.py` pass.
18. Done but for the probes (2026-10-13): UI: the dimension pane has "Selection" under "Fixed value": a table of rows
    (sign, option, low, high; values from `GET values`, free text for patterns), the mode switch, presets (`0FISCPER`:
    the regular periods) and Apply through `POST fix`; a fixed value stays one click (`I EQ`) (`schema-generator.md`,
    UI; `schema_ui_test.py`: a members range the clinic's facts contradict is refused with the values, the same range
    filtering the cube is applied and removed; the fiscal defaults of `0TSC0T001` are twelve rows, removed and brought
    back by the preset). Open: Accept's dialog runs `check?probe=true` and shows a refusal's values (accept refuses
    already, with the values); the start page gets "Probe all catalogs" with a result per catalog.
19. Test data: the clinic demo's period `ZCLFISCPR` gets special periods (013 to 016) in its master data only, for a
    restrict-members catalog, and facts in period 013 under one variant only, so the probe refuses that variant and
    accepts the others.
20. Tests: unit tests of 13 and 15; `fixed_selection_test.py` extended (ranges in both modes, the probe's refusal,
    the old annotation); `schema_api_test.py` (`POST probe`, refusals); `schema_ui_test.py` (the selection table, the
    probe on the start page).
21. Fiscal time: done in step 22 but for a fiscal year > period hierarchy on a fiscal period marked as time (open).
22. Done (2026-10-13): fiscal defaults of the proposal and the fiscal time master data. Decided with the user:
    - **K4 is proposed**: a provider with `0FISCYEAR` or `0FISCPER` (compounded with `0FISCVARNT`) is proposed with
      `0FISCVARNT` filtering the cube on `I EQ 'K4'`, the most common variant; the user changes it on its dimension.
    - **The period is restricted to the regular periods** (`olap4abap.members.0FISCPER`, `I CP '*001'` to
      `I CP '*012'`, K4's months), and **year and period are marked as time**, less friction for the user.
    - **A cube whose facts post to period 000 or 013 to 016 has no fiscal time dimension**: the probe refuses the
      restriction, the period is neither restricted nor time there (a note with the values), and the model has to
      make `0CALMONTH` the time, with its own logic of binding the fiscal period to the calendar month (open, below).
    - **Only `0FISCPER` and `0FISCYEAR`** get defaults.
    - **The time generator fills them as it fills `0CALYEAR` and `0CALMONTH`**.
    Built: `ZZXXMLA1_CL_SCHEMA_DEFAULTS` (new; `propose` checks K4 through the provider read and probes the period;
    `fiscal_defaults` and `regular_periods` unit-tested), called by `GET proposal` before the proposal, which reads the
    provider for the selection; `ZZXXMLA1_CL_SCHEMA_PROPOSAL=>propose( time = ... )` writes the time dimensions as the
    UI marks one (level types, no members with facts); its notes join the proposal's (the schema pane's "Not proposed"
    is now "Notes"). `ZZXXMLA1_CL_TIME_MD` fills `0FISCYEAR` and `0FISCPER` as it fills `0CALYEAR` and `0CALMONTH`, for K4
    only (its years are the calendar years, its periods 001 to 012 the months; `time-master-data.md`); filled on
    the development system for 1995 to 2029: BW's SID conversion
    made all 17 periods of every year (595 SIDs, 420 regular), which is why the restriction is needed.
    Tests: unit tests of the defaults, the time dimension of the proposal and the fiscal master data;
    `scripts/fiscal_default_test.py` (new, 19 checks: the proposal of BW's content cube `0TSC0T001`, accepted into
    `ZZFISCTEST`, twelve periods per fiscal year, `Lag(1)` of `2025001` is `2024012`, removed); `schema_api_test.py`,
    `fixed_selection_test.py`, `clinic_test.py` and `schema_ui_test.py` pass.
    Open:
    - the derived `0CALMONTH` time for a cube whose facts post to special periods (the binding of the fiscal period
      to the calendar month);
    - the probe's refusal path of the defaults is not tested live: no provider with `0FISCPER` has facts in special
      periods (step 19's test data is the clinic demo's own `ZCLFISCPR`, which gets no defaults);
    - a fiscal year > period hierarchy (`0FISCPER` has `0FISCYEAR` as an attribute), so `ParallelPeriod` and `Ytd`
      work on the period's dimension.

## Now: members pushed down to HANA

Decision in `mvp-scope.md` (Member decision, 2026-10-12). Found with Excel on the wide demo `ZXMLWIDE`: a label filter
on `[Dimension 00]` (100,000 members) made every query read and sort all 100,000 members in ABAP to show one
(`DrilldownLevel` → `get_member_children` → `load_members`), 2-3 s per query. Order, each step with all `reference/`
cases and the applicable statements passing:

1. Done (2026-10-12): hierarchy order without positions: members carry an order key built from their typed keys
   (`RolapMemberBase.compareTo`; `ZZXXMLA1_CL_MODEL=>order_key`, the key columns' types from HANA's catalog);
   `Hierarchize`, `Order`, ranges and the native crossjoin's order use it instead of the position in the loaded
   hierarchy.
2. Done (2026-10-12): the schema reader reads members by SQL and caches them (`SqlMemberSource` in
   `ZZXXMLA1_CL_MODEL=>read_members`, `MemberCache`): children of a member, a member by name under its parent or on a
   level (UPPER on both sides, a plain comparison for names without letters or of number columns), by key, a
   member's parent (by its path), a level's members only when asked for, ranges and `Lag`/`Lead` along a level (one
   query each, `order_condition`), children counts in one grouped query per level (DisplayInfo,
   `CHILDREN_CARDINALITY`), the ancestors kept with every read, each query answered once per request.
   `load_members` is gone.
3. Done (2026-10-12): members from the facts (native crossjoin) are read by their paths in one query per 1,000
   (`get_members_by_paths`; an IN list on the key of a level of unique members), not looked up in the level's members.
4. Done (2026-10-12): `Children`, `Members` (above 300 members), `Descendants`, `DrilldownLevel` and
   `DrilldownMember` under a non-empty evaluator: only the members with facts in the context and the subcube, their
   paths from one grouped fact query (`context_children`, `context_level_members`). Excel's label filter on
   `[Dimension 00]` of `ZXMLWIDE`: 0.13 s per query instead of 2-3 s, the same answers.
5. Done (2026-10-12): `MDSCHEMA_MEMBERS` reads through the schema reader only what its restrictions can select (a
   member and its TREE_OP relatives, the restricted levels); `MDSCHEMA_HIERARCHIES`' default member of a hierarchy
   without All member is its first member (LIMIT 1).
6. Open: a wide-demo characteristic with millions of members to measure against.
7. Done (2026-10-12): cell values are read as the reference reads them (`FastBatchingCellReader`, `CellRequest`,
   `Segment`): each phase of a query (slicer, axes, named sets, cells) is evaluated with a batching reader that records
   the cells it misses (their value 0 for the pass, `RolapUtil.valueNotReadyException`), then the recorded cells of each
   pattern of hierarchies and levels are read with one grouped query whose level columns are constrained to the keys
   asked for (`IN` lists, `ZZXXMLA1_CL_MDX_FACTS=>load_aggregations`), and the phase is evaluated again until it misses
   none (`RolapResult.phase`, at most `MaxEvalDepth` 10 passes). What was read is kept as segments: a cell a segment
   covers without a group has no facts. The native crossjoin's tuple read is constrained to its fixed members the same
   way. Applicable statements: same answers, the whole run 191 s instead of about 240 s; #46 and #85 (Order/TopCount
   over 100,000+ tuples) take about 105 s instead of about 80 s, the second pass evaluating every value again.
8. Open: an unqualified member name (`[USA]`) is looked for by name in every hierarchy, one query each (100 on
   `ZXMLWIDE`).
   Done (2026-10-12): `Order` over large sets. #85 (`Head(Order(...), 5)` over the 85,000 tuples of a
   `NonEmptyCrossJoin` of customers and products, the query a pivot client generates) took 105 s: the merge sort made
   1.4 million comparisons, each finding the key's dependent members again (`depends_on` over the key's tree) and its
   value by a string key. Two changes:
   - Native `Order` (our extension; the reference has no `RolapNativeOrder` and sorts in memory, `Sorter`):
     `ZZXXMLA1_CL_MDX_ENGINE=>native_order`, `ZZXXMLA1_CL_MDX_FACTS=>ordered_paths` (`top_count` is now one of its
     callers). Keys `BASC`/`BDESC`, each the `OrderKey` of an operand's current member or of its `Ancestor` at a level
     (its level's key column: a number as a number, a string `LOWER`, then as it is, `Util.caseSensitiveCompareName`;
     the All level orders nothing), or a stored measure, also through calculated measures that are only that measure
     (`[*SORTED_MEASURE]` -> `[*FORMATTED_MEASURE_1]` -> `[Store Sales]`). The set: what the native crossjoin reads
     (`NonEmptyCrossJoin`, `CrossJoin` under a non-empty evaluator), also through named sets (their context is the
     slicer's) and `Generate(set, {(the current members of its hierarchies)})`, which gives the set as it is. One
     query as native `TopCount`'s: the native crossjoin's tuples (inner join to the facts of the set's context), the
     measures' values left-joined (no facts: NULL, first ascending, last descending), `ORDER BY` the keys, then the
     members' keys (the set's order), and `Head(Order(...), n)` (also of a named set not evaluated yet) is `LIMIT n`.
     Not native: `ASC`/`DESC` (hierarchical), any other key or set, calculated members in the context of a measure key.
   - The interpreted sort (`sort_tuples`, also `TopCount`/`BottomCount` that are not native): with break keys only,
     the positions of the members each key depends on are found once, every key's value is evaluated once per tuple
     into a table (an error kept for the comparison that meets it; equal dependent members compare as 0 by an id),
     and the tuples' indexes are merge-sorted by these values. A hierarchical key keeps the old comparator
     (`merge_sort_tuples`).
   #85: 1 s (eMondrian 3.6 s). All 90 applicable statements with `Order`, `Head`, `TopCount` or `BottomCount` and 16
   edge cases (`BDESC`, ties, string keys, an ancestor key, the All level, slicer, subselect, a chain of calculated
   measures, empty values in another context, named sets with `Generate`, the fallbacks, evaluation errors) give
   eMondrian's answers; the whole run takes 104 s. Still open: a second pass of a phase evaluates the sort values of
   an interpreted `Order` again (`sort_values` are kept per run).
9. Done (2026-10-12): native `TopCount`/`BottomCount` (`RolapNativeTopCount`, `ZZXXMLA1_CL_MDX_ENGINE=>native_top_count`,
   `ZZXXMLA1_CL_MDX_FACTS=>top_count`): by a stored measure, of a crossjoin (`CrossJoin` or `*`, our extension: the
   reference's `CrossJoinArgFactory` knows only the function names, so it sorts #46 in memory) of level members,
   `Children` or `Descendants`, or of one of them. One query: the crossjoin of the operands' members (the distinct key
   columns of each dimension table) left-joined to the facts grouped by these columns with the context and the
   subcube, `ORDER BY` the value (`DESC NULLS LAST` for TopCount, `ASC NULLS FIRST` for BottomCount: the empty value
   is the smallest), then the members' keys (the stable sort keeps the set's order), `LIMIT` the count. Under a
   non-empty evaluator only a `CrossJoin` the native crossjoin would read, inner-joined to the facts of the context
   without the default members (its tuples) and left-joined to the value's. The whole crossjoin's size is counted
   first (one query) and fails on the result limit as the interpreted one does. Not native with calculated members in
   the context (a compound slicer, #73 and #297-#301: about 8 s each), a calculated measure or another set
   (`Distinct`, a member list). #46: 2.3 s instead of 104 s (eMondrian 3 s), the same answers; all 47 applicable
   statements with `TopCount`/`BottomCount` and 13 more edge cases (empty tuples, ties, an empty key, `Fact Count`,
   slicer, subselect, `NON EMPTY`) give eMondrian's answers.

## Now: members with facts

Decision in `mvp-scope.md` (Members with facts decision, 2026-10-13): a dimension of a cube can show only the members
that have facts in it, by the annotation `olap4abap.membersWithFacts` on its `DimensionUsage`.

1. Done (2026-10-13): the annotation (`ZZXXMLA1_CL_SCHEMA`, refused on a time dimension), member reads from
   `ZZXXMLA1_CL_MODEL=>member_table`, the clinic demo's 300 patients without a visit (region Coastal without any) and
   its schemas annotated on every dimension but time; `scripts/clinic_test.py` (71 checks on `ZCLVISIT` and
   `ZCLVISITA`: every level, children and descendants equal to NON EMPTY over all facts, members without facts not
   found, counts, ranges, native `TopCount`, `LEVEL_CARDINALITY`, time not restricted). FoodMart unchanged: the
   `reference/` cases and the applicable statements give the same answers.
2. Open: time dimensions (decide whether and how a period without facts is a member).
3. Done (2026-10-13): the schema generator proposes the annotation on every `DimensionUsage` (on by default:
   a characteristic is shared by many providers, which use few of its values); the cube pane's "Members with facts"
   column switches it per dimension, and marking a dimension as time removes it (`scripts/schema_ui_test.py`).
4. Open: measure the semi-join on a large provider (`ZXMLWIDE` with more records).

## Then: the schema generator

Design in `schema-generator.md`. Order:

1. Done: the decisions written down (`schema-generator.md`).
2. Done: the cube-type aDSO `ZFMSALESA` with the FoodMart facts and standard time characteristics, created and loaded
   by `ZZXXMLA1_CL_BW_FOODMART_GEN` (`environment.md`, FoodMart data for the BW cube).
3. Done (2026-10-06): the provider reader `ZZXXMLA1_CL_BW_PROVIDER` and the proposal `ZZXXMLA1_CL_SCHEMA_PROPOSAL`;
   `ZZXXMLA1_CL_BW_VIEW_GEN` takes its table names from BW (`schema-generator.md`, Implementation). The `ZFMSALES`
   proposal loads in `ZZXXMLA1_CL_SCHEMA`.
4. Done (2026-10-06): the `/zzxxmla1/schema/api` endpoints (`ZZXXMLA1_CL_SCHEMA_API`, `schema-generator.md`, The
   API); accepted schemas of the InfoCube `ZFMSALES` and the aDSO `ZFMSALESA` are served by the XMLA endpoint. An
   aDSO is modelled as an InfoCube: its time characteristics are dimensions on their views, no time dimension on the
   fact table (`schema-generator.md`, Time; decided 2026-10-06).
   Then (2026-10-06) `GET schemas`/`GET schema` to reopen an accepted schema (an existing catalog keeps its schema
   file), `POST check` (accept's checks, nothing written), and a clear reader error for an unnamed hierarchy next to
   an attribute of the dimension's name.
5. Done (2026-10-06): the Preact UI (`schema-generator.md`, UI), served as files of the server by
   `ZZXXMLA1_CL_WEB_APP` (since 2026-10-07 from the code, `ZZXXMLA1_CL_WEB_APP_FILES`), checked with `scripts/schema_ui_test.py`.
   Then (2026-10-06) removing a catalog (`POST remove`, Remove… on the start page; checked end to end with a
   throwaway catalog). One cube per catalog for the MVP (`mvp-scope.md`, Catalog decision).
   Open: an accept through the UI checked by hand (the API's accept was); calculated members of the schema (the
   reader ignores them) and aggregators other than `sum`/`count` (the engine sums them) are not offered.

## Done: compounded characteristics

Built 2026-10-12; the model is in `bw-schema-design-guide.md`, section 3.7. A compounded characteristic (`0FISCPER`
with `0FISCVARNT`, a cost centre with its controlling area) is unique only by all its key fields: `2024001` exists
under K4 and under V3. On an InfoCube the members' unique names collided; on an aDSO, keyed and joined by the value, a
fact was counted once per compounding value, in cells and in the native crossjoin, `TopCount` and `Order`.

1. Done: test data. The clinic demo (`docs/clinic-demo.md`) has the room `ZCLROOM`, compounded with the site
   `ZCLSITE`: R01 to R04 at both sites, R05 only in the north, in `ZCLVISIT` and `ZCLVISITA`. Joined by the value, the
   aDSO's visits were 64,516 instead of 33,956.
2. Done: the HANA plan on `ZCLVISITA`. A query without the room has no join to its SID table (pruned); one with it
   joins the facts to the SID table's index on both key fields. A compounded characteristic costs nothing where it is
   not used.
3. Done: the fact view. `ZZXXMLA1_CL_BW_VIEW_GEN` (`fact_layout`, `generate_fact_view`) reads an aDSO's compounded
   characteristics (`RSDIOBJCMP` of the basic characteristic) and writes a CDS view on `/BIC/A<adso>7`: every field
   without namespace and `SID_<field>` per compounded characteristic. `ZZXXMLA1_CL_BW_PROVIDER` reads the aDSO from it
   (a placeholder `ZZXXMLA1_F_<aDSO>` until it exists, generated on accept by `ZZXXMLA1_CL_SCHEMA_API`); the proposal
   keys the compounded dimensions by `SID`. No engine change for the joins.
4. Done: names. The characteristic's view has `COMPOUND_KEY` (`NORTH/R01`, `#/#`), the key attribute's `NameColumn`;
   the own key is the member property `Key`. Not the caption: `captionColumn` is not supported.
5. Done: order. `ZZXXMLA1_CL_SCHEMA` reads an attribute's `OrderByColumn` (and `orderBy`) and a level's
   `ordinalColumn` as the reference does (`RolapLevel`, `RolapDimension.resolveOrdinalColumn`); members are read
   ordered by it, then by the key, their order key is the ordinal's, then the key's, `order_condition` (`Lag`, `Lead`,
   ranges) compares the ordinal first, and the native `Order`/`TopCount` (`ordered_paths`) order by it. The clinic's
   south rooms get the lower SIDs and still come after the north ones.
6. Done for `0FISCPER` and `0FISCYEAR` (2026-10-13, selections, step 22): the fiscal time characteristics in the
   time master data (
   `time-master-data.md`): an aDSO's fact whose value has no SID has no `SID_<field>` and drops out of the engine's
   inner join.

Not done, decided: no hierarchy with the compounding as a level above (`[0FISCPER.Fiscal].[K4].[2024001]`), the
schemas are flat; no join on two generated string columns (HANA cannot use the columns); no SID columns for the characteristics without compounding (a join each,
up to 100 on the wide demo, and SID order); no keys of several columns in the engine (not in the reference's schema,
which then could not serve these schemas).

## Done: Time is a TimeDimension

The schema's Time dimension has `type="TimeDimension"` and time level types on its levels and attributes
(`TimeYears`/`TimeQuarters`/`TimeMonths`, `TimeWeeks`/`TimeDays` for Weekly, `TimeUndefined` for the day name and the
fiscal period). `ZZXXMLA1_CL_SCHEMA` reads the level types with Mondrian's checks, the schema reader carries
`DimensionType` and `LevelType` for the time functions, the rowsets give `DIMENSION_TYPE` 1 and the `LEVEL_TYPE` codes,
and the engine no longer evaluates the axes once per year (`RolapResult.loadSpecialMembers` skips a time dimension), so
value-dependent sets answer as in FoodMart. The generator rule for BW: a characteristic of type date (DATS) or a BW
time characteristic (`0CAL*`, `0FISC*`) becomes a time dimension (`docs/bw-to-schema-mapping.md`).

## Then: the set functions

Done: `Filter` (`FilterFunDef`, with `IsEmpty`) and `TopCount`/`BottomCount` (`TopBottomCountFunDef`); 11 of the 20
statements that stopped at `Filter` and 21 of the 22 that stopped at `TopCount` now give eMondrian's answer, the others
stop at the next function (`:`, `Descendants`, `VisualTotals`, `Avg`, `Sum`). Then `:` (`RangeFunDef`) and
`Descendants` (`DescendantsFunDef`, all signatures, of a set as `Generate`): of the 34 statements that stopped at them,
16 give eMondrian's answer, 13 stop at a compound slicer, 1 at `Count`, 4 are big crossjoins (memory limit,
#144 order). Then the compound slicer (`RolapResult`: unary members, `CompoundSlicerRolapMember` placeholders,
SCOPED solve order with cube scope, `CurrentMember` on a slicer hierarchy an error): 21 of its 26 statements give
eMondrian's answer, 5 stop at `Distinct`, `Tail` or `SetToStr`. eMondrian needed a fix for it
(`scripts/patches/compound-slicer.patch`, `docs/environment.md`). Then the aggregates and set algebra:
`Union`, `Except` (and `set - set`), `Intersect`, `Head`/`Tail`, `Distinct`, `<Set>.Item` (by index and by name, the
validator resolves `SetItemFunDef`'s string resolver), `<Tuple>.Item`, `SetToStr`, `Count` (with `EXCLUDEEMPTY`) and
`<Set>.Count`, `Sum`, `Avg`, `Min`, `Max`, `Rank` (2 and 3 arguments); `Aggregate`'s roll-up now shares their
`FunUtil` arithmetic. `Hierarchize` puts calculated members after their stored siblings (#242). Of the 35 statements
that stopped at them 22 give eMondrian's answer; the others stop at `Existing` (4), `PeriodsToDate` (3), `Generate` (2),
`.Parent`, `.LastSibling`, `AddCalculatedMembers`, `IS EMPTY`. An index or name not in the set gives Mondrian's null
member, which the engine does not have yet ("not implemented"). Then named sets: `WITH SET` (`SetBase`, found by its
name as written, may refer to sets defined after it), aliases `set AS name` (`Query.ScopedNamedSet`, visible in the
call around the AS), `<Set>.Current`, `<Set>.CurrentOrdinal` and `Generate` (set and string forms). A named set is
evaluated once per query, the first time it is used, in the context of the slicer (`RolapNamedSetEvaluator`,
`RolapResult.evaluateExp`); an alias each time its AS is evaluated. The position of the current tuple follows
`Generate`, `Filter` and `Order` (which evaluates its keys in the order of the set, as `Sorter`). Of the 69 statements
that stopped at named sets, aliases and `Generate` 39 give eMondrian's answer; 2 fail in eMondrian too (#2, #358), 3
differ by eMondrian's native crossjoin (#155 and #169 in hierarchy order, #85 a memory-limit crossjoin of all customers
and products), the others stop at `OrderKey`, `Existing`, `MATCHES`, `IN`, `IS`, `DrilldownLevel`, `Ancestor(s)`, ...
Then the member functions: `Parent`, `FirstChild`, `LastChild`, `FirstSibling`, `LastSibling`, `NextMember`,
`PrevMember`, `Lag`, `Lead` (along the level, across parents), `Siblings`, `Ancestor`, `Ancestors`, `Ascendants`,
`Cousin`, `ParallelPeriod`, `PeriodsToDate` (both also without arguments, on the cube's time hierarchy), `Level`,
`Hierarchy`, `Dimension`, `Name`, `UniqueName`, `Caption`, `Ordinal` and `OrderKey` (an `OrderKey` value: calculated
members last, then by key, numbers as numbers, strings ignoring case first, keys of different kinds by unique name).
With them the null member of a hierarchy (`RolapHierarchy.getNullMember`, `[Hierarchy].[#null]`): what these functions
give where there is no member, also `Item` out of range; its cells are null and `{}` leaves out tuples with it. An
empty axis now writes the `HierarchyInfo` of its set type, as Mondrian's axis metadata does. 25 more statements give
eMondrian's answer; #41 differs by the order of eMondrian's native `NonEmptyCrossJoin` (as #155, #169).
Then the operators: `IN`/`NOT IN` and `MATCHES`/`NOT MATCHES` are Mondrian's user-defined functions (`InUdf`,
`MatchesUdf`, which `GlobalFunTable` adds to every schema), so the funtable generator now appends the UDF resolvers
(`UdfResolver`, resolved like a `SimpleResolver`). `MATCHES` is Java's `Pattern.matches`; NetWeaver 7.50 has POSIX
regular expressions only, so leading `(?i)` becomes case-insensitive matching and `\Q...\E` is escaped. `IS`
(`IsFunDef`: tuples member by member, else the same object), `IS NULL` (the null member), `IS EMPTY` (the cell of a
member or tuple), `Existing` (`ExistingFunDef`) and `Exists` (`ExistsFunDef`), both `FunUtil.existsInTuple`: a member
exists if it is on the hierarchy chain (ancestor, descendant or itself) of the member of its hierarchy in the context
(`Existing`) or in a tuple of the second set (`Exists`, else the default member). Other hierarchies of the same
dimension do not matter. A compound slicer's placeholder (`CompoundSlicerRolapMember.isOnSameHierarchyChain`) matches
the members of its slicer tuples, but Mondrian looks for the hierarchy in the first position of the first tuple only, so
under a slicer of tuples of two hierarchies nothing exists (eMondrian answers `{}`; the engine does the same). All 20
statements that stopped at them give eMondrian's answer.
Then the remaining functions, all 46 statements that stopped at one give eMondrian's answer but #64 (a sum's last
digits). `VisualTotals` (`VisualTotalsFunDef`): visual total members keep the unique name of the member they stand for,
so the engine finds their calculation by a `calc_name` of their own (`ZZXXMLA1_CL_MDX_SCHEMA_READER=>get_calculation`),
they are not calculated in the query and contain `Aggregate` (scoped solve order), `.Name` is the member's name, the
caption the pattern's; the evaluator's `set_context` compares `calc_name` too (Mondrian compares identity), else the
visual total of the default member never entered the context. `CurrentDateMember` (`CurrentDateMemberUdf`): the
query's date formatted (`ZZXXMLA1_CL_MDX_FORMAT=>format_date`: Calendar of en_US, weeks from Sunday, the week of
1 January is week 1) and looked up as `Util.lookupCompound` with a match type: BEFORE and AFTER take the closest sibling
by key, then the last or first child down. `Parameter` (`ParameterFunDef`): the default value, typed as a member or set
of the type argument's hierarchy. `DrilldownLevel` (this Mondrian appends the children after the whole set),
`AddCalculatedMembers`, `CalculatedChild`, `LastNonEmpty`, `.Properties` (the standard properties of
`RolapMemberBase.getPropertyValue`; `PropertiesFunDef` types a literal name), `Format`, `Mod`, `CInt` (null for a null
argument, as `JavaFunDef`), `CoalesceEmpty` and `CASE` (`CaseTestFunDef`, `CaseMatchFunDef`), with their resolvers.
The six NON EMPTY crossjoins that ended in memory dumps used up the roll memory of the whole instance when they ran
together (other sessions dumped with `SYSTEM_NO_ROLL`, ADT answered 503 and `ICMENOSESSION`); the engine now has
Mondrian's result limit (`mondrian.result.limit`, `Util.checkCJResultLimit`): a crossjoin larger than
`ZZXXMLA1_CL_MDX_ENGINE=>result_limit` (1,000,000 tuples) fails with "Size of CrossJoin result (n) exceeded limit (m)"
before it is built. More memory would only move the limit; a native NON EMPTY crossjoin would answer these queries.

Then the native crossjoin (`RolapNativeCrossJoin`, `CrossJoinArgFactory`, `SqlTupleReader`): while the evaluator is
non-empty (a NON EMPTY axis; `NonEmptyCrossJoin`, which also puts the slicer members of its hierarchies at All), a
`Crossjoin` or `NonEmptyCrossJoin` whose operands are Level.Members, Member.Children, Descendants(member, level or
depth) or an enumeration of stored members of one level is read from the facts: the combinations of the
operands' level keys with facts in the context, one grouped query (`ZZXXMLA1_CL_MDX_FACTS=>non_empty_paths`, cached
like the cells), ordered by hierarchy order, the first operand first. The context are the stored non-All members of
the other hierarchies that are not their hierarchy's default member (`makeContextConstraintSet`,
`removeCalculatedAndDefaultMembers`); a context with calculated members (an Aggregate or a compound slicer) is not
ported, the crossjoin is then evaluated as before. Other operands go through eMondrian's multi-variant expansion: each is
evaluated and split by level (in the order of their first member), every combination of the levels is read natively,
one after the other, the first operand slowest; this gives eMondrian's order of #41, #144, #155 and #169. Neither an
enumeration nor a level group has a bound on its members (our deviation: eMondrian drops the native read for an
enumeration of more than 1,000 members, `MaxConstraints`, and for a group of more than 15,000,
`MAX_MEMBERS_PER_OPERAND_STATE`, to keep its SQL `IN` list small; our read has no `IN` list, so the bounds would only
send Excel's `Hierarchize({DrilldownLevel({[X].[All X]})})` on a large level, or a long member list, to the interpreted
crossjoin and the result limit). So an enumeration of more than 1,000 members comes back in hierarchy order, as a
shorter one does, where eMondrian keeps the order it was written in. Not valid
(and so not native): all operands with the All member or empty, a calculated member, a calculated measure whose formula
names a member of an operand's hierarchy below none of its members. The seven crossjoins of the result limit answer
now (about 60,000 combinations instead of 16 million tuples). `Format` with the empty format string (a measure without
one) keeps the integer digit (Java's `#,##0.###`: 0.67, not .67).

Then the member properties of levels (2026-10-05). The reference schema had none (Excel's "Show Properties in Report"
offered nothing, eMondrian too listed no property): it now has FoodMart's, as `<Property sourceAttribute=...>` on the
Store Name level (Store Type, Store Manager, Store Sqft, Grocery Sqft, Frozen Sqft, Meat Sqft, Has coffee bar, Street
address) and on the customer Name level (Gender, Marital Status, Education, Yearly Income). The schema reads them
(`RolapLevel.createProperties`: the attribute's column and type), the model reads their columns with the members, the
schema reader keeps the values (`getPropertyFromMap`, case-insensitive) and finds a property of a level or a level above
(`Util.lookupProperty`, `isValidProperty`). `.Properties` gives the typed value (null for a property of a level above,
an error for any other name) and the validator types a literal name from the hierarchy's last level
(`deducePropertyCategory`); an identifier whose last segment is a property of the member or level before it is a
property call (`Util.lookup` with allowProp), so `[Store 14].[Store Sqft]` fails as in Mondrian ("No function matches
signature '<Member>.Store Sqft'") and `[Store].[USA].[Caption]` is the caption. `DIMENSION PROPERTIES
[Store].[Store Name].[Store Sqft]` (also `[Store Name].[Store Sqft]`) is olap4j's `MondrianOlap4jProperty`: listed in
the `HierarchyInfo` of its hierarchy without a type, written with `xsi:type` for the members that have a value; element
names are encoded as `XmlaUtil.encodeElementName` (`Store_x0020_Sqft`). `MDSCHEMA_PROPERTIES` lists them for
PROPERTY_TYPE 1 (the default), `DBSCHEMA_COLUMNS` as columns of their level. Eight `reference/` cases cover them
(`mdschema_properties_level`, `execute_level_properties_*`, `execute_properties_*`, `execute_property_*`).

Excel's label and value filters (recorded on eMondrian through `scripts/xmla-proxy.py`) are `Filter` in a subselect:
`Filter([Store].[Store Country].AllMembers, ([Store].CurrentMember.member_caption = "AAA"))`, with `<>`, `Left(...,n) =`,
`InStr(1, ..., "x") > 0`, `>= AND <=`, a measure (`[Measures].[Unit Sales] > 5`) and for Top 10 a
`Generate(... AS [XL_Filter_Set_0], TopCount(Filter(Except(DrilldownLevel(...)))))`. eMondrian refuses every one of
them: `addFilterToSubcubePredicates` accepts only `[Level].CurrentMember.Name/Caption/Key` compared by `=` or `<>`
(Excel writes the hierarchy and `member_caption`), and the Top 10 form fails with "MDX object '[XL_Filter_Set_0]' not
found". Ported 2026-10-12: `Filter` in a subselect is `addFilterToSubcubePredicates` (`ZZXXMLA1_CL_MDX_ENGINE=>
add_subcube_filter`: `=`, `<>`, `NOT`, `AND`, `OR`, `IsEmpty` of the current member's `Name`, `Caption`, `Key` or
`Properties(...)` against a literal, as a `VALUE` predicate on the level's column), and `MEMBER_CAPTION`/`MEMBER_NAME`
count as `Caption`/`Name` in olap4abap and in the reference (`scripts/patches/subcube-filter-member-caption.patch`), so
Excel's "equals"/"does not equal" label filters work. The current member of a hierarchy compares its lowest level
(`getCurrentMemberComparisonLevel`), so they work on flat hierarchies (the schema builder's), not on a level above the
lowest of a user hierarchy. Extended 2026-10-13 to all of Excel's label filters in both servers (comparisons,
between, begins/ends with, contains; `scripts/patches/subcube-filter-label.patch`, `label_predicate`; cases
`execute_subselect_filter_label_compare` and `_text`); value filters and Top 10 still fail as in the reference. One
deviation: a constant true condition (`1 = 1`) makes eMondrian fail with a NullPointerException
(`LiteralStarPredicate` has no column); olap4abap does not restrict the subcube.

Suggested next: the functions Mondrian's tests do not reach
(`StrToSet`, `StrToTuple`, `Extract`, `Cache`, ...); `checkDimensionFilter` (a native `Filter` operand). Re-running
`scripts/extract-mdx-tests.py` after the level properties found 13 more statements that run on eMondrian (appended as
#382-#394, the earlier indexes kept); all give eMondrian's answer now. For them: `OpeningPeriod`/`ClosingPeriod`
(`OpeningClosingPeriodFunDef`: without a member the time hierarchy's current member, without a level the one below the
member's, `getDescendant` by first or last child, Mondrian's check that level and member share a dimension), `Ytd`,
`Qtd`, `Mtd`, `Wtd` (`XtdFunDef`: `PeriodsToDate` at the cube's first time level of the type, `CubeBase.getTimeLevel`;
typed without arguments, "must belong to Time hierarchy"), `Subset` (`SubsetFunDef`). `CurrentDateMember` with BEFORE
or AFTER now gives the member it makes up for the search (`findBestMemberMatch`) a unique name, which orders keys of
another kind (`[All Weeklys]` against the years). The evaluator finds an infinite recursion as Mondrian does:
`setExpanding` records the calculation being expanded, `checkRecursion` runs once the stacks have grown by 16 commands
per hierarchy and finds an earlier state with the same context and calculation, and the message carries
`getContextString` (a frame per savepoint after which the context changed). For the same message the command stack has
Mondrian's widths and shape: `executeBody` records `setCellReader`, `executeStripe` takes a savepoint per tuple, a tuple
value takes its savepoint before its members and sets them in turn, and a tuple with a null member is null without
evaluation (`MemberArrayValueCalc`; before, `([Measures].[Foo], [Time].CurrentMember.FirstChild)` on a month looped).

## Later

- Done: compound slicer (a set of several tuples in WHERE); Mondrian aggregates over the slicer tuples
  (`RolapResult`, `CompoundSlicerRolapMember`).
- Done: `VisualTotals`, `CurrentDateMember`, `Parameter`, `LastNonEmpty`, `CASE`, `CoalesceEmpty`,
  `AddCalculatedMembers`, `.Properties`, and the result limit.
- The result limit is a class attribute; a setting (per system, like Mondrian's property file) would let it be changed
  without a transport.
- Done: the native NON EMPTY crossjoin. Not yet: its context constraint with calculated members (Aggregate members
  and compound slicers expanded, `expandSupportedCalculatedMembers`), native `Filter` and member lists
  (`RolapNativeFilter`, `SqlMemberSource`). Native `TopCount` is done (members pushed down, step 9).
