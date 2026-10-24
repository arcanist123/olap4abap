# Master data of the time characteristics

The views of the characteristics (`ZZXXMLA1_CL_BW_VIEW_GEN`) take their members from the SID table (`/BI0/S...`),
their attributes from the attribute table (`/BI0/P...`) and their texts from the text table (`/BI0/T...`, English).
BW fills none of them for its calendar characteristics, so a time dimension shows only the periods that have data,
without `DATEFROM`, `DATETO`, `NUMDAY`, `NUMWDAY` or the year, month or quarter a period belongs to, and without texts
(its members' captions are blank). `ZZXXMLA1_CL_TIME_MD` fills all three for an interval; the page
`/zzxxmla1/schema/time.html` shows the state, lists the values each characteristic misses and fills them.

## What BW does (observed on the 2025 trial system, 2026-10-07, 2026-10-17 and 2026-10-23)

Transaction RSRHIERARCHYVIRT maintains the virtual time hierarchies. What it keeps:

- **The time interval, factory calendar and fiscal period texts** are in the customizing table `RSADMINS`, row
  `CUSTOMIZID = 'BW'`, fields `HIERARCHYVIRTFR`, `HIERARCHYVIRTTO`, `FCALID`, `FISCPERTXTFLG`. On the development
  system: 1995-10-01 to 2029-12-31, calendar `01`. Without an interval olap4abap takes seven years back and ten ahead,
  its own default.
- **The selected hierarchies** are not stored as a selection list: each one is a BW hierarchy of its own, a row of
  `RSHIEDIR` with its texts and levels; deselecting one deletes it.

Neither fills the SID or attribute tables, and the button *Recreate* on its second tab does not either: after it the
SID tables of the time characteristics hold the same values as before (marked checked, `CHCKFL`), and the attribute
tables of `0CALYEAR`, `0CALQUARTER`, `0CALMONTH` and `0CALWEEK` hold only the initial row. Every attribute of the
time characteristics is a display attribute there (`RSDBCHATR-ATTRITP = 'DIS'`).

**Texts**: the text tables of `0CALMONTH`, `0CALQUARTER`, `0CALMONTH2`, `0CALQUART1`, `0WEEKDAY1` and `0FISCYEAR`
exist and are empty, and nothing in BW fills them. BW's MDX (`BAPI_MDDATASET_*`, the members with their short, medium
and long text, properties `1`, `5` and `4` of the characteristic; asked 2026-10-23, English) shows texts all the same:

| Characteristic (provider) | Caption, short, medium | Long |
| --- | --- | --- |
| `0CALMONTH` (`ZFMSALESA`) | `JAN 1997` | `January 1997` |
| `0CALQUARTER` (`ZFMSALESA`) | `Q1 1997` | `Quarter 1 1997` |
| `0CALMONTH2` (`0D_FC_C01`) | `FEB` | `February` |
| `0CALQUART1` (`0D_FC_C01`) | `Q1` | `Quarter 1` |
| `0FISCPER` (`0D_NW_C01`, K4; no text table) | `January 2010` | `January 2010` |
| `0CALYEAR` (`ZFMSALESA`) | caption and short `1997`, no medium | none |
| `0CALWEEK` (`ZFMSALESA`) | caption and short `01.1997`, no medium | none |

BW makes these texts itself: with rows of the four text tables deleted and others changed to a marker, it showed the
same texts, while a changed text of the clinic's site (`/BIC/TZCLSITE`, the control) showed at once. The initial
value of a characteristic of ours is captioned *Not assigned* (`[ZCLSITE].[#]`). `0WEEKDAY1`, `0HALFYEAR1` and
`0FISCYEAR` are on no provider with facts here and were not observed; the texts olap4abap writes for `0WEEKDAY1`
(`MO`, `Monday`, from `T246`) and `0FISCYEAR` (`Fiscal year 1997`) are its own choice.

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
| `0CALMONTH` | medium `JAN 1997`, long `January 1997` |
| `0CALQUARTER` | short `Q3 1997`, long `Quarter 3 1997` (`0CALQUART1`'s with the year) |
| `0CALMONTH2` | medium `JAN`, long `January` |
| `0CALQUART1` | short `Q3`, long `Quarter 3` |
| `0WEEKDAY1` | short `MO`, long `Monday` |
| `0FISCYEAR` | under K4: medium `1997`, long `Fiscal year 1997` |
| the initial value of each | `Not assigned` |

- The interval is the one in `RSADMINS` (above) unless the request gives `from` and `to`. Nothing is written to
  `RSADMINS`; change BW's interval in RSRHIERARCHYVIRT. The schema proposal restricts the members of its time
  dimensions `0FISCYEAR` and `0FISCPER` to the same interval (`bw-schema-design-guide.md`, section 3.8, Fiscal time).
- The SIDs are made by BW (`RRSI_VAL_SID_CONVERT`: checked values for the characteristics with master data). The
  attribute rows are written here (`MODIFY` of the active version), with the values the attributes' names and
  descriptions define. `NUMWDAY` is the number of working days in the
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
  with the wording BW's queries show (above), the month and weekday names read from `T247` and `T246` in English.
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
