# Known issues

What olap4abap gets wrong, or answers differently, within the scope it has built: debt, not next steps. A feature
that is not built yet is no issue here; it is scope (`mvp-scope.md`) or a step (`next-steps.md`). An entry goes when
it is fixed. Read this before comparing answers with the reference or with BW.

## Debt

- **Members of a level with `sourceAttribute` are named by their name, not their key.** The reference names
  `[ZCLDOC].[0]` (the key, `SID`) where olap4abap names `[ZCLDOC].[000]` (the `NameColumn`), on the same schema
  (`ClinicBW.xml` and SAP's `ZCLVISIT`, compared 2026-10-16). Every schema the proposal makes has such levels.
  Example: `SELECT {[Measures].[ZCLVISNO]} ON 0, Head([ZCLDOC].[ZCLDOC].Members, 3) ON 1 FROM [ZCLVISIT]`.
- **A measure's `caption` is not its caption in an Execute answer.** `ZCLVISNO` has `caption="Visits"`; the
  reference's axis shows `Visits`, olap4abap's `ZCLVISNO` (the schema reader reads the caption,
  `ZZXXMLA1_CL_SCHEMA`). Same example.
- **Aggregators other than `sum` and `count` are summed.** The schema accepts `min`, `max`, `avg` and
  `distinct-count`, and the fact reads (`ZZXXMLA1_CL_MDX_FACTS`) sum every measure but a count: a wrong value without
  an error. The proposal makes only `sum`; a hand-written schema can have the others. Until they are built, the
  schema should refuse them.
- **Calculated members of a schema are ignored**, silently (`<CalculatedMember>` of a cube; the schema builder does
  not offer them). Until they are built, the schema should refuse them.
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

## Deliberate deviations

olap4abap answers differently on purpose; a comparison has to allow for these.

- `CREATE SESSION CUBE`, `CREATE SUBCUBE`, `ALTER CUBE`, `DROP CUBE` (Excel's grouping of members) are answered with
  a fault "... statements are not supported" before parsing; the reference gives a syntax error
  (`ZZXXMLA1_CL_XMLA_HANDLER=>unsupported_statement`).
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
