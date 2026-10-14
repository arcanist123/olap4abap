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
  and eMondrian's answers as now.
- Unit tests of the planner's marking: one statement per row of the principle table and per item of "What needs the
  evaluator", each with its expected marks.
- Runtime and SQL count from the trace (`ZZXXMLA1_TRACE`) for the statement above, an Excel pivot on FoodMart and the
  1,001 x 1,001 grid on `ZXMLWIDEA` (25 s with `fast_cells`): one fact statement per combination of patterns is the
  target.

## Steps

1. The marking: `ZZXXMLA1_CL_MDX_PLANNER` (static, relational, computed per node), with unit tests; not used yet.
2. All-relational queries: the engine asks the plan, reads one grouped statement per combination of patterns
   (`GROUPING SETS` in `ZZXXMLA1_CL_MDX_FACTS`), filters the non-empty axes and places the cells from it; the
   switch; both test suites with it on and off.
3. Retire `non_empty_axis`' evaluator loop and the second and third reads of the statement above; measure.
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
