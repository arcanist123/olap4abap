# Query planning: SQL answers, the evaluator computes

Decided 2026-10-14 (`next-steps.md`, Now: query planning). The engine evaluates every axis and every cell through the evaluator, as the
reference does, although for most queries every value is a group of one SQL statement and everything else comes from
the schema. This note says which parts of a query need the evaluator, which are SQL, and how a planning step between
the validator and the engine sends each part to the right place.

## The problem, on one statement

Excel fills the filter list of a characteristic with

```mdx
SELECT NON EMPTY Hierarchize({DrilldownLevel({[Store].[All Stores]},,,INCLUDE_CALC_MEMBERS)})
  DIMENSION PROPERTIES PARENT_UNIQUE_NAME ON COLUMNS
FROM [ZFMSALES]
CELL PROPERTIES VALUE, FORMAT_STRING, LANGUAGE, BACK_COLOR, FORE_COLOR, FONT_FLAGS
```

On catalog `ZFOODMART` the answer has two positions, All Stores and USA, and two cells, each 266,773 (the default
measure Unit Sales, in the default member of Time, 1997); Canada and Mexico are members of Store Country without facts
in 1997, which `NON EMPTY` removes (olap4abap and eMondrian agree, checked 2026-10-14). What is dynamic in it: which
countries have facts and their sums. What is fixed by the schema: the members' names, captions and properties, the
format string, the font flags. What the engine does today:

1. `DrilldownLevel` under the non-empty evaluator reads the countries with facts (`context_members`, SQL over the
   facts).
2. `non_empty_axis` (the `NonEmpty(<axis>, {measures})` of `Query.compile`) sets each tuple in the context and calls
   `evaluate_current`: a pass that records the missed cells, `load_aggregations` (SQL over the facts), a second pass
   that finds them; evaluator calls whose only work is a cache lookup.
3. `fast_cells` reads the same sums again by pattern (`cross_values`, SQL over the facts unless a segment covers it)
   and `remove_empty_positions` drops the empty positions a third time.

Three answers to one question, "which groups of the facts exist and what are their sums", which one statement answers:

```sql
SELECT GROUPING_ID( s."ZFMCNTRY" ), s."ZFMCNTRY", SUM( f."/BIC/ZFMUNITS" )
  FROM <facts> f JOIN <store view> s ON s."SID" = f.<store SID>
  WHERE <Time's default member 1997, slicer, subcube, selections>
  GROUP BY GROUPING SETS ( ( s."ZFMCNTRY" ), ( ) )
```

The All member is not a calculation: it is the grouping set without the country column. Time has no All member, so
its default member is a condition of the statement, not a column.

## Principle

A cell whose members are plain (stored or All, not calculated, not null) and whose measure is stored is not
evaluated; it is a group:

