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
- The physician `ZCLDOC` is **authorization relevant** and has the hierarchy `ZCLDOC_ORG` (see below), for working
  with BW's analysis authorizations. BW's own queries on `ZCLVISIT`/`ZCLVISITA` (RSRT, BEx, Analysis for Office) then
  need an analysis authorization that covers `ZCLDOC`; olap4abap reads the tables and checks no authorizations.
- Key figures: `ZCLVISNO` (1 per visit: the aDSO adds up visits with the same keys, so counting rows would not count
  visits), `ZCLDUR` duration, `ZCLWAIT` waiting time (minutes), `ZCLLABS` lab tests, `ZCLCHRG` charges.
- The views of the characteristics (`ZZXXMLA1_CL_BW_VIEW_GEN`), the schema files `/WEB-INF/schema/ZCLVISIT.xml` and
  `/WEB-INF/schema/ZCLVISITA.xml` and a catalog for each in `/WEB-INF/datasources.xml` (added once; the setup writes the
  data sources file if there is none).

## The hierarchy of the physicians

`ZCLDOC` has hierarchies that are **version dependent** and where the **entire hierarchy is time dependent**
(`RSDCHABAS`: `HIETABFL`, `HIEVERFL`, `HIENMTFL` set, `HIENDTFL` not; the same time dependency as the SAP demo's
`0D_NW_PROD`): one hierarchy name, and per version a hierarchy per time slice, each a row of `RSHIEDIR` with its own
`HIEID`, `DATEFROM` and `DATETO`. The generator loads `ZCLDOC_ORG` through BW's hierarchy interface
(`RSNDI_SHIE_STRUCTURE_UPDATE4`, then `RSNDI_SHIE_ACTIVATE`; `UPDATE3` dumps on the 2025 system) with four slices:

| Version | Valid | Structure |
|---|---|---|
| `001` Clinic Organization | 1000-01-01 to 2024-12-31 | Clinic > Primary Care (General Practice, Pediatrics), Specialist Care (Cardiology, Pulmonology, Orthopedics, Dermatology), Emergency Care (Emergency Medicine) > physicians |
| `001` | 2025-01-01 to 9999-12-31 | reorganised: Specialist Care > Internal Medicine > Cardiology, Pulmonology; Dermatology under Primary Care; Dr. Hana Sato (`008`) moves to General Practice, Dr. Karim Aziz (`011`) to Emergency Medicine |
| `002` Clinic Organization (Plan) | 1000-01-01 to 2024-12-31 | as version `001` |
| `002` | 2025-01-01 to 9999-12-31 | the plan: Emergency Medicine under Primary Care, no Internal Medicine, nobody moves |

The text nodes (`0HIER_NODE`) are named `CLINIC`, `PRIMARY`, `SPECIAL`, `INTMED`, `EMERGENCY` and per department `GP`,
`PED`, `CARD`, `PULM`, `ORTH`, `DERM`, `EMER`; the leaves are the physicians' keys. The attribute Department stays as in
the master data (it is not time dependent), so in 2025 it differs from the hierarchy for `008` and `011`. The run
deletes the characteristic's hierarchies before the InfoObjects.

## The data

2,000 patients, 20 physicians in 7 departments, 36 diagnoses, 33,956 visits. Patterns, so that queries show something:
fewer visits at weekends (Sundays only the emergency department), about a fifth more in winter and a quarter fewer in
August, 5% more in 2025; children go to pediatrics, cardiology and pulmonology see mostly older patients; respiratory
diagnoses are three times as frequent in winter; duration, waiting time, lab tests and charges depend on the visit type
and the diagnosis.

BW's blank member (the initial key, SID 0) is in every hierarchy, and a few visits use it: about 1% have no diagnosis
recorded yet, some emergency visits have no physician (triage) or an unidentified patient, 0.5% no visit type. Time has
no blank visits.

## The schemas

The generator writes the schemas itself, by the rules of the proposal (`docs/schema-generator.md`): on the cube a
dimension is keyed by the SID of its view and named by the value, on the aDSO keyed by the value (the fact column).

| Dimension | User hierarchies | Notes |
|---|---|---|
| Patient | Region > City > Patient (named by the patient's name; properties Sex, Birth Year, Blood Group, Insurance); `Demographics`: Age Group > Sex | City `uniqueMembers="false"` |
| Physician | Department > Physician (property Years in Practice) | |
| Diagnosis | Chapter > Group > Diagnosis | the group Influenza has one diagnosis |
| Visit Type | Care Setting > Visit Type | |
| Time (cube) | Year > Quarter > Month (named by the month) > Day, without All member, default `[Time].[2025]`; `Weekly`: Year > Week > Day | `TimeDimension` |
| Year, Quarter, Month, Week (aDSO) | none | one dimension per time characteristic, which have no attributes |

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
