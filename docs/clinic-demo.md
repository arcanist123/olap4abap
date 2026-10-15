# Clinic demo

A demo data set that ships with olap4abap: patients' visits to a clinic in 2024 and 2025. It is made up by
`ZZXXMLA1_CL_BW_CLINIC_GEN` (a seeded pseudo-random generator, the same visits on every run), so it carries no
third-party data and is under the project's license. FoodMart (`ZFMSALES`) stays the source of the correctness tests:
the reference server's expected answers exist only for FoodMart.

Run program `ZZXXMLA1_SETUP` with the checkbox "Also generate the clinic demo", or
`sapcli class execute ZZXXMLA1_CL_BW_CLINIC_GEN`. A run takes about two minutes and **deletes and creates** InfoArea
`ZCLINIC`'s objects (the demo's catalogs, the aDSO, the cube, the views of its characteristics and the InfoObjects
`ZCL*`); the views of the time characteristics `0CAL*` are shared with other providers and only generated again.

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
  R04 are at both sites, R05 only in the north, so a room is a member only with its site, `[ZCLROOM].[NORTH/R01]`
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
  customizing, which a warehouse does not maintain. Their SIDs come with the loads (no master data).
- The physician `ZCLDOC` is **authorization relevant** and has two hierarchies, `ZCLDOC_ORG` and `ZCLDOC_SITE`, and
  the diagnosis `ZCLDIAG` is authorization relevant too, with the hierarchy `ZCLDIAG_ICD` (see below), for working
  with BW's analysis authorizations, also in combination. BW's own queries on `ZCLVISIT`/`ZCLVISITA` (RSRT, BEx,
  Analysis for Office) then need an analysis authorization that covers `ZCLDOC` and `ZCLDIAG`; olap4abap reads the
  tables and checks no authorizations.
- Key figures: `ZCLVISNO` (1 per visit: the aDSO adds up visits with the same keys, so counting rows would not count
  visits), `ZCLDUR` duration, `ZCLWAIT` waiting time (minutes), `ZCLLABS` lab tests, `ZCLCHRG` charges.
- Texts: every characteristic has language-dependent short, medium and long texts (a text table `/BIC/T...`), and the
  run loads EN texts for all its values: the patient's and the physician's name, the diagnosis in plain words, the
  visit type (`Outpatient Visit`), the date (`Monday, 1 January 2024`, short `2024-01-01`), site and room
  (`Consultation Room 1`), the fiscal year variant (`Calendar Year, 4 Special Periods`), year and period
  (`Period 001/2024, January 2024`), and every value of an attribute (`0-17`: `Children (0-17)`, `O+`: `O Positive`,
  ...). The views carry them (`TXTMD`, `<attribute>_TXT`).
- The schema the schema generator proposes for each provider, accepted through the schema API with its views
  (`ZZXXMLA1_CL_BW_VIEW_GEN`): the schema files `/WEB-INF/schema/ZCLVISIT.xml` and `/WEB-INF/schema/ZCLVISITA.xml` and
  a catalog for each in `/WEB-INF/datasources.xml` (the setup writes the data sources file if there is none); see The
  schemas below.
- The same with the fiscal year variant fixed to K4 (`docs/bw-schema-design-guide.md`, section 3.8): the catalogs
  `ZCLVISIT_K4` and `ZCLVISITA_K4` (cubes named as the catalogs, `/WEB-INF/schema/ZCLVISIT_K4.xml`, ...), on the views
  filtered on K4 that accepting them generates: a fact view per provider (on the InfoCube too, its fact table joined to
  the variant's SID table) and the views of the variant (one row, K4), the fiscal year and period. A run deletes all of
  them with the views of the characteristics and the providers' fact views, also views whose row of `ZZXXMLA1_VIEW` is
  lost (found by their description): BW refuses to delete a characteristic a view still uses.

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

The schemas are the schema generator's (`docs/schema-generator.md`): per provider the run proposes the schema as
`GET proposal` does (the fiscal defaults, which concern only BW's `0FISC*`, then `ZZXXMLA1_CL_SCHEMA_PROPOSAL`) and
accepts it through the schema API (`POST accept`, catalog = provider: the views generated, the schema file written,
the catalog added); then it fixes the same proposal to K4 as `POST fix` does (`ZZXXMLA1_CL_SCHEMA_FIX`), names the
schema and the cube as the catalog (`ZCLVISIT_K4`, caption "Clinic Visits (K4)") and accepts that. Before it deletes
anything, the run removes the four catalogs through the API (`POST remove`, with their files and filtered views).

So the schemas follow `docs/bw-schema-design-guide.md`: a dimension per characteristic named by its technical name and
captioned by its text (`[ZCLPAT]`, "Patient"), one flat hierarchy with an All member (`All Patient`) and one level
(`[ZCLPAT].[ZCLPAT]`), members named by the key as BW holds it (`[ZCLPAT].[002000]`; on the cube keyed by the SID, on
the aDSO by the value), the text and the display attributes (each with its text) as member properties; measures by
their technical names (`[Measures].[ZCLVISNO]`, the default measure). The room, the fiscal year and the fiscal period
are compounded: keyed by the SID on both providers, named by `COMPOUND_KEY` (`NORTH/R01`, `K4/2024001`); in the K4
catalogs the year and period are named by their own key (`2024001`). The cube has the date `ZCLDATE`, the aDSO BW's
`0CALWEEK`, `0CALMONTH`, `0CALQUARTER` and `0CALYEAR` (`0CALDAY` has no SID table). The proposal makes no user
hierarchies (Region > City > Patient and the like are for the UI to add) and marks no dimension as time.

Every dimension is annotated `olap4abap.membersWithFacts` on the cube's `DimensionUsage` (`mvp-scope.md`, Members with
facts decision): its members are only those with visits, so the 300 registered patients are no members
(`scripts/clinic_test.py` checks it on both providers). The cubes are annotated `olap4abap.omitEmptyCells`.

Examples:

    SELECT [Measures].Members ON 0, [ZCLDOC].[ZCLDOC].Members ON 1 FROM ZCLVISIT

    SELECT [Measures].[ZCLVISNO] ON 0, NON EMPTY [0CALMONTH].[0CALMONTH].Members ON 1 FROM ZCLVISITA

    SELECT [Measures].[ZCLVISNO] ON 0, [ZCLPAT].[ZCLPAT].Members DIMENSION PROPERTIES [ZCLPAT].[ZCLPAT].[Text] ON 1
    FROM ZCLVISIT

    SELECT [Measures].[ZCLVISNO] ON 0, NON EMPTY [ZCLFISCPR].[ZCLFISCPR].Members ON 1
    FROM ZCLVISITA_K4
