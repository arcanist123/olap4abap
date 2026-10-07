# Designing olap4abap schemas for SAP BW cubes

A guide for BW developers who write or review the schema of a cube served by olap4abap. Example throughout: the SAP
demo InfoCube `0D_NW_C01` on the development system `a4h_http`. The rules were worked out on 2026-10-07/08 with two
demo catalogs on that system, `NWCOMPANY` and `NWPRODUCT`, whose schemas and views are in
[examples/bw-schema/](examples/bw-schema/).

**The decision: model a cube as BW models it.** A characteristic is a dimension, a navigation attribute is a field of
its own under it, a display attribute is a property, nothing is nested that BW does not nest. Everything is identified
by BW's technical names and keys; texts are captions and properties. Users see technical keys by default; that is a
deliberate trade-off for identifiers that never change, and texts can be added for display later (section 3.4).

Scope:

- **Format:** Mondrian 3 schema XML with eMondrian's attribute extensions (`DimensionAttribute`), as eMondrian
  9.3.0-emondrian.38 defines it. The Mondrian 4 metamodel (`PhysicalSchema`, `MeasureGroup`) is not supported.
- **Providers:** HANA-optimised InfoCubes and cube-type aDSOs.
- **Master data:** time-independent and time-dependent attributes and texts, read as one snapshot: the record valid on
  the key date 9999-12-31, texts in language EN. External BW hierarchies (`/BI0/H...`) are out of scope.
- Analysis authorisations are out of scope.

Related documents: [bw-to-schema-mapping.md](bw-to-schema-mapping.md) (the BW tables), [schema-generator.md](schema-generator.md)
(the generator and its UI), [mvp-scope.md](mvp-scope.md).

## 1. The rules at a glance

| BW | Schema | MDX name | Excel shows |
|---|---|---|---|
| Characteristic `0D_NW_CODE` | `Dimension name="0D_NW_CODE"` with one flat `Hierarchy` (All + one level) | `[0D_NW_CODE]` | Company |
| Characteristic value (internal key) | member, keyed by the SID, named by the key | `[0D_NW_CODE].[1111]` | 1111 |
| Text (EN) | member property `Text` | `.Properties("Text")` | Company Name (via *Show Properties*) |
| Navigation attribute switched on in the provider | flat `Hierarchy name="0D_NW_CODE__0D_NW_CNTRY"` in the characteristic's dimension | `[0D_NW_CODE.0D_NW_CODE__0D_NW_CNTRY]` | Country of Company |
| Display attribute, or navigation attribute not switched on in the provider | member properties (key and text) of the characteristic's level | `.Properties("0D_NW_CNTRY")` | Country, Country Name |
| Reference characteristic (`0D_NW_SHIP` -> `0D_NW_CUST`) | a dimension of its own on the basic characteristic's view | `[0D_NW_SHIP]` | Ship-to Party |
| Key figure `0D_NW_NETV` | `Measure name="0D_NW_NETV"` | `[Measures].[0D_NW_NETV]` | Net Value |
| InfoObject texts | `caption` of dimension, hierarchy, level, property, measure | | the captions |
| Fact table, SID column | `Table`, `DimensionUsage foreignKey="SID_<char>"` | | |

Not modelled by default, because BW does not model it: user hierarchies (drill paths over attributes), nesting of
navigation attributes, a time hierarchy over separate time characteristics. They can be added when the business asks
(section 3.5).

## 2. How a BW cube becomes a schema

```
 /BI0/F0D_NW_C01 (fact table)              one CDS view per basic characteristic, one row per SID
 ┌──────────────────────────┐              ┌──────────────────────────────────────────────────────┐
 │ SID_0D_NW_PROD  ─────────┼─ foreignKey ►│ SID │ D_NW_PROD │ TXTMD │ D_NW_PRDCT │ ... │ texts │
 │ SID_0D_NW_SHIP  ─────────┼─ foreignKey ►│ SID │ D_NW_CUST │ TXTMD │ D_NW_CNTRY │ ... │       │ (0D_NW_CUST)
 │ D_NW_NETV, D_NW_QUANT ...│─ Measure     └──────────────────────────────────────────────────────┘
 └──────────────────────────┘
```

