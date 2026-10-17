# Clinic demo

A demo data set that ships with olap4abap: patients' visits to a clinic in 2024 and 2025. It is made up by
`ZZXXMLA1_CL_BW_CLINIC_GEN` (a seeded pseudo-random generator, the same visits on every run), so it carries no
third-party data and is under the project's license. FoodMart (`ZFMSALES`) stays the source of the correctness tests:
the reference server's expected answers exist only for FoodMart.

Run program `ZZXXMLA1_SETUP` with the checkbox "Also generate the clinic demo", or
`sapcli class execute ZZXXMLA1_CL_BW_CLINIC_GEN`. A run takes about two minutes and **deletes and creates** InfoArea
`ZCLINIC`'s objects (the demo's catalogs, the aDSO, the cube, the views of its characteristics and the InfoObjects
`ZCL*`); the views of the time characteristics `0CAL*` are shared with other providers and only generated again.

The checkboxes "Demos: create the InfoCube" and "Demos: create the aDSO" (both on by default; `run( cube = ...
adso = ... )` of the class) choose the providers the run creates, loads and deploys a catalog for. It deletes all the
demo's objects and catalogs either way, and always creates the InfoObjects with their master data, texts and
hierarchies. The checkboxes apply to the wide demo too.

"Clinic demo: max. visits" (`run( max_visits = ... )` of the class) caps the number of visits for a smaller demo, e.g.
on a test system: the visits are thinned evenly over the days, so every day keeps its share; 0 (the default) keeps all
33,956. Patients, physicians and diagnoses stay the same.

## What it creates

- InfoCube `ZCLVISIT` (one BW dimension per characteristic) and cube-type aDSO `ZCLVISITA` with the same visits; the
  aDSO has BW's standard time characteristics (`0CALDAY`, `0CALWEEK`, `0CALMONTH`, `0CALQUARTER`, `0CALYEAR`) in place
  of the date.
- Characteristics with flat attributes: patient `ZCLPAT` (name, sex, birth year, age group on 1 January 2024, blood
  group, insurance, city, region), physician `ZCLDOC` (name, department, years in practice), diagnosis `ZCLDIAG` (ICD-10
  code; name in plain words, group, chapter), visit type `ZCLVTYPE` (care setting), service `ZCLSERV` (52 services
  by a four-digit code, care setting; see below), date `ZCLDATE` (`YYYYMMDD`; the date
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
  section 3.8) has a third of the visits (11,318), its periods named `2024001` ... `2025012`: the schema builder
  makes one with "Fixed value" (`scripts/fixed_selection_test.py` does it through the API). They are the demo's own
  characteristics, not BW's `0FISC*`: BW checks those against the fiscal year variants of the source system's
  customizing, which a warehouse does not maintain. Their SIDs come with the loads (no master data).
- The physician `ZCLDOC` is **authorization relevant** and has two hierarchies, `ZCLDOC_ORG` and `ZCLDOC_SITE`, and
  the diagnosis `ZCLDIAG` is authorization relevant too, with the hierarchy `ZCLDIAG_ICD` (see below), for working
  with BW's analysis authorizations, also in combination. BW's own queries on `ZCLVISIT`/`ZCLVISITA` (RSRT, BEx,
  Analysis for Office) then need an analysis authorization that covers `ZCLDOC` and `ZCLDIAG`; olap4abap reads the
  tables and checks no authorizations.
- The patient `ZCLPAT` has the hierarchy `ZCLPAT_PRG` with **duplicate and link nodes** (shared subtrees and patients
  under two parents, see below), the test case of BW hierarchies with shared nodes; it is not authorization relevant.
- The service `ZCLSERV` has the hierarchy `ZCLSERV_CAT` of **intervals**, overlapping and linked, and the hierarchy
  `ZCLSERV_LOC` with nodes of the **external characteristics** site and room (see below).
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
- A run deletes the views of the characteristics and the providers' fact views (also filtered ones, and views whose
  row of `ZZXXMLA1_VIEW` is lost, found by their description: BW refuses to delete a characteristic a view still
  uses), and the demo's catalogs, also the K4 ones (`ZCLVISIT_K4`, `ZCLVISITA_K4`) that earlier runs deployed.

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
by ICD-10 Chapter: All Diagnoses `DIAGNOSES` > chapter > group > diagnosis (72 nodes: 10 chapters, 24 groups, the 36
diagnoses' codes and the initial value as leaves). Every value is assigned: the initial one (the 337 visits without a
diagnosis) is the leaf `#` under `NOT_RECORDED` (Not recorded) > `NO_DIAGNOSIS` (No diagnosis), and the hierarchy
suppresses the not-assigned node (`NORESTNODES`), so it has no REST_H. Unlike the physician's, it is plain: neither version nor time dependent (`HIETABFL` only;
version blank, valid to 9999-12-31), so in a combination only the physician's side depends on the key date and the
version. The text nodes are named by their text in upper case with `_` for blanks and hyphens, cut at 32 characters:
`RESPIRATORY`, `UPPER_RESPIRATORY_INFECTIONS`, `CHRONIC_LOWER_RESPIRATORY_DISEAS`, `CHECK_UPS`, ... A department
treats some chapters more than others (respiratory diagnoses mostly in pulmonology, general practice and pediatrics),
so a node of each hierarchy restricts the visits differently from their intersection.

