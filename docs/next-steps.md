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
6. Open: the fiscal time characteristics in the time master data (`0FISCPER`, `0FISCYEAR`; not filled today,
   `time-master-data.md`): an aDSO's fact whose value has no SID has no `SID_<field>` and drops out of the engine's
   inner join.

Not done, decided: no hierarchy with the compounding as a level above (`[0FISCPER.Fiscal].[K4].[2024001]`), the
schemas are flat; no join on two generated string columns (HANA cannot use the columns, and the NUMC values are
numbers in the views but text in the facts); no SID columns for the characteristics without compounding (a join each,
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
lowest of a user hierarchy. The other label filters, value filters and Top 10 still fail as in the reference. One
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
