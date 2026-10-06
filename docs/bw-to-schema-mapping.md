# Mapping SAP BW to Mondrian's model

Analysed on system `a4h_http` using the demo cube `0D_NW_C01` (7,005 fact rows) against FoodMart's `Sales` cube.
Table and column names below were read from the system, not assumed.

The analysis used the SAP demo cube because it existed first. The project's main data source is now the generated
FoodMart cube `ZFMSALES` (see `environment.md`), which is what the mapping must be verified and implemented against.
Differences from the demo cube: names are flat attributes (CHAR 60) in `/BIC/P...`, not BW texts, so there are no `T`
tables; time is the plain characteristic `ZFMDATE` (`YYYY-MM-DD`) with flat attributes, not `0CALMONTH`; its tables
should use the customer namespace `/BIC/` instead of `/BI0/` (not yet checked on the system).

## BW layout of a HANA-optimised InfoCube

- Fact table `/BI0/F<cube>` (e.g. `/BI0/F0D_NW_C01`): one `SID_<characteristic>` column per characteristic (type `RSSID`),
  one column per key figure, one key column `KEY_<cube>P` for the package dimension (technical, ignore).
  There is no E table and no dimension tables. (Non-HANA cubes have F and E tables and DIM tables.)
- Per characteristic `<C>`:
  - `/BI0/S<C>`: SID table, key = the characteristic value, column `SID` = integer surrogate key (SID 0 = "not
    assigned"). Time characteristics, e.g. `/BI0/SCALMONTH`, key is `CALMONTH` (`YYYYMM`).
  - `/BI0/P<C>`: time-independent master data attributes, key = value + `OBJVERS` (read only `'A'`).
  - `/BI0/Q<C>`: time-dependent attributes (`DATETO` in key, `DATEFROM`) - out of MVP scope.
  - `/BI0/T<C>`: texts (`TXTSH`, `TXTMD`, language `LANGU` unless the characteristic is language independent).
  - `/BI0/X<C>`: SID table for navigational attributes (`S__<attr>` columns) - not needed with the view approach below.
  - `/BI0/H<C>`: external hierarchies (`HIEID`, `NODEID`, `PARENTID`, `CHILDID`, `NEXTID`, `TLEVEL`) - out of scope.
- Metadata tables: `RSDCUBE` (cubes), `RSDDIMEIOBJ` (cube dimension -> InfoObject), `RSDKYF` (key figures),
  `RSDCHABAS` (characteristic properties), `RSDBCHATR` (attributes; `ATRTIMFL = 1` means time dependent),
  `RSDCHA`, `RSHIEDIR` (hierarchy directory), `RSDIOBJ` (InfoObject types: CHA, KYF, TIM, UNI, DPA, XXL).
  Always filter `OBJVERS = 'A'`.

## Mapping

| Mondrian | BW |
|---|---|
| Cube fact table | `/BI0/F<cube>` |
| `<Dimension foreignKey=...>` | fact column `SID_<char>` |
| Dimension table primary key | `SID` of `/BI0/S<char>` |
| Level column | attribute column of `/BI0/P<char>` (time-independent only) |
| `nameColumn` / caption | `/BI0/T<char>` text columns |
| `<Property sourceAttribute=...>` (member property of a level) | an attribute of the characteristic (a display attribute in BW terms); in `ZFMSALES` FoodMart's properties of Store Name and of the customer Name level, the attributes keep their attribute hierarchies |
| `<Measure aggregator="sum">` | key figure with SUM / SUM |
| Time levels | derived from `/BI0/SCALMONTH` etc. (`YYYYMM` -> year, quarter, month) |
| `<Dimension type="TimeDimension">`, `levelType` | any dimension the user marks as time (the proposal marks none; the standard BW time characteristics `0CAL*`, `0FISC*` are dimensions on their views like any other characteristic and suggest their level type); every level and attribute gets a time level type (`TimeYears`, `TimeQuarters`, `TimeMonths`, `TimeWeeks`, `TimeDays`, else `TimeUndefined`), as Mondrian requires in a time dimension (`schema-generator.md`, Time) |

Mondrian only needs a foreign key in the fact table and a single-column primary key in the dimension table. BW SIDs are
exactly such surrogate keys (FoodMart itself uses integer surrogate keys).

Verified join (returns correct per-category, per-month totals on the demo cube):

```sql
SELECT p~d_nw_prdct, m~calmonth, SUM( f~d_nw_netv ) AS netv
  FROM /bi0/f0d_nw_c01 AS f
  INNER JOIN /bi0/sd_nw_prod AS s ON s~sid = f~sid_0d_nw_prod
  INNER JOIN /bi0/pd_nw_prod AS p ON p~d_nw_prod = s~d_nw_prod AND p~objvers = 'A'
  INNER JOIN /bi0/scalmonth AS m ON m~sid = f~sid_0calmonth
  GROUP BY p~d_nw_prdct, m~calmonth
```

## Modelling: one generated view per characteristic

Implemented by `ZZXXMLA1_CL_BW_VIEW_GEN` (decision in `mvp-scope.md`): a DDIC-based CDS view per characteristic of a
cube, so that the schema needs no SQL and the engine sees an ordinary flat dimension table keyed by SID, like
FoodMart's `store` or `customer`, without snowflake handling. BW-specific parts live in one generated place:

- the SID table `/BIC/S<char>` joined with the attribute table `/BIC/P<char>` on the key, `OBJVERS = 'A'`;
- columns: `SID` (the key of the view), the key and every time-independent attribute (`OBJVERS`, `CHANGED` and the SID
  flags left out), named without their namespace (SAP objects: `/BI0/` tables, fields have no namespace); the table
  names come from BW (`RSD_CHKTAB_GET_FOR_CHA_BAS`), and a characteristic without attribute table gets a view of its
  SID table alone; a reference characteristic (`RSDCHA-CHABASNM` differs, `0SOLD_TO` -> `0CUSTOMER`) has no tables of
  its own: its view, under its own name, is on the basic characteristic's tables and key field (and attributes);
- NUMC columns as numbers: `INT4` up to 9 digits, `INT8` up to 18, `DEC(31,0)` beyond; other columns as they are;
- named by a number (decided 2026-10-06; a characteristic name does not fit, and one in a namespace such as
  `/1BW/D01` has slashes): database view `ZZXXMLA1V` + 7 digits, DDL source `ZZXXMLA1_C` + the same digits. The
  source's description (`BW characteristic <char>: SID with active attributes`) names the characteristic; the view
  of a characteristic is found by it. A view keeps its number when generated again, a new one gets the next free
  number. An active source can rename neither itself nor its database view, so a source of another name (the older
  `ZZXXMLA1_C_<char>`) or with a view name of another form is deleted and created again under its number.

Run it with `sapcli class execute ZZXXMLA1_CL_BW_VIEW_GEN` (generates the views of `ZFMSALES`: `ZZXXMLA1V0000001`
ZFMPROD, `...2` ZFMCUST, `...3` ZFMSTORE, `...4` ZFMPROMO, `...5` ZFMDATE). In HANA each is a plain SQL view
(`SYS.VIEWS`, row view) of the same name. Not yet: texts (`/BIC/T<char>`, needs a language), time characteristics
without attribute table, navigation and time-dependent attributes. CDS views are not exported by
`scripts/sap-sync.sh pull`; the generator in `src/` is their source.

## Schema generator

See `schema-generator.md`: the generator proposes a schema for an InfoCube or a cube-type aDSO (fact table
`/BIC/A<adso>7`), the user edits it in the UI under `/zzxxmla1/schema`, and acceptance generates the views and saves the
schema file.