## The hierarchy of the care programs

The patient `ZCLPAT` has the hierarchy `ZCLPAT_PRG`, Care Programs, plain as `ZCLDIAG_ICD` (neither version nor time
dependent), with a node in several places in both of BW's ways:

- a **duplicate node**: BW takes a value of the characteristic more than once, each an ordinary node (with children
  of its own; BW even lets one duplicate have a subtree and another none, which olap4abap refuses: duplicates must
  have the same subtree, `next-steps.md`, Multiple parents); here leaves only;
- a **link node** (`LINK` = `X` in `/BIC/HZCLPAT`, `link` of the generator's node): no children of its own, BW shows
  its original's subtree (the node of that name that is no link) below it; a value or a text node.

```
All Care Programs  PROGRAMS
├── Chronic Care  CHRONIC
│   ├── Diabetes Program  DIABETES        127 patients
│   ├── Heart Program  HEART              185 patients (30 also in Diabetes: duplicates)
│   └── Respiratory Program  RESPIRATORY  118 patients (45 duplicates)
├── Senior Care  SENIOR
│   ├── Heart Program  HEART              link: the heart program's subtree again
│   └── Fall Prevention  FALLS             87 patients (39 links: also in Heart; 21 duplicates)
└── Prevention  PREVENTION
    ├── Senior Care  SENIOR               link: Senior Care's subtree, with its link to HEART (recursive)
    ├── Child Health  CHILD                85 patients
    └── Family Care  FAMILY                5 parents (postable nodes), each with their 1 or 2 children below
```

So the heart program's patients are in the hierarchy three times (Chronic Care, Senior Care, Prevention > Senior
Care), a patient in two programs a second time as a leaf (in Fall Prevention a link if the patient is in Heart
Program too, otherwise a duplicate), and a node sums distinct patients: Senior Care counts a
patient of Heart Program and Fall Prevention once, All Care Programs counts the 467 patients in a program once. The
members follow from the age group and the patient's number, without a random draw (the visits stay as they were):
Diabetes 40 and older, number divisible by 9; Heart 65 and older divisible by 4, 40-64 divisible by 12; Respiratory 40
and older, number ending in 4; Fall Prevention 65 and older divisible by 6; Child Health under 18 divisible by 5. The
patients without a visit are in it too; the other patients (most of them) are not assigned.

Family Care has **postable nodes**: a parent (18 to 39, number ending in 07 or 57) is a node of the patient with up
to three children below them (under 18, the same city, among the next 40 numbers), so the node is a value of the
characteristic with children and with visits of its own (5 to 13). Five parents have such children (`000007` with
`000011` and `000015`, `001257`, `001357`, `001407`, `001657`; 7 children). No parent is in another program (they
are 18 to 39), so a postable node is in the hierarchy once and has one shape; a child in Child Health too (`000015`)
is a duplicate leaf.

The hierarchy table has 626 nodes (2 linked text nodes, 39 linked and 96 duplicate patients, 5 postable nodes);
BW's SID structure `/BIC/IZCLPAT` holds every occurrence, the linked subtrees expanded, each with its own `LISTNO`:
1,090 rows numbered 1 to 1,090 (626, plus the heart program's 185 patients under Senior Care, plus Senior Care's 274
nodes under Prevention, plus a leaf per postable node), and the not-assigned node at 999999998/999999999. A postable
node is a node of its own there, with a negative SID as a text node has but the patient's node type, and the
patient's value is its first leaf, one level deeper and before the children (`000007`: node `-19` at level 4, then
`000007`, `000011`, `000015` at level 5): BW splits the node's own facts off into a leaf.

## The hierarchy of the services

