# Known issues

What olap4abap gets wrong, or answers differently, within the scope it has built: debt, not next steps. A feature
that is not built yet is no issue here; it is scope (`mvp-scope.md`) or a step (`next-steps.md`). An entry goes when
it is fixed. Read this before comparing answers with the reference or with BW.

## Debt

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
- **`clinic_test.py`'s "Text of two hierarchies on one axis" asks for a `Text` property the proposal no longer
  writes** (the key display gives captions and a property `Key`, no `Text` of the characteristic itself): it fails on
  `ZCLVISIT` and `ZCLVISITA` until it asks for a property the schemas have.

## Performance

Right answers, slower than they need to be; known, and waiting behind other priorities.

- **A calculated measure is evaluated per cell.** Excel's 1,001 x 1,001 grid on `ZXMLWIDEA` with a
  calculated measure spends nearly all of its time in the evaluator's pass over its 1,002,001 cells, and a NON EMPTY
  axis of such a query is filtered by the evaluator too (`filter_by_evaluator`). Fix: formulas per group
  (`next-steps.md`, Paused: query planning, step 7).
- **An unqualified member name (`[USA]`) is looked for in every hierarchy, one query each** (100 on `ZXMLWIDE`).
- **Members with facts on an aDSO read through the fact view.** The existence check of a member keyed by its value
  is `IN ( SELECT <key> FROM <fact view> )`, which joins the SID of each compounded characteristic; only a
  characteristic keyed by that SID needs it, every other one could read the aDSO's own table (`/BIC/A<aDSO>7`).
  Seen in Excel's filter list on `ZCLVISITA`.
- **Native `TopCount` and the native crossjoin give up on calculated members in the context.** Under a compound
  slicer (applicable #73, #297 to #301) or an `Aggregate` member they are evaluated as before
  (`expandSupportedCalculatedMembers` not ported).
- **An interpreted `Order` evaluates its sort values again in a second pass of a phase** (they are kept per run).
- **A large axis with member properties**: Excel's crossjoin of diagnoses and patients on COLUMNS of `ZCLVISITA`
  with 26 `DIMENSION PROPERTIES`: the engine (native crossjoin, `fast_cells`, `set_display_info`,
  `axis_properties`) and copying the 70 MB of axes as strings in `build` (they could go to the response in parts as
  the cells do).

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
- A label condition of a subselect `Filter` of a level's members (`<Level>.AllMembers`, Excel's label filters on any
  level) compares that level, where `<Hierarchy>.CurrentMember` stands for one of them; the reference compares the
  lowest level (`getCurrentMemberComparisonLevel`), so on an upper level of a user or BW hierarchy its subcube is
  wrong or empty. Its `InStr` (contains) ignores case as the evaluator's (`Vba.inStr`) and SSAS's do; the
  reference's subcube compares case (`subcube-filter-label.patch`). Cases `execute_subselect_filter_label_upper` and
  `execute_hier_excel_label_upper` take their answer from an equivalent member set.
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
    cell empty, the All member's too (olap4abap's answer: deliberate deviations above).

## BW's wrong answers

BW is the oracle of the analysis authorisations (`reference/auth/`, `mvp-scope.md`, BW's rules); where it answers
against its own rules, olap4abap does not follow it.

- **Leaves under a level-limited hierarchy line** (type 0 or 2; scenario H2LEAF, `CLINIC` to level 4; observed
  2026-11-12 with `scripts/auth_ask.py`, decided with the user the same day). BW refuses at reading the cells (with
  NON EMPTY or `Order` at the axis; "EYE 007 You do not have sufficient authorization") two kinds of query whose
  members are all inside the line:
  - an expansion that ends on leaves only: `GP.Children`, `Descendants(PRIMARY, 2)`, `Hierarchize` and `Order` of
    them, unions with them, at every key date (GP's physicians are at level 4, every one of them authorised as a
    node and as a value), while expansions whose target level holds nodes too pass (`INTMED.Children`,
    `Descendants(CLINIC, 3)` at 9999-12-31, `{GP.Children, INTMED.Children}`);
  - at a key date whose slice has a leaf inside the line that the slice of the line's date has below it, a set of
    two or more leaves containing it (2024-06-15: `{009, 010}`, `{001, 009}`, `Head(CARD.Children, 2)`), while the
    leaf alone passes (`{009}` on rows, `WHERE (009)`).

  The same members pass written otherwise: `Head(GP.Children, 6)`, `Filter(GP.Children, 1 = 1)`, `001.Siblings` and
  the explicit set give the six physicians with the same values. Under a type 1 or type 3 line nothing of this is
  refused (H1, HDATE, H3). olap4abap checks every member as a node of the key date's slice at its own depth, the
  rule BW applies to a single member and to every member under an unlimited line, so it allows these queries.
  `auth_check_test.py` and `bw_auth_compare.py` count such rows apart ("widened by BW": BW refuses at the cells or
  the axis, olap4abap allows, the user has a type 0 or 2 line on the row's hierarchy).
