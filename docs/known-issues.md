# Known issues

What olap4abap gets wrong, or answers differently, within the scope it has built: debt, not next steps. A feature
that is not built yet is no issue here; it is scope (`mvp-scope.md`) or a step (`next-steps.md`). An entry goes when
it is fixed. Read this before comparing answers with the reference or with BW.

## Debt

- **The initial value has two names in one cube.** olap4abap's BW hierarchies
  (`ZZXXMLA1_CL_BW_HIERARCHY_COPY=>levels_sql`, `c_initial_name`) name a characteristic's initial value (SID 0) `#`,
  as BW's MDX does; the flat hierarchies on the characteristics' views name it by the view's value, `''` for a CHAR
  characteristic (`[ZCLDIAG].[]`), BW's value for the others (`0000`). Decided 2026-10-16: `''` everywhere, every key
  type, with `#` as the caption of a characteristic without texts (`next-steps.md`, Now: texts and captions).
- **The Discover cache does not see BW loads.** It is cleared by a change of a server file and the time master data
  fill, not when BW activates master data or loads a request: a Discover answer can be up to 12 hours old
  (`mvp-scope.md`, Discover cache decision; `next-steps.md`, Later).
- **A fixed reference characteristic is not filtered** (accepted 2026-10-13; the user disagrees long term): a
  reference characteristic (`0SOLD_TO` → `0CUSTOMER`) keeps its basic characteristic's unfiltered view, so it shows
  all members unless its dimension has members with facts; fixing a basic characteristic another characteristic of
  the provider references is refused. Fix: views per characteristic and selection (`next-steps.md`, Paused: fixed
  selections).
- **An aDSO's compounded characteristic stays keyed by its SID when all its compounding is fixed** (accepted
  2026-10-13; the user disagrees long term): one join to the SID table per such characteristic in the fact view,
  where its value would do. Fix: key it by its value and have `POST fix` rename the key attribute and what refers to
  it.
- **A label filter of Excel on a level above the lowest of a user hierarchy compares the lowest level**
  (`getCurrentMemberComparisonLevel`, as the reference does): the subcube is wrong there. Excel's label filters work
  on flat hierarchies (the schema builder's) and on the lowest level. The reference answers the same filter on a BW
  hierarchy's `Level 02` with every cell empty (below).

## Performance

Right answers, slower than they need to be; known, and waiting behind other priorities.

- **A calculated measure is evaluated per cell.** Excel's 1,001 x 1,001 grid on `ZXMLWIDEA` takes 108 s with a
  calculated measure, 3.5 s with the stored one: nearly all of it the evaluator's pass at about 100 µs per cell, and
  a NON EMPTY axis of such a query is filtered by the evaluator too (`filter_by_evaluator`). Fix: formulas per group
  (`next-steps.md`, Paused: query planning, step 7).
- **An unqualified member name (`[USA]`) is looked for in every hierarchy, one query each** (100 on `ZXMLWIDE`).
- **Members with facts on an aDSO read through the fact view.** The existence check of a member keyed by its value
  is `IN ( SELECT <key> FROM <fact view> )`, which joins the SID of each compounded characteristic; only a
  characteristic keyed by that SID needs it, every other one could read the aDSO's own table (`/BIC/A<aDSO>7`).
  Seen in Excel's filter list on `ZCLVISITA`.
- **Native `TopCount` and the native crossjoin give up on calculated members in the context.** Under a compound
  slicer (applicable #73, #297 to #301) or an `Aggregate` member they are evaluated as before, about 8 s each
  (`expandSupportedCalculatedMembers` not ported).
- **An interpreted `Order` evaluates its sort values again in a second pass of a phase** (they are kept per run).
- **A large axis with member properties**: Excel's crossjoin of diagnoses and patients on COLUMNS of `ZCLVISITA`
  with 26 `DIMENSION PROPERTIES` takes 3.7 s, of which the engine about 2 s (native crossjoin, `fast_cells`,
  `set_display_info`, `axis_properties`) and copying the 70 MB of axes as strings in `build` about 1.2 s (they could
  go to the response in parts as the cells do).

## Deliberate deviations

olap4abap answers differently on purpose; a comparison has to allow for these.

- `CREATE SESSION CUBE`, `CREATE SUBCUBE`, `ALTER CUBE`, `DROP CUBE` (Excel's grouping of members) are answered with
  a fault "... statements are not supported" before parsing; the reference gives a syntax error
  (`ZZXXMLA1_CL_XMLA_HANDLER=>unsupported_statement`).
- A level with `sourceAttribute` and a `captionColumn` of its own is refused: the reference ignores the
  `captionColumn` there and captions by the attribute's `NameColumn` (`RolapLevel.createFromXml`).
- A label condition of a subselect (`Filter` on `Name` or `Caption`, Excel's label filters) compares the level's
  name or caption column, as SSAS does; the reference compares its key column, so on a level keyed by the SID its
  answer is empty, everything or a cast error. Those cases take their answer from an equivalent member set
  (`execute_caption_subcube_*`, `capture-execute.py --answer-of`).
- A subselect `Filter` whose condition is a constant true (`1 = 1`) does not restrict the subcube; the reference fails
  with a NullPointerException (`LiteralStarPredicate` has no column).
- The native crossjoin has no bound on an enumeration (the reference's `MaxConstraints` 1,000,
  `MAX_MEMBERS_PER_OPERAND_STATE` 15,000): an enumeration of more than 1,000 members comes back in hierarchy order,
  where the reference keeps the order it was written in.
- `Aggregate` and a compound slicer of a member and a member below it count the lower one twice, as the reference
  does and as Microsoft specifies `Aggregate` for Sum; only Distinct Count would count it once.
- olap4abap reports itself as SSAS 2016 but names hierarchies as the reference does without SSAS naming
  (`[Time.Weekly]`, `[Time].[1997]`, not `[Time].[Weekly]`, `[Time].[Time].[1997]`). Excel only sends back the
  names it gets; hand-written SSAS MDX can fail (`next-steps.md`, Later: SSAS naming).

## The reference's wrong answers

Known faults of the reference server (eMondrian); its answer is not the oracle there.

- It sometimes answers "Internal Error null" while several statements run at once (applicable #2, #171, #237, #348
  in some runs), and #35 and #46 differed once in a parallel run: run such a statement again on its own.
- Applicable #2 and #358 fail in the reference too; #64 differs in the last digits of a sum its database adds in
  another order (`test-strategy.md`).
- A binary `-` in a subselect (`{All} - {member}`) is not understood (only Excel's unary `- {...}`).
- Waiting for SSAS, the spec for hierarchies and Excel's behaviour (decided 2026-10-16; the reference is not patched
  any more, `next-steps.md`, Reference scenario, step 6):
  - Expand Entire Field on a level hierarchy answers with duplicates (nested `DrilldownLevel(..., [Level 01])` to
    `[Level 03]` on `ZCLDIAG_ICD`: 203 tuples of 75 members);
  - Excel's Top 10 value filter is refused ("MDX object '[XL_Filter_Set_0]' not found");
  - a label filter on an upper level (contains `RESP` on `ZCLDIAG_ICD`'s `Level 02`, in a subselect) leaves every
    cell empty, the All member's too.
