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
- `NonEmpty` (also with a second set, step 6), `NonEmptyCrossJoin`, `TopCount`/`BottomCount` by a stored measure
  with a static count, `Order` whose keys are all `BASC`/`BDESC` on stored measures or `OrderKey` calls and `Filter`
  whose condition SQL answers (`filter_condition`, step 6) are relational (their value arguments are SQL, so they do
  not make the node computed); a stored member, tuple or hierarchy where a value is wanted is relational as an
  argument.
- Everything else is computed: operators, value functions, `IIf`, `CASE`, aggregates, `Filter` of another
  condition, `Generate`, `Existing`, `VisualTotals`, functions not listed.
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
A query whose axes are computed but whose cells are relational (a `Filter` on a value) is a mixed plan (step 5).

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
  more axes the crossed patterns need a statement anyway and the extra join only adds to the reads, so they are not
  read there.
- **No evaluator for NonEmpty.** The NON EMPTY axes that `axis_filter_needed` finds (`[Time].[1998]` on the other
  axis) are filtered by groups too: per pattern of the axis its group with the context's members of every other
  hierarchy (the context NonEmpty sees), read in the same `cross_values` call as the cells (`fast_cells`'
  `filter_axes`); a tuple without facts there is dropped with its cells (`drop_positions`). The evaluator stays for a
  calculated measure among the query's measures (a computed part, step 5), an axis on a hierarchy of the slicer, and
  as the fallback when `fast_cells` cannot place the cells.
- **Statements.** A set without constraint (the grand total) is read in a statement of its own: in the others' it
  removes their `WHERE`, and the grid's sets then returned 633,830 groups for 90,000 cells. A column constrained to
  every key of its level that has facts (known from a segment read without constraint) is not constrained (`widen`):
  the 1,001 x 1,001 grid's statement had two `IN` lists of 1,000 keys before. Patterns of the same columns are one
  grouping set, and one grouping set is a plain `GROUP BY` (GROUPING SETS on HANA, below).
- **ABAP.** `fast_cells` copied every axis per group (`FOR ... IN fast_axes`); each value is now written and
  formatted once per query; `ZZXXMLA1_CL_MDX_FORMAT`'s shortest digits take the 15-digit rounding of the double first
  and the logarithm of the double only where that is not enough (`log10` of a `decfloat34` is expensive).

Statements with `python scripts/planning_measure.py` (the trace's SQL count; measurements stay in `.local/`): the
filter list (one axis) 6 statements, 1 fact read (2 before); the Excel pivot (Product drilled x Customers) 15; `NON
EMPTY` states with `[Time].[1998]` 7; the 1,001 x 1,001 grid on `ZXMLWIDEA` 8, and it answers now (before, the ICM
cut it off).

The grid's time is ABAP: turning 632,000 rows into groups and values (`ZZXXMLA1_CL_SQL=>query`, `load`, the values),
placing them, and writing the 119 MB answer. The schema is annotated
`omitEmptyCells`: the answer has the 633,830 cells with a value only (of 1,002,001) and 2,002 members, the cells
118.6 MB, some 187 characters each (value, format string and font flags, indented).

### Cells first (step 4, decided 2026-10-14)

The 1,001 x 1,001 grid (Excel's PivotTable of two characteristics, `planning_measure.py`'s `wide_grid`) runs 8
statements, most of its time outside SQL. Its axes are read first, as the reference evaluates them: per axis the
members with facts (`DrilldownLevel`'s context members: a grouped fact read, then a member read with an `IN` list of
all 1,000 keys) and, at the end, a count of them; then the cells statement groups the facts by both levels (631,829
rows). Everything the axis reads give is in the cells statement's result: the members with facts on one axis are the
keys among its groups (the other axis covers its whole level and All), the totals are sums of its groups (sum and
count are additive), and the members' keys are its keys. Decided with the user: such a query is one fact statement,
and its axes are built from the result, not read before it. Filters, ranks and the like come later; they are most
likely SQL too (steps 5 and 6).

What the query needs:

| step             | work                                                                                   |
| ---------------- | -------------------------------------------------------------------------------------- |
| read the facts   | one statement, 631,829 rows                                                            |
| build the axes   | the distinct keys of each axis (1,000) in hierarchy order, a position per key          |
| place the cells  | ordinal = position on axis 0 + position on axis 1 x 1,001; totals summed in one pass   |
| write the answer | a `<Cell>` per row in ordinal order, 119 MB                                            |

Today the same rows pass four layers, each with its own per-row allocations (method trace): `load` builds a string
key per group into the hashed group cache, `cross_values` splits each key back into a paths table, `fast_cells` finds
each axis' position by a string-keyed hash read and fills a cell table of 1,002,001 rows, a third of them empty, and
the writer walks that table and builds each cell's XML from pieces.

The plan of such a query (planner and engine):
- **When.** Every NON EMPTY axis is a set whose members depend on the facts only: a level's members, `Children`,
  `DrilldownLevel`, `Descendants` of members of the model, crossjoins of these, under NON EMPTY with stored measures
  only; no calculated member, no `Filter`, `TopCount`, `Order` on values (later steps); additive aggregators. An axis
  without NON EMPTY keeps the members without facts and is read from the dimension as now.
- **The statement.** The patterns of the axes' combinations as now (`GROUPING SETS` for the totals, or the totals
  summed in ABAP from the finest pattern: to measure), constrained only where an axis is not a whole level.
