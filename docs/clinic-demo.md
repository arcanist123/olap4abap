# Clinic demo

A demo data set that ships with olap4abap: patients' visits to a clinic in 2024 and 2025. It is made up by
`ZZXXMLA1_CL_BW_CLINIC_GEN` (a seeded pseudo-random generator, the same visits on every run), so it carries no
third-party data and is under the project's license. FoodMart (`ZFMSALES`) stays the source of the correctness tests:
the reference server's expected answers exist only for FoodMart.

Run program `ZZXXMLA1_SETUP` with the checkbox "Also generate the clinic demo", or
`sapcli class execute ZZXXMLA1_CL_BW_CLINIC_GEN`. A run takes about two minutes and **deletes and creates** InfoArea
`ZCLINIC`'s objects (the aDSO, the cube, the views of its characteristics and the InfoObjects `ZCL*`); the views of the
time characteristics `0CAL*` are shared with other providers and only generated again.

"Clinic demo: max. visits" (`run( max_visits = ... )` of the class) caps the number of visits for a smaller demo, e.g.
on a test system: the visits are thinned evenly over the days, so every day keeps its share; 0 (the default) keeps all
33,956. Patients, physicians and diagnoses stay the same.

## What it creates

- InfoCube `ZCLVISIT` (one BW dimension per characteristic) and cube-type aDSO `ZCLVISITA` with the same visits; the
  aDSO has BW's standard time characteristics (`0CALDAY`, `0CALWEEK`, `0CALMONTH`, `0CALQUARTER`, `0CALYEAR`) in place
  of the date.
- Characteristics with flat attributes: patient `ZCLPAT` (name, sex, birth year, age group on 1 January 2024, blood
  group, insurance, city, region), physician `ZCLDOC` (name, department, years in practice), diagnosis `ZCLDIAG` (ICD-10
  code; name in plain words, group, chapter), visit type `ZCLVTYPE` (care setting), date `ZCLDATE` (`YYYYMMDD`; the date
  text, day and month names, year, quarter, month, week counted from 1 January, day of month). The date is a plain
  characteristic, as FoodMart's `ZFMDATE`, so it can carry attributes.
- The site `ZCLSITE` (`NORTH`, `SOUTH`; city) and the room `ZCLROOM` (room type), **compounded** with the site: R01 to
  R04 are at both sites, R05 only in the north, so a room is a member only with its site, `[Room].[NORTH/R01]`
  (`docs/bw-schema-design-guide.md`, section 3.7). The south rooms are loaded first, so their SIDs come before the
  north ones and the members' order (by name, `OrderByColumn`) differs from the SIDs'. The aDSO is read through its
  fact view (the SID of the room, `ZZXXMLA1_CL_BW_VIEW_GEN=>generate_fact_view`), which a run deletes before the aDSO.