The service `ZCLSERV` (a dimension of its own in both providers, the InfoCube's `ZCLVISIT8`) is billed per visit: 52
services by a code of four digits whose first is the category (1 consultations, 2 diagnostics, 3 therapy, 4
prevention, 5 mental health), each with the care setting as attribute (telehealth remote, the rest in person). A
visit's service follows from its visit type, the chapter of its diagnosis and the patient's age, its number choosing
among a few (no random draw, the visits stay as they were); 42 services have visits, 10 have none.

Its hierarchy `ZCLSERV_CAT`, Service Catalog, is plain and holds **intervals** (`HIEINTFL` on the characteristic; an
interval is a leaf `INTERVL` = `X` named by its lower bound, its bounds in `/BIC/JZCLSERV`), no single values:

```
All Services  SERVICES
├── Consultations  CONSULT        1000-1099
├── Diagnostics  DIAGNOSTICS
│   ├── Laboratory  LAB           2000-2099
│   ├── Imaging  IMAGING          2100-2199
│   └── Functional Tests  FUNCTION  2200-2299
├── Therapy  THERAPY              3000-3049, 3050-3099
├── Prevention  PREVENTION        4000-4099
├── Mental Health  MENTAL         5000-5099
└── Care Pathways  PATHWAYS
    ├── Emergency Pathway  EMERGENCY  1010-1019 (within the consultations' interval)
    │                                 Imaging: link, with its interval 2100-2199
    │                                 3000-3049: a linked interval (the minor procedures)
    └── Cardiac Pathway  CARDIAC      2003-2004 (within the laboratory's interval)
                                      Functional Tests: link, with its interval
```

Overlapping intervals are duplicate nodes: BW refuses them, as a value within an interval, only under the same parent.
The hierarchy table has 25 nodes (11 intervals, 3 links). BW's SID structure `/BIC/IZCLSERV` expands every interval to
the values it holds when the hierarchy is activated, a row per value, all with the interval's `LISTNO` (1000-1099:
the eight consultations, `LISTNO` 3); the links are expanded too (the linked Imaging with its interval one level
deeper, the linked interval to its seven services). A value in more than one place has one more row under the root
with `LISTNO` 0 (as in `/BIC/IZCLPAT`).

Its second hierarchy `ZCLSERV_LOC`, Service Locations, is plain and has nodes of **external characteristics** (the
characteristic's "external characteristics in hierarchies", `RSDHIECHA`, `HIERARCHYCHARACTERISTICS` of
`BAPI_IOBJ_CREATE`): the site `ZCLSITE` and the room `ZCLROOM`, which is compounded with the site. Every service is in
it once, by the room it is given in (the room types of the master data); the laboratories are no rooms of the clinic,
and the partner laboratory's text node is named `NORTH`, as the site next to it is:

```
All Locations  LOCATIONS
├── North Site  NORTH (ZCLSITE)
│   ├── Room 1  NORTH     R01 (ZCLROOM)   1001-1005 consultations
│   ├── Room 2  NORTH     R02             5001-5003 mental health
│   ├── Room 3  NORTH     R03             3001-3007 minor procedures
│   ├── Room 4  NORTH     R04             3051-3055 therapy
│   └── Room 5  NORTH     R05             2101-2106, 2201-2206 imaging and functional tests
├── South Site  SOUTH (ZCLSITE)
│   ├── Room 1  SOUTH     R01             4001-4007 prevention
│   └── Room 2  SOUTH     R02             1010-1012 emergency care
├── External Laboratory  LAB             2001-2007
└── North Partner Laboratory  NORTH      2008-2010 rapid tests and cultures
```