- **The axes.** Each axis' positions from the distinct keys of the result, in hierarchy order (the engine's member
  order stays authoritative: the keys are mapped to positions once in ABAP; `DENSE_RANK( ) OVER ( ORDER BY <order
  column> )` in the statement is the alternative). Its members are made from the keys where the level's name is its
  key; otherwise one member read per axis by the keys of the result.
- **The cells.** Rows to cells without a cell table: each row's ordinal from its positions, the value written once per
  distinct amount (as now). With `ORDER BY` the second axis' position, then the first's, the rows come in
  `CellOrdinal` order and are written as they are read.

The answer's text (compared 2026-10-14 with `python scripts/answer_text_probe.py`: 633,830 cells with Excel's cell
properties, made up in the program, each variant giving the UTF-8 bytes of `CellData`): today's `cell_xml` (pieces,
lines joined once, converted to UTF-8), one string template per cell joined once, the same joined and converted per
10,000 cells with the xstrings appended or kept in a table, the sXML writer (`CL_SXML_STRING_WRITER`, token calls,
no indentation; 87.3 MB against 119.7 MB), a simple transformation in the answer's shape (a throwaway one in
`$TMP`) and `CALL TRANSFORMATION id` of the cell table (asXML, a bound only, not the answer's format).

Decided (2026-10-14): one string template per cell, converted to UTF-8 in parts of 10,000 cells, the parts a table
of xstrings that the endpoint appends to the response (`append_data`), nothing joined. A simple transformation does
not fit: the cell properties are dynamic (which elements, the value type, empty cells: a `tt:cond` for each), and
sapcli's checkout and checkin know no transformations, so it would be an object the sync cannot carry.

Done (part 1, 2026-10-14): `ZZXXMLA1_CL_XMLA_MDDATASET=>build` returns the answer as UTF-8 parts (the head with the
Session element the handler gives it, the cells by 10,000, the tail), each cell's elements one template each; the
handler passes them on in `ty_result-parts`, the endpoint appends them (`append_data`), the trace gzips them as
binary. Not one string of the whole answer any more, so no `set_cdata` conversion and no `with_session` replace over
it. The trace's runtime now includes the conversion to UTF-8, which `set_cdata` did after it before. Part 2 is the cells-first
path itself: rows to positions and ordinals, without the group cache and the cell table.

Done (part 2, 2026-10-14): `ZZXXMLA1_CL_MDX_ENGINE=>cells_first`, after the slicer, instead of the axes, NON EMPTY
and cells phases (phase `Cells first` in the trace and the console's query plan).
- **When** (`grid_axes`): the plan is relational, no hierarchy without All member is evaluated per root member, the
  query has no formula, at most two axes (`ZZXXMLA1_CL_MDX_FACTS=>c_max_grid_axes`), each NON EMPTY and, also inside
  `Hierarchize` or braces, `DrilldownLevel({the All member})` (Excel's form with `INCLUDE_CALC_MEMBERS` where the
  hierarchy has no calculated member), `Level.Members` or the All member's `Children`, of a level of at most three
  key columns (`c_max_grid_levels`); the context (slicer of one tuple, default members) has no calculated or null
  member and a stored measure. Any other query runs as before; crossjoins, `Descendants`, filters and ranks on an
  axis are later steps.
- **The statement** (`ZZXXMLA1_CL_MDX_FACTS=>grid`): the facts grouped by the axes' levels, `GROUPING SETS` with
  each axis' All member aggregated (one plain `GROUP BY` without All members), the measure of the context (or
  `COUNT( * )`) and the fact count; the context's non-All members of the other hierarchies (Time's 1997, the slicer)
  as `WHERE`, and the subcube. Fetched typed (`ZZXXMLA1_CL_SQL=>fetch`, the new reader of a typed table): the
  `GROUPING_ID` as `int8`, three key columns per axis, the amount as text. Not the group cache: nothing else reads it.