| MDX                                   | SQL                                                                     |
|---------------------------------------|-------------------------------------------------------------------------|
| a stored measure                      | its aggregate: `SUM` (NULL is 0, as `load` reads it), `COUNT( * )`      |
| a member of a level                   | its level's key columns in `GROUP BY`, its keys in `WHERE`              |
| the All member, a hierarchy not named | the column left out of `GROUP BY`                                       |
| the cells of several levels           | `GROUPING SETS`, one set per level pattern; `GROUPING_ID()` tells them apart |
| an empty cell                         | no group (a group's sum is never NULL)                                  |
| the slicer, the subcube, selections   | `WHERE` (`set_subcube`'s predicate, the fact views of the selections)   |
| a compound slicer of plain tuples     | `WHERE` with the tuples `OR`ed (sum and count are additive over them)   |
| `NON EMPTY`, `NonEmpty(set, measures)`| the tuples whose group exists for one of the measures                   |
| `membersWithFacts`                    | the semi-join `member_table` already adds                               |
| hierarchy order                       | `ORDER BY` the order key columns (`ordered_paths` does it)              |

What is not in the facts is in the schema and the member reads: unique names, captions, `DIMENSION PROPERTIES`,
member properties, format strings of stored measures, `DisplayInfo` (children counts are a member read).

## What needs the evaluator

Only parts whose value is an expression:

1. Calculated members and measures (`WITH MEMBER`, the schema's `CalculatedMember`, `Aggregate`, `VisualTotals`):
   a formula over other cells, ordered by solve order. Its inputs are still groups; only the formula is computed.
2. Navigation inside a formula (`CurrentMember`, `Parent`, `PrevMember`, `ParallelPeriod`, `Ancestor`, ...): which
   cell the formula reads depends on the cell being computed.
3. Sets that depend on values (`Filter` on a value, `Order`, `TopCount`, `Rank`, `Generate` over them): the set needs
   values before the axis exists. Several are SQL already (`top_count`, `ordered_paths`); the rest are evaluated.
4. Cell properties that are expressions (`FORMAT_STRING = IIf(...)`, `FORE_COLOR`, `BACK_COLOR`, `FONT_FLAGS` of a
   calculated member), an error as the value of one cell, the recursion check.
5. Functions of members that read no facts (`Parent`, `Children`, `Lag`, `:`, `Descendants`, ...) are not
   evaluation of cells either: they are member reads and stay as they are.

So the evaluator stays, as the port of `RolapEvaluator`, for the computed parts. It stops being the way every cell is
reached.

## Design

### A planning step

Between `ZZXXMLA1_CL_MDX_VALIDATOR` and the engine, a planner walks the resolved tree and marks every node:

- **static**: answered by the schema and member reads (metadata, member sets that read no facts, properties, formats
  of stored measures);
- **relational**: answered by grouped SQL (stored measures at plain tuples, `NON EMPTY`, `NonEmpty`,
  `NonEmptyCrossJoin`, members with facts in the context, slicer, subcube, selections, the native `TopCount` and
  `Order` cases);
- **computed**: everything else, for the evaluator.

A node is relational only if all of its children are static or relational and no calculated or null member can reach
its context (the slicer's members, the default members of hierarchies without All, the axes' members). One computed
node makes its parent computed. The marking is the decision `fast_cells` makes today at run time, made once on the
tree before anything runs.

### The marking (step 1, done 2026-10-14)

`ZZXXMLA1_CL_MDX_PLANNER->plan( query )` takes the query as the validator resolved it, with the validator's schema
reader (which holds the query's calculated members), and keeps a mark per node in a table keyed by the node
reference: the tree (`ZZXXMLA1_CL_MDX_NODE`) is not changed. `get_mark( node )` reads it. Rules:

- Literals, levels, hierarchies, dimensions, stored and All members, and an argument left out are static; a
  calculated or null member is computed.
- Member reads are static (the highest mark of their arguments): `{}`, `()`, `CrossJoin`, `*`, set `+` and `-`, `:`,
  `Members`, `Children`, the navigation functions (`Parent`, `Lag`, `Ancestor`, `Cousin`, ...), `Descendants`,
  `Hierarchize`, `DrilldownLevel`, `DrilldownMember`, `Union`, `Except`, `Intersect`, `Head`, `Tail`, `Distinct`,
  `Subset`, `Item`, `Exists` of two sets, the metadata functions (`Name`, `UniqueName`, `Caption`, `OrderKey`,
  `Properties`, `Level`, ...), the time functions (`ParallelPeriod`, `PeriodsToDate`, `Ytd`, ...), `CurrentMember`
  and `CurrentDateMember`. The null member needs no rule: axes and the slicer are sets, and `{}` leaves out the tuples
  with it.
- `NonEmpty` of one set, `NonEmptyCrossJoin`, `TopCount`/`BottomCount` by a stored measure with a static count and
  `Order` whose keys are all `BASC`/`BDESC` on stored measures or `OrderKey` calls are relational (their value
  arguments are SQL, so they do not make the node computed); a stored member, tuple or hierarchy where a value is
  wanted is relational as an argument.
- Everything else is computed: operators, value functions, `IIf`, `CASE`, aggregates, `Filter`, `Generate`,
  `Existing`, `NonEmpty` with a second set (step 5), `VisualTotals`, functions not listed.
- A member, tuple or set node also knows whether a calculated member can be among its members: a calculated member,
  `AllMembers`, `AddCalculatedMembers`, `CalculatedChild`, `DrilldownLevel` with `INCLUDE_CALC_MEMBERS`, and the
  current member (also a hierarchy where a member is wanted), each when its hierarchy has a calculated member of the
  query; `VisualTotals` always. It passes up through member, tuple and set arguments.
- Context: when the slicer can hold a calculated member, relational nodes are computed.
- The plan: the slicer and each axis have the mark of their expression; the cells are computed when a calculated
  member can reach the context (the slicer or an axis), static when no cell property shows a value and no axis is
  NON EMPTY (`cells_needed`), else relational (`fast_cells`); a NON EMPTY axis is computed with computed cells, else at
  least relational; the query has the highest mark.

On the filter-list statement above the axis expression is static, the axis (NON EMPTY) and the cells relational.
A query whose axes are computed but whose cells are relational (a `Filter` on a value) is a mixed plan (step 4).

### Running a plan

- **All static and relational** (the statement above, Excel's member lists and filter lists, most pivot grids): the
  axes are member reads, their non-empty filter and the cells are one grouped statement per combination of level
  patterns, `GROUPING SETS` putting the patterns of one axis into one statement. The evaluator is not called.
  `NON EMPTY` removes the positions without a group; the cells are the groups put at their ordinals (`fast_cells`'
  placement). The axes need the group existence before the cell values, so the statement that filters the axes is the
  one that gives the cells: read once, used twice.
- **Mixed**: the relational nodes are read first, as one batch, into the cell cache (`ZZXXMLA1_CL_MDX_FACTS`'
  segments); the evaluator then computes the computed nodes and finds their inputs there, so a computed query needs
  no second phase for the cells it reads directly. The batching passes (`phase`) remain for inputs the plan cannot see
  in advance (navigation inside a formula).
- **All computed**: as today.

### What becomes of today's shortcuts

| Today                                        | In the plan                                                   |
|----------------------------------------------|---------------------------------------------------------------|
| `cells_needed`                               | a plan whose cells are static: no fact read                   |
| `fast_cells`                                 | the cell part of an all-relational plan                       |
| `context_members`, `non_empty_paths`         | relational member sets                                        |
| `native_top_count`, `native_order`           | relational set nodes (unchanged)                              |
| `non_empty_axis` with `evaluate_current`     | the same groups as the cells, no evaluator call               |
| `remove_empty_positions`                     | kept for mixed plans; for relational ones the groups decided  |
| `omitEmptyCells`                             | unchanged (writing the answer)                                |

### All-relational queries (step 2, done 2026-10-14)

- **One statement for all patterns.** `fast_cells` collects the combinations of a pattern of each axis first and
  passes them to `cross_values` in one call. The patterns no segment covers are one statement: `GROUP BY GROUPING
  SETS`, a set per pattern, `GROUPING_ID` over all the statement's level columns (the first argument the highest bit)
  telling them apart. A pattern's constraint is on its own grouped columns only, so the WHERE is the OR of the
  patterns' constraints: every fact of a group that meets its pattern's constraint passes it, and its value is
  exact. A group that does not meet it was read for another pattern, with only part of its facts, and is dropped.
  The groups go into the segments as `load_segment` keeps them. One pattern is read as before, and so is a
  statement of more than 62 columns (`GROUPING_ID` is a `BIGINT`). Every hierarchy of any set is joined, so a set
  that does not group by it still has the inner join; BW has master data for every value of a fact, so the join
  drops no row (as in the drill-through).
- **NON EMPTY by the cells.** The reference filters a NON EMPTY axis with `NonEmpty(set, {measures})` in the context
  of the slicer, then removes the positions whose cells are all empty. For stored measures a cell is non-empty
  exactly when its group has facts, whatever the measure. When every member of the other axes is the default
  member of its hierarchy or below it (All, for most), each non-empty cell lies inside the context NonEmpty sees.
  So the first filter keeps every position the second keeps, and the second alone gives the same axes.
  `axis_filter_needed` finds where that does not hold (a calculated measure among the query's measures, Time's
  default member 1997 with `[Time].[1998]` on another axis), and `non_empty_axis` filters those axes after they are
  evaluated. Axes evaluated once per root member of a hierarchy without All member keep the filter, because their
  merge depends on the filtered sets.
- **Compound slicer.** The placeholder's value is the roll-up (sum) of the tuples' cells, which equals one group
  over the ORed tuples when no fact is in two tuples. `compound_predicate` gives that predicate when the tuples are
  stored members, the measure is not among the varying hierarchies and every two tuples differ in a varying
  hierarchy where neither member is on the other's path. Its groups are read without the cache (the axes'
  evaluation reads without the predicate). Otherwise the evaluator rolls up as before.
- Unchanged: the axes' set evaluation, with its own fact reads under the non-empty evaluator (step 3), and the cells
  of every plan that is not relational.

### One read per group (step 3, done 2026-10-14)

- **The axes' reads feed the cells.** `ZZXXMLA1_CL_MDX_FACTS` answers a pattern from a finer one read before, as a
  segment cache rolls up (`roll_up`): an entry with every hierarchy of the pattern at the same or a deeper level and a
  segment that covers the constraint on these columns and constrains none of its others; its groups are summed by the
  pattern's columns (sum and count are additive; the finer read joins more dimension tables, which drops no fact in
  BW). So the All member's cell is the sum of the level a native set read, and a level's cells are the groups the axis
  read. `cross_values`, `value` and `load_aggregations` try it before a statement.
- **The default members the constraint leaves out.** The reference's context constraint drops the default members
  (`SqlConstraintUtils.removeCalculatedAndDefaultMembers`), so the countries of the filter list are read without
  Time's 1997, while its cells have it. For a relational query of one axis (filter and member lists) the read of the
  members with facts also sums the measures and counts the facts under the condition of those default members that
  are not All, in the same statement (`SUM( CASE WHEN <1997> THEN ... END )`, `non_empty_paths`' `defaults`), and keeps
  these groups as a segment of their own pattern: the filter list is then one fact statement, the cells none. With
  more axes the crossed patterns need a statement anyway and the extra join only slowed the reads down (the pivot of
  `planning_measure.py`: 256 ms with it, 185 ms without), so they are not read there.
- **No evaluator for NonEmpty.** The NON EMPTY axes that `axis_filter_needed` finds (`[Time].[1998]` on the other
  axis) are filtered by groups too: per pattern of the axis its group with the context's members of every other
  hierarchy (the context NonEmpty sees), read in the same `cross_values` call as the cells (`fast_cells`'
  `filter_axes`); a tuple without facts there is dropped with its cells (`drop_positions`). The evaluator stays for a
  calculated measure among the query's measures (a computed part, step 4), an axis on a hierarchy of the slicer, and
  as the fallback when `fast_cells` cannot place the cells.
- **Statements.** A set without constraint (the grand total) is read in a statement of its own: in the others' it
  removes their `WHERE`, and the grid's sets then returned 633,830 groups for 90,000 cells. A column constrained to
  every key of its level that has facts (known from a segment read without constraint) is not constrained (`widen`):
  the 1,001 x 1,001 grid's statement with two `IN` lists of 1,000 keys took 21.4 s, without them 0.9 s. Patterns of
  the same columns are one grouping set, and one grouping set is a plain `GROUP BY` (on the FoodMart InfoCube
  `GROUPING SETS` costs some 40 ms more than `GROUP BY` also from the plan cache: 48 ms against 8 ms).
- **ABAP.** `fast_cells` copied every axis per group (`FOR ... IN fast_axes`), 20 s of the 300 x 300 grid; each value
  is now written and formatted once per query; `ZZXXMLA1_CL_MDX_FORMAT`'s shortest digits take the 15-digit rounding
  of the double first and the logarithm of the double (`log10` of a `decfloat34` takes 130 µs): `xmla_double` 142 to
  4 µs, `format_number` 168 to 21 µs.

Measured with `python scripts/planning_measure.py` (the trace's runtime and SQL count and time, best of 3; before:
step 2, runtime only):

| statement                                   | before                  | after                         |
| ------------------------------------------- | ----------------------- | ----------------------------- |
| filter list (one axis)                      | 175 ms, 2 fact reads    | 148 ms, 6 statements, 1 fact read |
| Excel pivot (Product drilled x Customers)   | 196 ms                  | 185 ms, 15 statements         |
| `NON EMPTY` states with `[Time].[1998]`     | 134 ms                  | 122 ms, 7 statements          |
| 1,001 x 1,001 grid on `ZXMLWIDEA`           | ICM timeout (> 5 min)   | 17.1 s, 8 statements, 0.9 s SQL |

The grid's 17 s are ABAP: about 7 s to turn 632,000 rows into groups and values (`ZZXXMLA1_CL_SQL=>query` 0.7 s,
`load` 2 s, the rest the values), 5 s to place them, and writing the 119 MB answer. The schema is annotated
`omitEmptyCells`: the answer has the 633,830 cells with a value only (of 1,002,001) and 2,002 members, the cells
118.6 MB, some 187 characters each (value, format string and font flags, indented). `compare-applicable.py`: SAP 196 to 216 s in total (271 s at step 2).

## Semantics that must not change

- Empty is "no group", not 0: a stored measure whose group sums to 0 is a cell with 0, written, and `NON EMPTY` keeps
  it.
- Aggregators: sum and count are what the model has; sum and count are additive, so a compound slicer and the All
  member are `OR` and a grouping set. A distinct count (not in the model) would still be SQL, never summed from
  children, which `GROUPING SETS` gives for free.
- Hierarchies without All member (Time): their default member is a `WHERE` on its keys, as `base_filters` in
  `fast_cells`.
- `membersWithFacts`, selections (filter and members mode), subcube predicates and compound slicers apply to every
  statement the plan sends, as they apply to `value` and `non_empty_paths` now.
- The result limit (`result_limit`) is checked before a crossjoin is built, also when its tuples come from SQL.
- A group's pattern is its `GROUPING_ID()`, never a NULL or empty column: BW's blank member has the key `''`, as an
  aggregated column reads through ADBC.
- Positions are in hierarchy order and `Hierarchize` is the order of the member reads.
- A query whose plan is relational gives the answer the evaluator gives: same positions, same cells, same formats,
  same `DisplayInfo`.

## Verification

- A switch (class attribute, as `result_limit`) turns planning off; the two runs of `python scripts/xmla_test.py` (244
  cases) and `python scripts/compare-applicable.py` (395 statements) must give the same answers with it on and off,
  and eMondrian's answers as now. Since step 3 the engine's unit test `planning_on_and_off` compares the two in one
  run, and the suites run with planning on.
- Unit tests of the planner's marking: one statement per row of the principle table and per item of "What needs the
  evaluator", each with its expected marks.
- Runtime and SQL count from the trace (`ZZXXMLA1_TRACE`) for the statement above, an Excel pivot on FoodMart and the
  1,001 x 1,001 grid on `ZXMLWIDEA` (25 s with `fast_cells`): one fact statement per combination of patterns is the
  target.

## Steps

1. Done (2026-10-14): the marking: `ZZXXMLA1_CL_MDX_PLANNER` (static, relational, computed per node), with unit
   tests.
2. Done (2026-10-14): all-relational queries: the engine asks the plan, reads one grouped statement for all
   combinations of patterns (`GROUPING SETS` in `ZZXXMLA1_CL_MDX_FACTS=>cross_values`), filters the non-empty axes
   and places the cells from it; the switch `ZZXXMLA1_CL_MDX_ENGINE=>planning`; both test suites with it on and off
   (`next-steps.md`, query planning step 2). See All-relational queries (step 2) below.
3. Done (2026-10-14): `non_empty_axis`' evaluator loop retired for relational plans, the axes' reads feed the cells;
   measured. See One read per group (step 3) above.
4. Mixed queries: the relational inputs of computed nodes read as one batch before the first pass.
5. More set nodes relational: `Filter` on a stored measure (`RolapNativeFilter`), `NonEmpty` with a second set.

## GROUPING SETS on HANA

`GROUPING SETS` with many patterns (an Excel grid with several levels per axis) against one statement per pattern,
measured 2026-10-14 with `scripts/grouping_sets_probe.py` (ADBC through `ZZXXMLA1_CL_SQL=>query`, the wide
aDSO's reporting view, 1,000,000 records; best of 5 runs in random order, each statement new text so that no
cache answers it). HANA runs `GROUPING SETS` and `GROUPING_ID( ... )` through ADBC, and all three forms give the
same groups. A blank key comes back as `''` like the aggregated column, so only `GROUPING_ID` tells them apart.

| case                                          | groups  | grouping sets | union all | a statement per pattern |
| --------------------------------------------- | ------- | ------------- | --------- | ----------------------- |
| one level and All (1,000)                     | 1,001   | 35 ms         | 83 ms     | 53 ms (2)               |
| grid 2 levels, both totals, slice of ~1,000   | 2,287   | 37 ms         | 35 ms     | 105 ms (4)              |
| grid 1,000 x 1,000, both totals               | 633,830 | 1,138 ms      | 1,189 ms  | 1,643 ms (4)            |
| level of 100,000 and All                      | 99,997  | 191 ms        | 342 ms    | 307 ms (2)              |
| 6 patterns of 3 levels, ~50,000 records       | 149,394 | 345 ms        | 351 ms    | 595 ms (6)              |

`GROUPING SETS` is never slower, and the gain grows with the number of patterns, mostly from fewer compilations
and round trips (about 25 ms per statement); on the big grid the transfer of the rows dominates. Unexplained: the
first `GROUPING SETS` run of a case was sometimes much slower (179, 990, 1,567 ms) while the other forms' first
runs were not.

## Open

- Mixed plans and the batching passes: how much of `phase` remains once the relational inputs are read first.
- `GROUPING SETS` has a fixed cost on the FoodMart InfoCube (some 40 ms more than `GROUP BY`, also from the plan
  cache), which the wide aDSO did not show; a statement per pattern may be cheaper there when HANA's plan cache
  answers. Measure on a real provider before relying on either.
- The grid's ABAP (groups to values, placement, writing the answer) is now its cost, not SQL.
- `fast_cells` formats every value although the query may not ask for `FORMATTED_VALUE`: Excel's grid asks for
  `VALUE, FORMAT_STRING, LANGUAGE, BACK_COLOR, FORE_COLOR, FONT_FLAGS` only. Format only when the cell properties
  show the formatted value.