- **Fact:** the InfoCube's `/BI0/F<cube>` (`/BIC/F...` in the customer namespace), or an aDSO's view `/BIC/A<adso>7`.
  Each characteristic is a `SID_<char>` column (aDSO: the value column), each key figure a column.
- **Dimension table:** a CDS view per basic characteristic: the SID table, left-outer-joined with attributes and texts
  (section 4). The schema needs only its SQL view name and its columns.
- **Join:** the dimension's key attribute is the view's `SID` (aDSO: the key), matched with the fact column. The engine
  joins the view once for every hierarchy of the dimension a query uses.

## 3. Characteristics and attributes

### 3.1 The characteristic

```xml
<Dimension name="0D_NW_CODE" caption="Company" table="ZZXXMLA1VNWCOMP">
  <DimensionAttribute name="0D_NW_CODE SID" usage="Key" attributeHierarchyEnabled="false">
    <KeyColumn dataType="Integer" columnName="SID"/>
    <NameColumn dataType="String" columnName="D_NW_CODE"/>
  </DimensionAttribute>
  <DimensionAttribute name="0D_NW_CODE Text" attributeHierarchyEnabled="false">
    <KeyColumn dataType="String" columnName="TXTMD"/>
  </DimensionAttribute>
  ...
  <Hierarchy hasAll="true" allMemberName="All Companies" caption="Company">
    <Level name="0D_NW_CODE" caption="Company" uniqueMembers="true" sourceAttribute="0D_NW_CODE SID">
      <Property name="Text" caption="Company Name" sourceAttribute="0D_NW_CODE Text"/>
    </Level>
  </Hierarchy>
</Dimension>
```

- The `DimensionAttribute`s describe the view's columns. All of them have `attributeHierarchyEnabled="false"`: what
  users see are the `Hierarchy` elements, so that each can carry properties and a proper All member name.