- **The axes**: per axis the distinct paths of the grouping set that groups by it alone (else the finest), read as
  members with `get_members_by_paths`, the All member first, `hierarchize`d: the engine's member order, as decided.
  NON EMPTY keeps every position then (each has a group with facts), so no axis is filtered.
- **The cells**: `ty_result` has `cell_values` (the distinct cells, the first the empty one with the measure's format
  string) and `cell_refs` (per ordinal its cell's index), instead of `cells`; `cells_of` gives them as cells (the unit
  tests). Each row's ordinal from its axes' positions (a hashed read per axis, the All member's position where its
  set aggregates the axis), its value written and formatted once per distinct amount text. The writer writes each
  distinct cell's elements once and then one template per ordinal.
- **Statements**: the filter list one fact statement as before, the grid one. Rejected: `DENSE_RANK( ) OVER ( ORDER
  BY ...)` per axis in the statement for array positions (it costs HANA more than the reads it saves), and numeric
  keys as array indexes (not worth a special case). The rows are fetched typed, not into a structure of string
  columns read with `ASSIGN COMPONENT`.

### Cells first of an outline (done 2026-10-17)

Excel's expanded members on a BW hierarchy: `Hierarchize(DrilldownMember({{DrilldownMember({{DrilldownLevel({All},,,
INCLUDE_CALC_MEMBERS)}}, {m1},,,INCLUDE_CALC_MEMBERS)}}, {m2, m3},,,INCLUDE_CALC_MEMBERS))`, every click on a plus
sign one more level of nesting. The per-function path read it with a facts read and a member read per
`DrilldownMember`, then the cells a statement per level of the hierarchy (`bw_pattern`): 29 statements on
`0D_NW_C01` (rows four levels deep against the sales groups), each new statement text (a drill to new members)
compiled anew by HANA. Now one statement gives both axes and the cells (`ZZXXMLA1_CL_MDX_ENGINE=>outline_first`, our
extension, phase `Cells first`): 14 statements; the answer is the same, byte for byte.
- **When** (`outline_axes`, after `grid_axes` declined): as cells first, but each axis (at most two) is a set of
  factors (`outline_factors`): the operands of its crossjoin (`CrossJoin`, `*`, Excel's form for several fields on
  one axis) or the set alone, each an outline (`outline_axis`: `Hierarchize` of nested `DrilldownMember`, without
  `RECURSIVE`, down to `DrilldownLevel({the All member})` of a BW hierarchy, the second sets literal members) or a
  grid axis of a hierarchy that is no BW hierarchy; at least one outline, each hierarchy once, at most six factors
  (`ZZXXMLA1_CL_MDX_FACTS=>c_max_outline_factors`). The slicer restricts any number of dimensions (filters of the
  statement, BW hierarchies' members too); a compound slicer (Excel's filter of several members) is its predicate
  (`compound_predicate`, `add_predicates`), its hierarchies' placeholders left out of the filters. A subselect is
  the subcube predicate as everywhere; not with one that names members of a BW hierarchy of an axis
  (`restrict_to_subcube`), nor where a member is given twice (`DrilldownMember` would repeat its children).
- **The outline** is known before any read: the All member, the first level and the children of each expanded
  member. A member of a second set is expanded only if the set its `DrilldownMember` drills holds it: on the first
  level or its parent expanded by an inner `DrilldownMember` (the same holds under the non-empty evaluator: a member
  without facts has children without facts).
- **The statement** (`ZZXXMLA1_CL_MDX_FACTS=>outline`): the facts joined to each outline's members of all levels
  (since 2026-10-18 `ZZXXMLA1_CL_MODEL=>fact_join_closure`: the facts grouped by the closure's `ANCESTOR_SID` of the
  outline's members and the grid, the members joined to the groups, `docs/next-steps.md` step 9; before:
  `fact_join_members`, each member joined to the closure by its own SID, the key of its deepest
  level, so a fact joins each member it is below once and a member's value is the sum over its distinct values),
  grouped by the members' columns, `GROUPING SETS` over the grid hierarchies where they have their All member. An
  outline's All member comes from the facts without its closure: a branch (`UNION ALL`) per combination of the
  outlines joined and aggregated (2^n for n outlines, each outline's members a `WITH o1 AS ...` of its own), so a
  fact joins each combination of members it is below once. No member is summed from others, as for `bw_pattern`.
  The groups carry the members' columns (`ZZXXMLA1_CL_MODEL=>member_columns`), so the members are made from them
  (`ZZXXMLA1_CL_MDX_SCHEMA_READER=>remember_row`) without a member read.
- **The axes and cells** as in cells first: each factor's members with facts hierarchized, the All members first,
  each group's value at its positions. An axis' tuples are the combinations of its factors' members with facts,
  ordered by their positions (the crossjoin of the factors, each hierarchized).
- **Several outlines and dimensions** (added 2026-10-18): Excel's pivot on `ZCLVISITA` with the diagnoses' outline on
  columns and the physicians' on rows, under a service node of `ZCLSERV_CAT`, took the per-function path, 36
  statements (10 of them the cells, a statement per pair of levels: `bw_pattern`); now 16, the cells and both axes
  one statement, the same answer, byte for byte. Three outlines with a characteristic (2 x 2 factors): 57 to 15.
  `scripts/outline_first_test.py` asks such statements (several fields per axis, slicers of several dimensions,
  compound slicers, subselects) of both clinic catalogs on this path and on the per-function path and compares.
- **A crossjoin on the other axis** (added 2026-10-18): Excel's pivot on `0D_NW_C01` with the products' outline on rows
  and `CrossJoin` of the sales groups and calendar years on columns took the per-function path, 29 statements
  (four of them compiled anew per drill); now 13 statements (one compile of the outline statement), the same answer.
- **Not yet**: the Resolve phase still looks up each member of the MDX with a statement of its own (6 on
  `0D_NW_C01`) and the Finish phase counts children for `DisplayInfo` a statement per level (6). An outline on a
  level hierarchy, more than two axes, a crossjoin of grid axes without an outline (cells first takes one grid
  axis per axis), a subselect naming members of a BW hierarchy of an axis, a compound slicer `compound_predicate`
  declines (tuples that share facts) or Excel's Expand Entire Field (nested `DrilldownLevel`) take the per-function
  path. Of `ssas_compare.py`'s 36 statements 13 take this path.

### Mixed queries (step 5, done 2026-10-15)

A query with a calculated measure or member keeps the evaluator for its cells (`execute_stripe`), pass after pass
until a pass misses no cell (`phase`). On Excel's 1,001 x 1,001 grid of `ZXMLWIDEA` with a calculated measure as the
slicer (`WITH MEMBER [Measures].[Double] AS [Measures].[ZXMLAKF] * 2 ... WHERE [Measures].[Double]`) the cells
statement had both `IN` lists of 1,000 keys (`load_aggregations` did not `widen`), and the evaluator made two passes
over 1,002,001 cells, the first of which only recorded the misses.

- **The misses as one batch.** `ZZXXMLA1_CL_MDX_FACTS=>load_aggregations` reads the batches of a pass that no finer
  entry rolls up with one `load_sets` call (one statement, `GROUPING SETS` for several patterns), each constraint
  widened first (`widen`), as `cross_groups` reads; before, a statement per pattern with every key.
- **The direct inputs before the first pass.** `ZZXXMLA1_CL_MDX_ENGINE=>prefetch_cells`, before the first pass of
  the evaluator's cells (planning on): per combination of a pattern of each axis the groups of its tuples' stored
  members with the context's non-All members, all with one `cross_groups` call. A group holds every measure's sum,
  so a formula that reads stored measures of its own cell (`[Store Sales] - [Store Cost]`, `[ZXMLAKF] * 2`) finds
  them in the first pass, which is then the only one. Tuples with a calculated or null member other than a measure
  are left out (an `Aggregate` member reads its children), and nothing is read when the context or the slicer has
  one (a compound slicer's placeholders). What a formula reads elsewhere (`([Unit Sales], [Time].[1997].[Q1])`,
  navigation) is still missed and read between the passes, as one batch. The read is not exact: a formula that
  never reads its own cell makes it a read too many; accepted, a grouped read is cheap next to a pass.
- Not changed: the NON EMPTY axes of a query with a calculated measure are still filtered by the evaluator
  (`filter_by_evaluator`, its own passes), and the axes' computed sets (`Filter` on a value) are evaluated as before.

The grid now runs 8 statements and one evaluator pass, which is nearly all of its time (per cell: savepoints, the formula, each stored
measure's group key and lookup, the format string, the double written, a row of the cell table): computing such a
formula per group instead of per cell is step 7. Tests: `planning_on_and_off` compares three
mixed statements with planning on and off and reads the mixed grid's facts once; `xmla_test.py` 272 of 274 (the
two datasources cases), `compare-applicable.py` 394 of 395 (#64).

### Set nodes by groups (step 6, done 2026-10-15)

- **`Filter` in SQL** (`RolapNativeFilter`, `ZZXXMLA1_CL_MDX_ENGINE=>native_filter`): a crossjoin (`CrossJoin` or `*`)
  of a level's members (`Members`, `Children`, `Descendants`), or one such operand, filtered by a condition SQL
  answers is one statement: `ordered_paths` with the condition as a `WHERE` on the grouped values of its measures in
  the context (the stored non-All members of the other hierarchies), in hierarchy order. The condition
  (`ZZXXMLA1_CL_MDX_PLANNER=>filter_condition`, used by the marking and the engine alike) is a part of
  `RolapNativeSql`'s: `AND` and `OR` of comparisons of numbers made of stored measures, decimal numbers, `+`, `-`
  and `*`. The reference sends any condition its compilers know to SQL, also where SQL's answer is not MDX's; here
  only a condition that is false for every tuple without facts: a comparison with an empty side is false
  (`BooleanNull`), `*` is empty with one empty side, `+` and `-` only with two, `AND` is false with one false side,
  `OR` with two. The join keeps only tuples with facts, so the answer is the evaluator's, whether the evaluator is
  non-empty or not. Not native: `NOT`, `IsEmpty`, division, a constant side of `OR`, `IIf`, names and captions,
  calculated measures, member lists, a calculated or null member in the context, a calculated member of the query in
  a hierarchy of the set. Like the reference, the crossjoin is not checked against the result limit, only the tuples
  kept.
- **`NonEmpty` by groups** (`non_empty_groups`): `NonEmpty(set [, set])` keeps the tuples of the first set whose
  group with a tuple of the second set (none: the context) and the context's members of the other hierarchies has
  facts. All groups are one `cross_groups` call (a pattern per pair of a left and a right pattern, the second set's
  hierarchies overriding the first's), then each pair's group is looked up by key; no evaluator call. The evaluator
  stays where a tuple or the context holds a calculated or null member, or the cell's measure is calculated.

`planning_measure.py` has each of these statements by groups and by the evaluator (`*_evaluated`, the same answer:
`NOT (NOT (...))`, a calculated measure equal to the stored one): `Filter` of the 10,281 customers by Unit Sales >
300, `Filter` of `ZXMLAD00`'s 100,000 members by `ZXMLAKF`, `NonEmpty` of the customers with `{([Product].[Dairy],
[Unit Sales])}`. The rest of the native `Filter` on `ZXMLWIDEA` is the member read by the paths of the kept members
(18 statements) and the answer; of `NonEmpty`, the 10,281 customers' read and the cells. Tests: the engine's
`native_filter_and_non_empty` (each native statement against its evaluated twin), the planner's marks;
`xmla_test.py` 272 of 274 (the two datasources cases), `compare-applicable.py` 394 of 395 (#64; #353 differed once in
the parallel run, the same alone and with its neighbours).

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
- The MDX console's Query plan tab (Trace SQL on) shows a statement's marks and which element read which SQL
  (`ZZXXMLA1_CL_MDX_EXPLAIN`); the same is in the trace (`GET trace/entry`, `explain` and each statement's `node`).
- Runtime and SQL count from the trace (`ZZXXMLA1_TRACE`) for the statement above, an Excel pivot on FoodMart and the
  1,001 x 1,001 grid on `ZXMLWIDEA`, kept in `.local/`: one fact statement per combination of patterns is
  the target.

## Steps

1. Done (2026-10-14): the marking: `ZZXXMLA1_CL_MDX_PLANNER` (static, relational, computed per node), with unit
   tests.
2. Done (2026-10-14): all-relational queries: the engine asks the plan, reads one grouped statement for all
   combinations of patterns (`GROUPING SETS` in `ZZXXMLA1_CL_MDX_FACTS=>cross_values`), filters the non-empty axes
   and places the cells from it; the switch `ZZXXMLA1_CL_MDX_ENGINE=>planning`; both test suites with it on and off
   (`next-steps.md`, query planning step 2). See All-relational queries (step 2) below.
3. Done (2026-10-14): `non_empty_axis`' evaluator loop retired for relational plans, the axes' reads feed the cells;
   measured. See One read per group (step 3) above.
4. Done (2026-10-14) for two axes of a level each: a query whose NON EMPTY axes depend on the facts only is one fact
   statement, its axes built from the result and its cells written from the rows, without the axis reads, the group
   cache, the cell table. See Cells first (step 4) above.
5. Done (2026-10-15): mixed queries: the misses of a pass read as one batch (widened), the cells' inputs in their own
   context read before the first pass. See Mixed queries (step 5) above.
6. Done (2026-10-15): more set nodes relational: `Filter` on stored measures in SQL (`RolapNativeFilter`), `NonEmpty`
   (also with a second set) by groups. See Set nodes by groups (step 6) above.
7. Formulas per group: a calculated measure of arithmetic on stored measures of its own cell computed per group,
   first in ABAP from the groups, later as SQL for the simple operators (`next-steps.md`, query planning step 7).

## GROUPING SETS on HANA

`GROUPING SETS` with many patterns (an Excel grid with several levels per axis) against one statement per pattern,
tried 2026-10-14 with `scripts/grouping_sets_probe.py` (ADBC through `ZZXXMLA1_CL_SQL=>query`, the wide aDSO's
reporting view, 1,000,000 records; each statement new text so that no cache answers it; results in `.local/`): one
level and All (1,001 groups), a grid of 2 levels with both totals on a slice (2,287), the grid 1,000 x 1,000 with
both totals (633,830), a level of 100,000 and All (99,997), 6 patterns of 3 levels (149,394), each as `GROUPING SETS`,
`UNION ALL` and a statement per pattern. HANA runs `GROUPING SETS` and `GROUPING_ID( ... )` through ADBC, and all three
forms give the same groups. A blank key comes back as `''` like the aggregated column, so only `GROUPING_ID` tells
them apart.

Decided (2026-10-14): `GROUPING SETS`, one statement per query: fewer statements to compile and fewer round trips,
and the reads stay simple; one grouping set stays a plain `GROUP BY`. Not to be revisited before a real provider
shows it matters.

## Open

- Mixed plans (after step 5): a calculated measure whose formula is arithmetic of stored measures of its own cell is
  still evaluated per cell (nearly all of the computed grid's time); it could be computed per group, in ABAP from the groups or as
  a SQL expression of the grouped statement. The NON EMPTY filter of a query with a calculated measure still runs
  the evaluator.
- Cells first beyond a level per axis: crossjoins of levels (Excel's rows of two characteristics), `Descendants`, a
  NON EMPTY axis of a non-All member's children, and an axis without NON EMPTY (its members without facts from the
  dimension). The grid's remaining time: the statement, rows to cells, the writer.
- (Before step 4) The grid's ABAP (groups to values, placement, writing the answer) is now its cost, not SQL: step 4. A cell's value is
  formatted only when the query asks for `FORMATTED_VALUE` (`want_formatted`; Excel's grid asks for `VALUE,
  FORMAT_STRING, LANGUAGE, BACK_COLOR, FORE_COLOR, FONT_FLAGS`). Fewer copies per group and the answer
  joined once (229d1cf).