- The fiscal time, in both providers (the InfoCube's dimension `ZCLVISIT7`, Fiscal Time): the fiscal year variant
  `ZCLFISCVR` (K1, K2, K4), the fiscal year `ZCLFISCYR` and the fiscal period `ZCLFISCPR`, both **compounded** with
  the variant. Each visit is booked under one variant, by its number (K1, K2, K4 in turn); all three follow the
  calendar (the period is the month), so `2024001` exists under each, and without a fixed variant the periods are
  members `K1/2024001` ... `K4/2025012`. A cube that fixes `ZCLFISCVR = K4` (`docs/bw-schema-design-guide.md`,
  section 3.8) has a third of the visits (11,318), its periods named `2024001` ... `2025012`: the catalogs
  `ZCLVISIT_K4` and `ZCLVISITA_K4` (below, `scripts/fixed_selection_test.py`). They are the demo's own
  characteristics, not BW's `0FISC*`: BW checks those against the fiscal year variants of the source system's
  customizing (T009), which a warehouse does not maintain. Their SIDs come with the loads (no master data).
- The physician `ZCLDOC` is **authorization relevant** and has two hierarchies, `ZCLDOC_ORG` and `ZCLDOC_SITE`, and
  the diagnosis `ZCLDIAG` is authorization relevant too, with the hierarchy `ZCLDIAG_ICD` (see below), for working
  with BW's analysis authorizations, also in combination. BW's own queries on `ZCLVISIT`/`ZCLVISITA` (RSRT, BEx,
  Analysis for Office) then need an analysis authorization that covers `ZCLDOC` and `ZCLDIAG`; olap4abap reads the
  tables and checks no authorizations.
- Key figures: `ZCLVISNO` (1 per visit: the aDSO adds up visits with the same keys, so counting rows would not count
  visits), `ZCLDUR` duration, `ZCLWAIT` waiting time (minutes), `ZCLLABS` lab tests, `ZCLCHRG` charges.
- The views of the characteristics (`ZZXXMLA1_CL_BW_VIEW_GEN`), the schema files `/WEB-INF/schema/ZCLVISIT.xml` and
  `/WEB-INF/schema/ZCLVISITA.xml` and a catalog for each in `/WEB-INF/datasources.xml` (added once; the setup writes the
  data sources file if there is none).
- The same with the fiscal year variant fixed to K4 (`docs/bw-schema-design-guide.md`, section 3.8): the catalogs
  `ZCLVISIT_K4` and `ZCLVISITA_K4` (cubes named as the catalogs, `/WEB-INF/schema/ZCLVISIT_K4.xml`, ...), on the views
  filtered on K4 that the run generates with the others: a fact view per provider (on the InfoCube too, its fact table
  joined to the variant's SID table) and the views of the variant (one row, K4), the fiscal year and period. A run deletes all of them with the
  views of the characteristics and the providers' fact views.

## The hierarchies of the physicians

`ZCLDOC` has hierarchies that are **version dependent** and where the **entire hierarchy is time dependent**
(`RSDCHABAS`: `HIETABFL`, `HIEVERFL`, `HIENMTFL` set, `HIENDTFL` not; the same time dependency as the SAP demo's
`0D_NW_PROD`): per hierarchy name and version a hierarchy per time slice, each a row of `RSHIEDIR` with its own
`HIEID`, `DATEFROM` and `DATETO`. There are two hierarchy names, for authorization tests that restrict on nodes of
different hierarchies. A physician's department and site are
independent, so the nodes of the two cut across each other. The generator loads them through BW's hierarchy interface
(`RSNDI_SHIE_STRUCTURE_UPDATE4`, then `RSNDI_SHIE_ACTIVATE`; `UPDATE3` dumps on the 2025 system), four slices each.

`ZCLDOC_ORG`, the organization:

| Version | Valid | Structure |
|---|---|---|
| `001` Clinic Organization | 1000-01-01 to 2024-12-31 | Clinic > Primary Care (General Practice, Pediatrics), Specialist Care (Cardiology, Pulmonology, Orthopedics, Dermatology), Emergency Care (Emergency Medicine) > physicians |
| `001` | 2025-01-01 to 9999-12-31 | reorganised: Specialist Care > Internal Medicine > Cardiology, Pulmonology; Dermatology under Primary Care; Dr. Hana Sato (`008`) moves to General Practice, Dr. Karim Aziz (`011`) to Emergency Medicine |
| `002` Clinic Organization (Plan) | 1000-01-01 to 2024-12-31 | as version `001` |
| `002` | 2025-01-01 to 9999-12-31 | the plan: Emergency Medicine under Primary Care, no Internal Medicine, nobody moves |

The text nodes (`0HIER_NODE`) are named `CLINIC`, `PRIMARY`, `SPECIAL`, `INTMED`, `EMERGENCY` and per department `GP`,
`PED`, `CARD`, `PULM`, `ORTH`, `DERM`, `EMER`; the leaves are the physicians' keys. The attribute Department stays as in
the master data (it is not time dependent), so in 2025 it differs from the hierarchy for `008` and `011`.

`ZCLDOC_SITE`, the sites (All Sites `SITES` > City Center `CITY`, Suburbs `SUBURBS` > site > physicians):

| Version | Valid | Main Campus `MAIN` (City Center) | Riverside Branch `RIVER` (Suburbs) | Northgate Branch `NORTH` |
|---|---|---|---|---|
| `001` Clinic Sites | 1000-01-01 to 2024-12-31 | the other 13 | `004`, `005`, `008`, `011`, `013`, `016`, `018` | - |
| `001` | 2025-01-01 to 9999-12-31 | the other 12 | `004`, `011`, `013`, `018` | Suburbs: `002`, `005`, `008`, `016` |
| `002` Clinic Sites (Plan) | 1000-01-01 to 2024-12-31 | as version `001` | as version `001` | - |
| `002` | 2025-01-01 to 9999-12-31 | the other 12 | `005`, `008`, `011`, `016` | City Center: `003`, `004`, `013`, `018` |

### Probing BW's authorizations on them

Program `ZZXXMLA1_BW_AUTH_PROBE` (`ZZXXMLA1_CL_BW_AUTH_PROBE`) runs queries through BW's own MDX engine
(`BAPI_MDDATASET_*`) on `$ZCLVISITA` as the current user and lists per query OK, EMPTY, NO AUTH or ERROR with BW's
answer (with the cell status where BW gives one) or message; above the list the analysis authorizations that restrict
`ZCLDOC` or `ZCLDIAG`, with all their lines, and whether the user has them. BW's MDX shows per hierarchy name and
version only the slice valid at the key date (unique name `[ZCLDOC<pad 30>ZCLDOC_ORG<pad 30>001]`, no date in it;
`[ZCLDIAG<pad 30>ZCLDIAG_ICD]` without version), so the probe sets the key date (`RRT_SET_KEY_DATE`) and runs everything
once per key date (default 2024-06-15 and 2025-06-15):

- the total, which aggregates both characteristics (it needs the aggregation authorization `:` on each);
- per characteristic, flat: `[ZCLDOC].Members` and each value as slicer (the values from the SID table);
- per hierarchy its members, and per node (text node `[<hierarchy>].[<name pad 32>0HIER_NODE]`, leaf
  `[<hierarchy>].[008]`) the node as slicer, on the rows, its children and its parent;
- combined: the members of one characteristic (flat and per hierarchy) with each value and each text node of the
  other as slicer (its leaves too with "combine with leaves").

With `0BI_ALL` all 2,244 queries answer (about 90 seconds). The statement goes to BW in lines of 75 characters that BW
joins respecting blanks.

## The hierarchy of the diagnoses

For authorizations that combine two characteristics, the diagnosis `ZCLDIAG` has the hierarchy `ZCLDIAG_ICD`, Diagnoses
by ICD-10 Chapter: All Diagnoses `DIAGNOSES` > chapter > group > diagnosis (69 nodes: 9 chapters, 23 groups, the 36
diagnoses' codes as leaves). Unlike the physician's, it is plain: neither version nor time dependent (`HIETABFL` only;
version blank, valid to 9999-12-31), so in a combination only the physician's side depends on the key date and the
version. The text nodes are named by their text in upper case with `_` for blanks and hyphens, cut at 32 characters:
`RESPIRATORY`, `UPPER_RESPIRATORY_INFECTIONS`, `CHRONIC_LOWER_RESPIRATORY_DISEAS`, `CHECK_UPS`, ... A department
treats some chapters more than others (respiratory diagnoses mostly in pulmonology, general practice and pediatrics),
so a node of each hierarchy restricts the visits differently from their intersection.

The run deletes the characteristics' hierarchies before the InfoObjects. An analysis authorization on a hierarchy node
also stores the hierarchy's `HIEID` (`RSECHIE`), and every run creates new ones: check the hierarchy authorizations
after a run (not tried yet).

## The data

2,000 patients, 20 physicians in 7 departments, 36 diagnoses, 33,956 visits. Another 300 patients are registered
without a visit (made after the visits, so these stay as they were), some of them in the city Kingsport of the region
Coastal, where nobody has visited: the master data has members the providers do not use, as a BW characteristic shared
by many providers has. Patterns, so that queries show something:
fewer visits at weekends (Sundays only the emergency department), about a fifth more in winter and a quarter fewer in
August, 5% more in 2025; children go to pediatrics, cardiology and pulmonology see mostly older patients; respiratory
diagnoses are three times as frequent in winter; duration, waiting time, lab tests and charges depend on the visit type
and the diagnosis.

BW's blank member (the initial key, SID 0) is in every hierarchy, and a few visits use it: about 1% have no diagnosis
recorded yet, some emergency visits have no physician (triage) or an unidentified patient, 0.5% no visit type. Time has
no blank visits.

The site and the room come from the physician (even: north, odd: south) and the patient (the room), so they draw no
random number and the visits stay as they were; a visit without physician has neither (`#/#`).

## The schemas

The generator writes the schemas itself, by the rules of the proposal (`docs/schema-generator.md`): on the cube a
dimension is keyed by the SID of its view and named by the value, on the aDSO keyed by the value (the fact column).

| Dimension | User hierarchies | Notes |
|---|---|---|
| Patient | Region > City > Patient (named by the patient's name; properties Sex, Birth Year, Blood Group, Insurance); `Demographics`: Age Group > Sex | City `uniqueMembers="false"` |
| Physician | Department > Physician (property Years in Practice) | |
| Diagnosis | Chapter > Group > Diagnosis | the group Influenza has one diagnosis |
| Visit Type | Care Setting > Visit Type | |
| Site | none (property City) | |
| Room | none (properties Room Key, Room Type) | keyed by the SID on both providers (the aDSO's fact view), named and ordered by `COMPOUND_KEY` (`NORTH/R01`) |
| Time (cube) | Year > Quarter > Month (named by the month) > Day, without All member, default `[Time].[2025]`; `Weekly`: Year > Week > Day | `TimeDimension` |
| Year, Quarter, Month, Week (aDSO) | none | one dimension per time characteristic, which have no attributes |
| Fiscal Year Variant | none | `K1`, `K2`, `K4`; in the K4 catalogs the one member `K4` |
| Fiscal Year, Fiscal Period | none | compounded with the variant: keyed by the SID, named and ordered by `COMPOUND_KEY` (`K4/2024`, `K4/2024001`); in the K4 catalogs not compounded, still keyed by the SID (on the aDSO too) and named by their own key (`2024`, `2024001`) |

Every dimension but time is annotated `olap4abap.membersWithFacts` on the cube's `DimensionUsage`
(`mvp-scope.md`, Members with facts decision): its members are only those with visits, so the registered patients,
Kingsport and Coastal are no members (`scripts/clinic_test.py` checks it on both providers). The time dimensions are
not annotated (to be decided).

Every attribute is also an attribute hierarchy (`[Patient.Age Group]`). Measures: Visits, Duration Min, Waiting Min, Lab
Tests (format `#,##0`), Charges (`#,##0.00`). A hierarchy other than Time has an All member: BW's blank member sorts
first, so without an All member it would be the default member and every query would read the blank visits only.

Examples:

    SELECT [Measures].Members ON 0, [Physician].[Department].Members ON 1 FROM ZCLVISIT

    WITH MEMBER [Measures].[Prev Year] AS ([Measures].[Visits], ParallelPeriod([Time].[Year], 1))
         MEMBER [Measures].[Avg Wait] AS [Measures].[Waiting Min] / [Measures].[Visits], FORMAT_STRING = '0.0'
    SELECT {[Measures].[Visits], [Measures].[Prev Year], [Measures].[Avg Wait]} ON 0,
           [Time].[2025].[Q1].Children ON 1
    FROM ZCLVISIT

    SELECT [Patient.Demographics].[Age Group].Members ON 0, [Physician].[Department].Members ON 1
    FROM ZCLVISIT WHERE [Measures].[Visits]

    SELECT [Measures].[Visits] ON 0, NON EMPTY [Fiscal Period].[Fiscal Period].Members ON 1
    FROM ZCLVISITA_K4
