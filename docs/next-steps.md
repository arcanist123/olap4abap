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
four minutes; the slowest on SAP are #85 (79 s) and #46 (77 s), then #116 (24 s); everything else is below 15 s.

## Now: the schema generator

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
   `ZZXXMLA1_CL_WEB_APP`, uploaded with `scripts/sap-files.py app`, checked with `scripts/schema_ui_test.py`.
   Then (2026-10-06) removing a catalog (`POST remove`, Remove… on the start page; checked end to end with a
   throwaway catalog). One cube per catalog for the MVP (`mvp-scope.md`, Catalog decision).
   Open: an accept through the UI checked by hand (the API's accept was); calculated members of the schema (the
   reader ignores them) and aggregators other than `sum`/`count` (the engine sums them) are not offered.

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
found". Supporting them goes beyond the reference; decided separately.

Suggested next: the performance of #85 and #46 (one minute each); the functions Mondrian's tests do not reach
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
  and compound slicers expanded, `expandSupportedCalculatedMembers`), native `Filter`, `TopCount` and member lists
  (`RolapNativeFilter`, `RolapNativeTopCount`, `SqlMemberSource`).
