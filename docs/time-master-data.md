# Master data of the time characteristics

The views of the characteristics (`ZZXXMLA1_CL_BW_VIEW_GEN`) take their members from the SID table (`/BI0/S...`) and
their attributes from the attribute table (`/BI0/P...`). BW fills neither for its calendar characteristics, so a time
dimension shows only the periods that have data, without `DATEFROM`, `DATETO`, `NUMDAY`, `NUMWDAY` or the year, month
or quarter a period belongs to. `ZZXXMLA1_CL_TIME_MD` fills both for an interval; the page
`/zzxxmla1/schema/time.html` shows the state and fills them.

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

- The interval is the one in `RSADMINS` (above) unless the request gives `from` and `to`. Nothing is written to
  `RSADMINS`; change BW's interval in RSRHIERARCHYVIRT.
- The SIDs are made by BW (`RRSI_VAL_SID_CONVERT`, as `CL_RS_TIME_SERVICE` makes them: checked values for the
  characteristics with master data). The attribute rows are written here (`MODIFY` of the active version), and the
  values are computed as `CL_RS_TIME_SERVICE` computes them. `NUMWDAY` is the number of working days in the
  factory calendar of `RSADMINS` (`DATE_CONVERT_TO_FACTORYDATE`: the factory date of the last working day minus that
  of the first, plus one). It is 0 if the calendar does not cover the period.
- Attribute rows are written for every value with a SID, also one loaded outside the interval. Existing rows are
  replaced. Each characteristic is committed on its own, and one that fails (its SIDs) is rolled back and reported.
- Not filled: the fiscal characteristics (`0FISCPER`, `0FISCYEAR`, ...: compounded with the fiscal year variant, their
  values depend on it) and `0CALDAY` (no SID table of its own that the views use, `docs/schema-generator.md`).

**Filling changes the cubes' members.** Every view on these tables (the schemas of `ZFMSALESA`, the clinic demo,
...) then has every period of the interval as a member, with or without facts. The reference database holds copies of
the BW tables (`scripts/build-bw-reference-db.py`): rebuild it after a fill, or the comparisons with the reference
differ in the time dimensions.

## API and page

`ZZXXMLA1_CL_SCHEMA_API`, below `/zzxxmla1/schema/api/`:

- `GET time?from=YYYY-MM-DD&to=YYYY-MM-DD`: the interval (each date BW's if not given), the factory calendar and, per
  characteristic, `sids`, `attributes`, `expected` (values of the interval), `missingSids`, `missingAttributes` and
  the smallest and largest value with a SID. The initial value (SID 0) is not counted.
- `POST time/fill?from=...&to=...&characteristics=0CALMONTH,0CALYEAR`: fills the characteristics (all without
  `characteristics`) and answers `filled` (per characteristic `createdSids`, `attributeRows`, `error`) and the state
  afterwards. Refused (400): a date that is none, `from` after `to`, an interval longer than 100 years.

The page `time.html` (`web/schema/time.js`, linked from the schema builder and the MDX console) shows the state for
the interval, selects the incomplete characteristics and fills the selected ones after a confirmation.
`scripts/schema_api_test.py` checks `GET time` and the refusals of `time/fill`; it does not fill.
