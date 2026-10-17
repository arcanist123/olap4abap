# Master data of the time characteristics

The views of the characteristics (`ZZXXMLA1_CL_BW_VIEW_GEN`) take their members from the SID table (`/BI0/S...`),
their attributes from the attribute table (`/BI0/P...`) and their texts from the text table (`/BI0/T...`, English).
BW fills none of them for its calendar characteristics, so a time dimension shows only the periods that have data,
without `DATEFROM`, `DATETO`, `NUMDAY`, `NUMWDAY` or the year, month or quarter a period belongs to, and without texts
(its members' captions are blank). `ZZXXMLA1_CL_TIME_MD` fills all three for an interval; the page
`/zzxxmla1/schema/time.html` shows the state, lists the values each characteristic misses and fills them.

## What BW does (analysed on the 2025 system, 2026-10-07)

Transaction RSRHIERARCHYVIRT (function group `RSR_HIERARCHY_VIRT`, `RSR_HIERARCHY_VIRT_MAINTAIN`, dynpro 1000)
maintains the virtual time hierarchies. Its selections are kept in two places:

- **The time interval, factory calendar and fiscal period texts** are in the customizing table `RSADMINS`, row
  `CUSTOMIZID = 'BW'`, fields `HIERARCHYVIRTFR`, `HIERARCHYVIRTTO`, `FCALID`, `FISCPERTXTFLG`. They are read in the
  class constructor of `CL_RSR_HIERARCHY_VIRT` and written by `CL_RSR_HIERARCHY_VIRT=>SET_ADMIN_DATA`, a direct
  `UPDATE` under the lock of `RSCC_RSADM_ENQ_DEQ`. The update also invalidates the OLAP cache if the calendar changed
  and adjusts the hierarchies (`RRHI_VIRTUELL_HIER_CHANGE`). Without an interval the default is seven years back and
  ten ahead. On the development system: 1995-10-01 to 2029-12-31, calendar `01`.
- **The selected hierarchies** are not stored as a selection list. Each one is a BW hierarchy of its own: the node
  classes `CL_RSR_HIERARCHY_VIRT_NODE` (`SAVE`, `UPDATE`) create it with `CL_RSSH_TIMEHIERARCHY` (`RSHIEDIR`, its texts
  and levels) and register it with `RRHI_VIRTUELL_HIERARCHY_SAVE`. Deselecting one deletes it
  (`CL_RSSH_TIMEHIERARCHY=>DELETE`). `RSR_HIERARCHY_VIRT_ACTIVATE` does the same without the dynpro.

Neither touches the SID or attribute tables. The button *Recreate* on tab 1001 (`USER_COMMAND_1001`, OK code
`RECREATE`) calls `CL_RS_TIME_SERVICE=>REBUILD_TIME_MD_TABLES`, and that method fills less than its name suggests:

1. It sets `CHCKFL` in the SID tables of `0DATE`, `0CALWEEK`, `0CALMONTH`, `0CALMONTH2`, `0CALQUARTER`, `0CALQUART1`,
   `0CALYEAR`, `0FISCPER`, `0FISCPER3` and `0FISCYEAR`, but only for the SIDs that already exist.
2. It calls `INITIAL_FILL_TIME_MD_TABLES` only for `0DATE`, `0CALMONTH`, `0CALQUARTER` and `0FISCPER`
   (`IS_TIME_MD_TABLE_USABLE`), and only **if the characteristic has a navigation attribute**. In the standard every
   attribute of the time characteristics is a display attribute (`RSDBCHATR-ATTRITP = 'DIS'`), so nothing is filled.
3. Even when it runs, `INITIAL_FILL_TIME_MD_TABLES` writes the attribute rows of the SIDs that existed before the run
   and then creates the missing SIDs, for `0DATE` and `0CALMONTH` only (`0CALQUARTER` and `0FISCPER` are "to do"). The
   new SIDs get no attribute rows until a second run. `0CALYEAR` and `0CALWEEK` never get attribute rows.

**Texts** (analysed 2026-10-17): the text tables of `0CALMONTH`, `0CALQUARTER`, `0CALMONTH2`, `0CALQUART1`,
`0WEEKDAY1` and `0FISCYEAR` exist and are empty, and nothing in BW fills them. BW's queries do not read them for most
of these: the master data reader of a characteristic (`CL_RSMD_RS_FACTORY`) is a class of its own for `0CALMONTH`,
`0CALMONTH2`, `0CALQUART1`, `0WEEKDAY1` and `0FISCPER` (`CL_RSMD_RS_0CALMONTH`, ...), whose `GET_TEXT` makes the texts
when asked, in the logon language: the month names of `T247` with the year (`CL_RSMD_RS_0CALMONTH`: medium `JAN 1997`,
long `January 1997`), the weekday names of `T246` (short `MO`, medium and long `Monday`), the quarter from the text
pool of `SAPLRRSV` (`Q01` read into 10 places, `Q02` into 20: short `Q1`, long `Quarter 1`) and *Not assigned* (text
pool of `SAPLRSDM`, `001`) for the initial value. `0CALQUARTER` and `0FISCYEAR` have no such class: BW reads their
empty tables. `0CALYEAR`, `0CALWEEK` and `0HALFYEAR1` have no texts; `0FISCPER` has texts in its metadata but no
text table on the development system (its reader makes them).

So on the development system the attribute tables of `0CALYEAR`, `0CALQUARTER`, `0CALMONTH` and `0CALWEEK` hold only
the initial row. Their SID tables hold the values that FoodMart, the clinic demo and the SAP demo cube loaded.
`0HALFYEAR1` and `0WEEKDAY1` have no SIDs at all.

## What `ZZXXMLA1_CL_TIME_MD` fills

| Characteristic | SIDs | Attribute row |
| --- | --- | --- |
| `0CALYEAR` | every year of the interval | `DATEFROM`, `DATETO`, `NUMDAY`, `NUMWDAY` |
| `0CALQUARTER` | every quarter that overlaps it | the same and `CALYEAR`, `CALQUART1` |
| `0CALMONTH` | every month that overlaps it | the same and `CALYEAR`, `CALMONTH2` |
| `0CALWEEK` | every ISO week that overlaps it | `DATEFROM` (Monday), `DATETO`, `NUMDAY`, `NUMWDAY` |
| `0HALFYEAR1`, `0CALQUART1`, `0CALMONTH2`, `0WEEKDAY1` | all their values | no attribute table |
| `0FISCYEAR` | under K4 (below), every year of the interval, as `0CALYEAR` | `DATEFROM`, `DATETO`, `NUMDAY`, `NUMWDAY` of the calendar year |
| `0FISCPER` | under K4, every month of the interval as period 001 to 012, as `0CALMONTH` | the month's dates and days, `FISCYEAR`, `FISCPER3`; period 000 and the special periods only `FISCYEAR` and `FISCPER3` |

| Characteristic | Texts (English: short, medium, long as the table has them) |
| --- | --- |
| `0CALMONTH` | medium `JAN 1997`, long `January 1997` (as `CL_RSMD_RS_0CALMONTH`) |
| `0CALQUARTER` | short `Q3 1997`, long `Quarter 3 1997` (`0CALQUART1`'s with the year) |
| `0CALMONTH2` | medium `JAN`, long `January` |
| `0CALQUART1` | short `Q3`, long `Quarter 3` |
| `0WEEKDAY1` | short `MO`, long `Monday` |
| `0FISCYEAR` | under K4: medium `1997`, long `Fiscal year 1997` |
| the initial value of each | `Not assigned` |

- The interval is the one in `RSADMINS` (above) unless the request gives `from` and `to`. Nothing is written to
  `RSADMINS`; change BW's interval in RSRHIERARCHYVIRT. The schema proposal restricts the members of its time
  dimensions `0FISCYEAR` and `0FISCPER` to the same interval (`bw-schema-design-guide.md`, section 3.8, Fiscal time).
- The SIDs are made by BW (`RRSI_VAL_SID_CONVERT`, as `CL_RS_TIME_SERVICE` makes them: checked values for the
  characteristics with master data). The attribute rows are written here (`MODIFY` of the active version), and the
  values are computed as `CL_RS_TIME_SERVICE` computes them. `NUMWDAY` is the number of working days in the
  factory calendar of `RSADMINS` (`DATE_CONVERT_TO_FACTORYDATE`: the factory date of the last working day minus that
  of the first, plus one). It is 0 if the calendar does not cover the period.
- Attribute rows are written for every value with a SID, also one loaded outside the interval. Existing rows are
  replaced. Each characteristic is committed on its own, and one that fails (its SIDs) is rolled back and reported.
- **Fiscal characteristics** (added 2026-10-13): `0FISCYEAR` and `0FISCPER` are compounded with the fiscal year
  variant, so their values are the variant and the key (`K42024001`, shown `K4/2024001` on the page). They are filled
  the way `0CALYEAR` and `0CALMONTH` are, for the variant K4 only (`ZZXXMLA1_CL_TIME_MD=>c_fiscal_variant`, the one
  the schema builder proposes, `bw-schema-design-guide.md`, section 3.8): its fiscal year is the calendar year and
  its periods 001 to 012 are the months, so the values and dates are computed in ABAP from the interval, nothing is
  read from customizing, and the SIDs are made by the same `RRSI_VAL_SID_CONVERT`. Values of other variants that have
  a SID get no attribute rows. Only the regular periods are expected, but **BW's SID conversion of a period makes all
  periods of its fiscal year**, 000 and the special periods 013 to 016 included: K4 over the development system's
  interval has 595 period SIDs (35 years of 17), of which 420 are regular. A cube restricts its members to the regular
  periods (`olap4abap.members.0FISCPER`, the proposal's default). Period 000 and the special periods have no dates of
  their own: their attribute rows have the year and `FISCPER3`, no dates, 0 days. `0FISCPER3` and the other fiscal
  characteristics are not filled.
- **Tables the system does not have** (added 2026-10-14): not every system has the tables above (a characteristic
  that was never activated has none). Before reading or writing, each table is looked up as an active transparent
  table in the dictionary (`DD02L`, `missing_tables`). Without its SID table a characteristic is not active. The
  page shows it as "not active" and cannot select it, and a fill of it is an error that writes nothing. Without its
  attribute table it is filled like a characteristic without master data: SIDs only (not checked), and the fill
  answers a warning. `GET time` lists both cases per characteristic as `missingTables`.
- **Texts** (added 2026-10-17): written in English (`ZZXXMLA1_CL_TIME_MD=>c_language`, the language the views read)
  for every value with a SID and for the initial value (`Not assigned`, so the SID 0 member is captioned as in BW),
  with the wording of BW's readers (above), the names read from `T247`, `T246` and the two text pools in English.
  Existing rows are replaced. Only the text fields the table has are written. A characteristic whose text table the
  system does not have gets no texts, and the fill answers a warning. Values of another variant than K4 get none.
- **Missing values**: the state counts, per characteristic, the values of the interval without SID and the values of
  the interval or with a SID without attribute row or text row, counting only values this class can fill (since
  2026-10-17 a value of another fiscal year variant is no missing attribute row any more). `GET time/missing` lists
  them.
- Not filled: `0CALDAY` (no SID table of its own that the views use, `docs/schema-generator.md`).

**Filling changes the cubes' members.** Every view on these tables (the schemas of `ZFMSALESA`, the clinic demo,
...) then has every period of the interval as a member, with or without facts. The reference database holds copies of
the BW tables (`scripts/build-bw-reference-db.py`): rebuild it after a fill, or the comparisons with the reference
differ in the time dimensions.

## API and page

`ZZXXMLA1_CL_SCHEMA_API`, below `/zzxxmla1/schema/api/`:

- `GET time?from=YYYY-MM-DD&to=YYYY-MM-DD`: the interval (each date BW's if not given), the factory calendar and, per
  characteristic, `sids`, `attributes`, `expected` (values of the interval), `missingSids`, `missingAttributes` and
  the smallest and largest value with a SID, and with a text table (`textTable`) `texts` and `missingTexts`. The
  initial value (SID 0) is not counted.
- `GET time/missing?characteristic=0CALMONTH&from=...&to=...`: the values the characteristic misses, as the page shows
  them (`K4/2024001`): `sids`, `attributes` and `texts`, each `count`, `truncated` and the first 1,000 `values`. Refused
  (400): no characteristic, one the class does not fill.
- `POST time/fill?from=...&to=...&characteristics=0CALMONTH,0CALYEAR`: fills the characteristics (all without
  `characteristics`) and answers `filled` (per characteristic `createdSids`, `attributeRows`, `textRows`, `error`,
  `warning`) and the state
  afterwards. Refused (400): a date that is none, `from` after `to`, an interval longer than 100 years.

The page `time.html` (`web/schema/time.js`, linked from the schema builder and the MDX console) shows the state for
the interval (SIDs, attribute rows and texts), shows per incomplete characteristic its missing values ("Show
missing"), selects the incomplete characteristics and fills the selected ones after a confirmation.
`scripts/schema_api_test.py` checks `GET time`, `GET time/missing` and the refusals of `time/fill`; it does not fill.
`scripts/fiscal_default_test.py` needs the fiscal ones filled (it checks twelve periods for every fiscal year).