- The key attribute is keyed by `SID` (the join) and named by the BW key in its **internal format** (`0000001000`,
  not BW's display `1000`): the internal key is what BW stores and what never changes.
- The one-level `Hierarchy` is flat. It is written out only because a member property needs a level; an attribute
  hierarchy (`attributeHierarchyEnabled="true"`) cannot carry properties, and its All member gets a generated name
  ("All Company.Countrys").
- The first `Hierarchy` of a dimension is its default hierarchy, unnamed, so its unique name is the dimension's:
  `[0D_NW_CODE]`.

### 3.2 Navigation attributes

A navigation attribute switched on in the provider (`RSDDIMEIOBJ` lists it as `<char>__<attribute>`) is a flat
hierarchy of the characteristic's dimension, named as BW names it:

```xml
<Hierarchy name="0D_NW_CODE__0D_NW_CNTRY" caption="Country of Company" hasAll="true"
           allMemberName="All Countries of Companies">
  <Level name="0D_NW_CNTRY" caption="Country of Company" uniqueMembers="true"
         sourceAttribute="0D_NW_CODE__0D_NW_CNTRY">
    <Property name="Text" caption="Country Name" sourceAttribute="0D_NW_CODE__0D_NW_CNTRY Text"/>
  </Level>
</Hierarchy>
```

What the demos showed:

- **It behaves as in BW: an independent field.** `[0D_NW_CODE.0D_NW_CODE__0D_NW_CNTRY]` on its own lists countries;
  crossed with the companies it gives every pair, and `NON EMPTY` keeps those with facts (DE / 1111, FR / 3333, ...).
  Nothing in the schema says that a company belongs to a country; the facts do.
- **It is the country of the company, not a country.** Its name says so, and a characteristic `0D_NW_CNTRY` of the
  cube would be a separate dimension `[0D_NW_CNTRY]`, as in BW.
- **No SQL difference** between a navigation attribute in the characteristic's dimension and a dimension of its own on
  the same view: both are one join of the same view, grouped by the attribute's column. The placement is about
  meaning, not performance.
- **Several navigation attributes are independent of each other.** Product Category and Product Group of
  `0D_NW_PROD` happen to nest in the data (each group belongs to one category), but BW does not model that, so the
  schema does not either.

### 3.3 Display attributes and attributes not switched on

A display attribute, or a navigation attribute that the provider does not switch on, is a member property of the
characteristic's level, as key and text:

```xml
<Level name="0D_NW_SHIP" caption="Ship-to Party" uniqueMembers="true" sourceAttribute="0D_NW_SHIP SID">
  <Property name="Text" caption="Ship-to Party Name" sourceAttribute="0D_NW_SHIP Text"/>
  <Property name="0D_NW_CNTRY" caption="Country" sourceAttribute="0D_NW_CNTRY"/>
  <Property name="0D_NW_CNTRY Text" caption="Country Name" sourceAttribute="0D_NW_CNTRY Text"/>
  <Property name="0D_NW_IND" caption="Industry" sourceAttribute="0D_NW_IND"/>
  <Property name="0D_NW_IND Text" caption="Industry Name" sourceAttribute="0D_NW_IND Text"/>
</Level>
```

In `0D_NW_C01`, `0D_NW_SHIP` has no navigation attribute switched on although customer has two (Country, Industry), so
they are properties. Excel shows them with right-click > *Show Properties in Report* or in the tooltip. Excel lists
only declared properties: the member key is not offered, which is why the text and every attribute must be a
`Property`.

### 3.4 Names: technical keys, texts as captions

- **Identifiers** (dimension, hierarchy, level, measure names) are BW technical names: `0D_NW_CODE`,
  `0D_NW_CODE__0D_NW_CNTRY`, `0D_NW_NETV`. **Captions** are the InfoObject texts: Company, Country of Company, Net Value.
  Excel and the MDX console show captions; typed MDX uses names.
- **Members are named by their internal BW key.** A member's unique name is built from its name, so
  `[0D_NW_CODE].[1111]` stays valid when the company's text changes. Saved queries, Excel filters and calculated
  members refer to keys that never change. Named by text, they break with every text maintenance, and two members with
  the same text under one parent collide.
- **Texts are properties** (`Text`, the EN medium text), shown next to the key on request.
- **Texts later, if the business wants them:** the caption shown for a member is its name, so showing texts means
  naming members by the text column (`NameColumn` = `TXTMD`), at the price of unique names that change with the text.
  The SID key, joins and numbers stay the same. Decide per characteristic.

### 3.5 What BW does not have, and when to add it

- **User hierarchies** (a drill path such as Category > Group > Product): only on request, for attributes that really
  nest, next to the flat fields, never instead of them. A user hierarchy placed first becomes the dimension's default
  and pushes the flat fields into Excel's "More Fields"; in the first demo it made the companies look as if they could
  only be seen under their countries.
- **External BW hierarchies:** out of scope.
- **A time hierarchy:** `0CALMONTH` and `0CALYEAR` are separate characteristics in BW and stay separate dimensions.
  Time functions (`Ytd`, `ParallelPeriod`, `PeriodsToDate`) need one `TimeDimension` with Year > Quarter > Month levels
  on a view that derives them from `0CALMONTH`; every level of a time dimension needs a `levelType`. Add it when
  the business needs those functions.
- **Default members** for value type and version (BW queries restrict them; the schema can make every MDX query do the
  same with `defaultMember`): a schema addition, not a BW object; useful when a cube mixes plan and actual.

### 3.6 Traps

- **A dimension's default hierarchy is its first one.** `[0D_NW_CODE].[0D_NW_CODE]` resolves in the default
  hierarchy; a hierarchy named like the dimension but defined later cannot be reached that way.
- **An unnamed `Hierarchy` and an attribute named like the dimension** get the same unique name; the reader refuses it.
  Name key attributes `<char> SID`, as above.
- **BW's "not assigned" value (SID 0)** is a member with an empty key; it appears without `NON EMPTY`.
- **Hierarchy unique names** of non-default hierarchies are `[Dimension.Hierarchy]`, not `[Dimension].[Hierarchy]`.

## 4. Views

The generated views (`ZZXXMLA1_CL_BW_VIEW_GEN`) hold the SID, the key and the time-independent attributes. For texts
and time-dependent attributes write the view by hand (or extend the generator); the demo views are in
[examples/bw-schema/](examples/bw-schema/). Rules, each learnt on the system:

1. **One row per SID.** The facts are joined to the view on `SID`; a second row for a SID counts its facts twice.
   Check with native SQL: `SELECT "SID", COUNT(*) FROM "<view>" GROUP BY "SID" HAVING COUNT(*) > 1`.
2. **Never join a client-dependent table without a client filter.** The engine reads with native SQL, which does not
   filter `MANDT`. Joining `T005T` (country names) made HANA's view `CROSS JOIN T000`: one row per client, every fact
   counted twice (DE showed 2,083,508,356.00 instead of 1,041,754,178.00), while ABAP SQL checks, which do filter the
   client, showed one row. BW's `/BI0/` and `/BIC/` tables are client-independent; take texts from them.
3. **Every SID stays:** start from the SID table, left-outer-join everything else. A SID missing in the view drops its
   facts (the engine inner-joins).
4. **Texts:** join `/BI0/T<char>`; a language-dependent text table (`LANGU` in its key) with `LANGU = 'E'`; the demo's
   category and group texts exist in DE and EN, so without the filter every product appears twice. A time-dependent
   text table also with `DATETO = '99991231'`. `coalesce( text, key )` so that a value without text is named by its key.
5. **Time-dependent attributes:** join `/BI0/Q<char>` with `OBJVERS = 'A'` and `DATETO = '99991231'`. Every value then
   shows its current assignment, also for old facts: product `CN00S1` was in group `NB1` until 2012-12-31 and is in
   `UB1` since, so all its sales from 2010 are under `UB1` (NB1 shows only `HT1000`, 85,742,741.00). This is BW with
   key date 9999-12-31.
6. **Reference characteristics** have no tables of their own: `0D_NW_SHIP`, `0D_NW_SOLD`, `0D_NW_PAYER` all use the
   view of `0D_NW_CUST`, and their fact columns hold its SIDs.
7. Check the text flags in `RSDCHABAS` (`TXTTABFL`, `NOLANGU`, `TXTTIMFL`) and the attribute types in `RSDBCHATR`
   (`ATTRITP` `NAV`/`DIS`, `ATRTIMFL`) before writing the joins.

Example, product with category (time-independent) and group (time-dependent):

```
define view ZZXXMLA1_C_NW_PROD
  as select from /bi0/sd_nw_prod as s
    left outer join /bi0/pd_nw_prod  as p  on  p.d_nw_prod = s.d_nw_prod and p.objvers = 'A'
    left outer join /bi0/qd_nw_prod  as q  on  q.d_nw_prod = s.d_nw_prod and q.objvers = 'A'
                                           and q.dateto = '99991231'
    left outer join /bi0/td_nw_prod  as t  on  t.d_nw_prod = s.d_nw_prod
    left outer join /bi0/td_nw_prdct as ct on  ct.d_nw_prdct = p.d_nw_prdct and ct.langu = 'E'
    left outer join /bi0/td_nw_prdgp as gt on  gt.d_nw_prdgp = q.d_nw_prdgp and gt.langu = 'E'
{
  key s.sid       as SID,
      s.d_nw_prod as D_NW_PROD,
      coalesce( t.txtmd, s.d_nw_prod )   as TXTMD,
      p.d_nw_prdct                       as D_NW_PRDCT,
      coalesce( ct.txtmd, p.d_nw_prdct ) as PRDCT_TXT,
      q.d_nw_prdgp                       as D_NW_PRDGP,
      coalesce( gt.txtmd, q.d_nw_prdgp ) as PRDGP_TXT
}
```

## 5. The example: 0D_NW_C01

7,005 fact rows, 2010-01 to 2020-12, one value type, one version, currency EUR, unit ST.

| BW dimension | Characteristic | Basic characteristic | Navigation attributes switched on in the cube | Other attributes | Values in facts |
|---|---|---|---|---|---|
| 1 | `0D_NW_CODE` Company code | itself | `0D_NW_CNTRY` | | 4 |
| 1 | `0D_NW_PLANT` Plant | itself | | | 5 |
| 1 | `0D_NW_SGRP` Sales group | itself | | | |
| 2 | `0D_NW_SOLD` Sold-to | `0D_NW_CUST` | none | `0D_NW_CNTRY`, `0D_NW_IND` (NAV in master data) | 19 |
| 2 | `0D_NW_SHIP` Ship-to | `0D_NW_CUST` | none | same | 19 |
| 2 | `0D_NW_PAYER` Payer | `0D_NW_CUST` | none | same | 19 |
| 3 | `0D_NW_PROD` Product | itself | `0D_NW_PRDCT`, `0D_NW_PRDGP` (time-dependent) | | 12 |
| 4 | `0D_NW_VTYPE` Value type | itself | | | 1 |
| 5 | `0D_NW_VERS` Version | itself | | | 1 |
| 6 | `0D_NW_CHANN`, `0D_NW_DIV` | itself | | | |
| 6 | `0D_NW_SORG` Sales organisation | itself | `0D_NW_CNTRY` | | 5 |
| 7 | `0D_NW_CNTRY` Country | itself | | | 4 |
| 7 | `0D_NW_REGIO` Region | compounded with `0D_NW_CNTRY` | | | 5 |
| T | `0CALMONTH`, `0CALYEAR` | | | | 132 / 11 |
| U | `0CURRENCY`, `0UNIT` | | | | 1 / 1 |

Key figures, all SUM/SUM: `0D_NW_NETV`, `0D_NW_COSTV`, `0D_NW_OORV` (currency), `0D_NW_QUANT`, `0D_NW_OORQT` (unit),
`0D_NW_DOCUM`.

The demo catalog `NWPRODUCT` (cube `NW Product Sales`) has Product with its two navigation attributes and Ship-to with
its display attributes ([NWPRODUCT.xml](examples/bw-schema/NWPRODUCT.xml)); `NWCOMPANY` has the company code with its
country ([NWCOMPANY.xml](examples/bw-schema/NWCOMPANY.xml)). Answers on the system:

| Query (NON EMPTY, Net Value) | Result |
|---|---|
| `[0D_NW_PROD.0D_NW_PROD__0D_NW_PRDCT]` | MOB 1,550,415,790.00 · MON 1,589,641,940.00 · NB 1,534,753,565.00 |
| `[0D_NW_PROD.0D_NW_PROD__0D_NW_PRDGP]` | UB1 712,365,431.00 (CN00S1, all years) · NB1 85,742,741.00 (HT1000 only) · ... |
| `[0D_NW_SHIP]` with properties | 0000001000 · Adecom SA · GB · 1111: 102,625,813.00 · ... (19 parties) |
| `[0D_NW_CODE.0D_NW_CODE__0D_NW_CNTRY]` × `[0D_NW_CODE]` | DE / 1111 · FR / 3333 · GB / 2222 · US / 4444, totals 4,674,811,295.00 |

Compounding: `0D_NW_REGIO` is compounded with `0D_NW_CNTRY`, so its key alone is not unique. The SID is unique; name
the member by both keys, concatenated in the view (`concat_with_space( d_nw_cntry, d_nw_regio, 1 )`), so that unique
names are unique too. Not tried on the system yet.

## 6. Measures

```xml
<Cube name="NW Product Sales" caption="0D_NW_C01 by product and ship-to party" defaultMeasure="0D_NW_NETV">
  <Table name="/BI0/F0D_NW_C01"/>
  <DimensionUsage name="0D_NW_PROD" caption="Product" source="0D_NW_PROD" foreignKey="SID_0D_NW_PROD"/>
  <Measure name="0D_NW_NETV" caption="Net Value" column="D_NW_NETV" aggregator="sum" formatString="#,##0.00"/>
</Cube>
```

- Name = key figure, caption = its text, a format string per key figure type.
- Amounts in different currencies must not be summed: with several currencies keep `0CURRENCY` as a dimension users
  slice by, or convert in BW.
- Calculated and restricted key figures belong in the MDX query (`WITH MEMBER`) until schema `CalculatedMember`s are
  read (section 8).

## 7. Performance

| What the engine does | Design consequence |
|---|---|
| **Members:** the first time a hierarchy is used, `SELECT DISTINCT <level key, name, properties> FROM <view> ORDER BY <level key>`, all rows of the view. | Cost grows with master data, not facts. Many properties on a characteristic with millions of values (customers, documents) make this read large. |
| **Cells:** one grouped query per combination of levels: the fact table inner-joined with the view once per hierarchy used, `GROUP BY` the level key columns, `SUM` of every measure plus `COUNT(*)`, kept for the rest of the query. | Every hierarchy on an axis or in the slicer is one join, whether or not two hierarchies share a dimension. Views must be cheap to join: 1:1 joins on keys, no aggregation, no `DISTINCT`, no `UNION`. HANA aggregates. |
| Grouping uses key columns only (the SID); names and properties are read with the members. | Texts and keys as names or properties cost nothing in fact queries. |
| Levels list every row of the view, not only values with facts (`0CALMONTH`'s SID table has 231 months, the facts 132). | Use `NON EMPTY`, as Excel does. Under `NON EMPTY`, levels of more than 300 members, `Children` and `Descendants` read only members with facts, and crossjoins are computed in the database. |
| A crossjoin larger than 1,000,000 tuples fails before it is built. | Large combinations need `NON EMPTY`, `Filter` or `TopCount`. |
| Subselects (Excel pivot filters) add their hierarchies' joins and a `WHERE` to every fact query. | Same rule as axes: cheap views. |
| aDSO facts come from `/BIC/A<adso>7`, a union of inbound and active table. | Activate requests regularly. |

## 8. Checklist and current limits

Checklist:

- [ ] One dimension per characteristic of the provider (technical ones such as package and request left out), named by
      the InfoObject, captioned by its text.
- [ ] Members keyed by SID, named by the internal BW key, the EN text as property `Text`.
- [ ] Each navigation attribute switched on in the provider is a flat hierarchy `<char>__<attribute>`; display
      attributes and attributes not switched on are properties (key and text).
- [ ] Reference characteristics are dimensions of their own on the basic characteristic's view.
- [ ] No user hierarchies unless the business asks; never first in a dimension.
- [ ] Measures named by key figure, captioned, formatted; no sums across currencies.
- [ ] Every view: one row per SID (checked with native SQL), every SID kept, no client-dependent table, texts in EN,
      time-dependent data at 9999-12-31.

Current limits of olap4abap:

- **The schema generator does not follow this guide yet:** its proposal names dimensions, attributes and measures by
  InfoObject texts, names members by the key only on the key attribute, treats navigation and display attributes alike,
  and its views have no texts or time-dependent attributes. Until it does, write the schema and views by hand from the
  examples.
- **Aggregation:** fact queries sum every measure; only `sum` (and the built-in `Fact Count`) are correct. A measure
  with `aggregator="min"` or `"max"` is read as a sum by `ZZXXMLA1_CL_MDX_FACTS` today. Exception aggregation and
  non-cumulative key figures are not supported.
- **Schema calculated members** (`CalculatedMember` in a cube) are not read; schema `NamedSet`s, virtual cubes, roles
  and parameters are refused.
- **Not supported in levels:** `captionColumn`, `ordinalColumn` (members are ordered by key), expressions,
  `parentColumn`, `hideMemberIf`; property formatters.
- **`0CALDAY`** has no SID table and is not proposed.
- One cube per catalog.