64 nodes; the not-assigned node is shown (it holds `#` only). A node of an external characteristic is named by its key
as BW names it, the compounding first at its full length (`ZCLSITE` is CHAR 10: `NORTH     R01`, as
`RSNDI_SHIE_BW_NODENAMESCREATE4` puts it together), and has no text of its own: BW's MDX captions it by the external
characteristic's short text (North Site, Room 1, so the two sites' Room 1 have the same caption) and names it
`[NORTH     R01                   ZCLROOM]` (the name padded to 32, then the InfoObject). These nodes are the test case
of external characteristics: olap4abap's copy takes `/BIC/K`'s node name as it is (`NODE_IOBJ` `ZCLROOM`, `NODE_NAME`
the padded key, and `/BIC/K-OSID`, the external characteristic's SID, as `VALUE_SID`). Checked 2026-10-17
(`bw_hierarchy_test.py`): members, levels, children and values are BW's; such a node is named and captioned by the
external characteristic's view on that SID, named as its members are (`[ZCLSERV.ZCLSERV_LOC].[LOCATIONS].[NORTH].[NORTH/R01]`)
and captioned by its text as its members are (North Site, Northfield; Consultation Room 1), the medium text BW's
text properties give it (BW's MDX captions it by the short text). BW keys a node by InfoObject and name, so the site
`NORTH` and the text node `NORTH` are siblings: the test case of members a path of names cannot tell apart, named by the
key of their path (`...&[LOCATIONS]&[ZCLSITE]&[NORTH]` and `...&[LOCATIONS]&[0HIER_NODE]&[NORTH]`; the path of names
`[LOCATIONS].[NORTH]` finds the site, the first one). The generator gives a node the InfoObject of its parent where the
parent's name is not enough (`parent_iobjnm`).

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
random number and the visits stay as they were; a visit without physician has neither (`#/#`). The service
draws no random number either (The hierarchy of the services).

## The schemas

The schemas are the schema generator's (`docs/schema-generator.md`): per provider the run proposes the schema as
`GET proposal` does (the fiscal defaults, which concern only BW's `0FISC*`, then `ZZXXMLA1_CL_SCHEMA_PROPOSAL`) and
accepts it through the schema API (`POST accept`, catalog = provider: the views generated, the schema file written,
the catalog added). Before it deletes anything, the run removes the demo's catalogs through the API (`POST remove`,
with their files and filtered views).

So the schemas follow `docs/bw-schema-design-guide.md`: a dimension per characteristic named by its technical name and
captioned by its text (`[ZCLPAT]`, "Patient"), one flat hierarchy with an All member (`All Patient`) and one level
(`[ZCLPAT].[ZCLPAT]`), members named by the key as BW holds it (`[ZCLPAT].[002000]`; on the cube keyed by the SID, on
the aDSO by the value), the text and the display attributes (each with its text) as member properties; measures by
their technical names (`[Measures].[ZCLVISNO]`, the default measure). The room, the fiscal year and the fiscal period
are compounded: keyed by the SID on both providers, named by `COMPOUND_KEY` (`NORTH/R01`, `K4/2024001`). The cube has the date `ZCLDATE`, the aDSO BW's
`0CALWEEK`, `0CALMONTH`, `0CALQUARTER` and `0CALYEAR` (`0CALDAY` has no SID table). The proposal makes no user
hierarchies (Region > City > Patient and the like are for the UI to add) and marks no dimension as time.
The run then ticks every BW hierarchy BW serves on the providers' dimensions, as the schema builder's "BW hierarchies"
does (`tick_hierarchies`): `ZCLVISIT` and `ZCLVISITA` have `[ZCLDIAG.ZCLDIAG_ICD]`, `[ZCLPAT.ZCLPAT_PRG]` and
`[ZCLSERV.ZCLSERV_CAT]` and `[ZCLSERV.ZCLSERV_LOC]`, captioned by BW's texts, and the physician's per version at
their slice valid to 9999-12-31: `[ZCLDOC.ZCLDOC_ORG_001]`, `[ZCLDOC.ZCLDOC_ORG_002]` (Clinic Organization (Plan)),
`[ZCLDOC.ZCLDOC_SITE_001]` and `[ZCLDOC.ZCLDOC_SITE_002]`, the 2025 structures; `bw_hierarchy_test.py` compares them
with BW's MDX at key date 9999-12-31 (the probe sets it). On the aDSO, whose
facts hold the value, the closure's SIDs are mapped to the values on the characteristic's view
(`ZZXXMLA1_CL_MODEL=>bw_fact_value`).

With the InfoCube the run also deploys the **test catalog `ZCLHIER`** (`test_schema`): the InfoCube's schema with its
BW hierarchies, schema and cube named `ZCLHIER`, without olap4abap's extensions `membersWithFacts` and
`omitEmptyCells`, so it is the reference's `reference/schema/ClinicBW.xml` but for the BW hierarchies' form (compared
2026-10-17: nothing else differs). The hierarchy cases (`execute_hier_*`, `members_hier_*`, `mdschema_*_hier`) and
`ssas_compare.py` run against it. The run removes it with the demo's other catalogs: the run deletes and regenerates
the views it names, so a test catalog deployed from elsewhere would be left naming deleted views. The generator builds
everything the SAP side's tests need, as its provider checkboxes ask.

Every dimension is annotated `olap4abap.membersWithFacts` on the cube's `DimensionUsage` (`mvp-scope.md`, Members with
facts decision): its members are only those with visits, so the 300 registered patients are no members
(`scripts/clinic_test.py` checks it on both providers). The cubes are annotated `olap4abap.omitEmptyCells`.

Examples:

    SELECT [Measures].Members ON 0, [ZCLDOC].[ZCLDOC].Members ON 1 FROM ZCLVISIT

    SELECT [Measures].[ZCLVISNO] ON 0, NON EMPTY [0CALMONTH].[0CALMONTH].Members ON 1 FROM ZCLVISITA

    SELECT [Measures].[ZCLVISNO] ON 0, [ZCLPAT].[ZCLPAT].Members DIMENSION PROPERTIES [ZCLPAT].[ZCLPAT].[Text] ON 1
    FROM ZCLVISIT

    SELECT [Measures].[ZCLVISNO] ON 0, NON EMPTY [ZCLFISCPR].[ZCLFISCPR].Members ON 1
    FROM ZCLVISITA WHERE [ZCLFISCVR].[K4]
