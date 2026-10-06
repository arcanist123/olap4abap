# Metadata tables (Mondrian model) - no longer used

**Since 2026-10-04 nothing reads these tables:** the model is the Mondrian schema of each catalog (a file of the
server, read by `ZZXXMLA1_CL_SCHEMA`; `docs/mvp-scope.md`, schema decision). The tables and `ZZXXMLA1_CL_MODEL_GEN`
remain in SAP (`ZZXXMLA1_CL_CREATE_TABLES` now creates only `ZZXXMLA1_FILE`) until the generator writes schema XML instead. The rules below are what
`ZZXXMLA1_CL_SCHEMA` now derives from a schema with eMondrian's attribute model.

sapcli cannot export DDIC tables, so the tables are created from code: run `ZZXXMLA1_CL_CREATE_TABLES`
(`sapcli class execute ZZXXMLA1_CL_CREATE_TABLES`). Every run deletes the five tables including their rows and creates
them again (the generator refills them). The field list is in the class; this file describes the meaning. Tables are
cross-client (no client field), delivery class A, in package `$ZZXXMLA1`. The class follows abapGit's table import
(`DDIF_TABL_PUT`, `DDIF_TABL_ACTIVATE`, `RS_DD_DELETE_OBJ` with object type `T`). Table names are limited to 14 characters.

The generator fills them from BW metadata; the engine reads only these tables. `origin` is `G` (generated) or `M`
(manual): a regeneration replaces only `G` rows.

| Table | Key | Other fields |
|---|---|---|
| `ZZXXMLA1_CUBE` | `cube_name` CHAR30 | `catalog_name` CHAR30 (the cube's InfoArea; XMLA catalog), `caption` CHAR60, `fact_table` CHAR30, `origin` CHAR1, `generated_at` TIMESTAMPL |
| `ZZXXMLA1_DIM` | `cube_name`, `dim_name` CHAR60 | `seq_no` NUMC3 (order in the cube), `caption`, `characteristic` CHAR30 (BW InfoObject), `fk_column` CHAR30 (SID column in the fact table), `sid_table` CHAR30 (`/BIC/S<char>`), `attr_table` CHAR30 (`/BIC/P<char>`), `key_column` CHAR30 (characteristic key column in both), `dim_type` CHAR10 (Standard/Time), `origin` |
| `ZZXXMLA1_HIER` | `cube_name`, `dim_name`, `hier_name` CHAR60 | `seq_no` NUMC3 (order in the dimension; key hierarchy first), `caption`, `has_all` CHAR1, `all_member_name` CHAR60, `origin` |
| `ZZXXMLA1_LEVEL` | `cube_name`, `dim_name`, `hier_name`, `level_no` NUMC3 | `level_name` CHAR60, `caption`, `key_column` CHAR30, `name_column` CHAR30, `ordinal_column` CHAR30, `data_type` CHAR10, `unique_members` CHAR1, `origin` |
| `ZZXXMLA1_MEAS` | `cube_name`, `meas_name` CHAR60 | `seq_no` NUMC3 (order in the cube, the first is the default measure), `caption`, `fact_column` CHAR30, `aggregator` CHAR10, `format_string` CHAR40, `visible` CHAR1, `origin` |

Scope follows `mvp-scope.md`: no parent-child hierarchies, time-dependency or non-SUM aggregators (`aggregator` leaves room
for them).

Several dimensions can use the same characteristic (FoodMart's Customers, Gender, Marital Status and Yearly Income all
sit on the customer characteristic), so the physical join (`fk_column`, `sid_table`, `attr_table`, `key_column`) is kept
per dimension row. There are no generated views: the SQL generator joins the SID table and the attribute table
(`OBJVERS = 'A'`) itself, using these columns. This replaces the per-characteristic view idea in
`bw-to-schema-mapping.md`. Level columns (`key_column`, `name_column`, `ordinal_column` in LEVEL) are columns of the
dimension's attribute table.

## Generator

`ZZXXMLA1_CL_MODEL_GEN` (`sapcli class execute ZZXXMLA1_CL_MODEL_GEN`) fills the tables for `ZFMSALES` from the BW
metadata (`build` returns the model, `save` replaces the cube's rows). Default rules, all derived from BW:
- characteristics of the cube (`RSDDIMEIOBJ`, InfoObject type CHA) become dimensions named like their text; time
  characteristics (type TIM) and the package dimension are not handled;
- the key is a hierarchy named like the dimension, every time-independent attribute (`RSDBCHATR`) is a further
  single-level hierarchy; the level column is the attribute's column in `/BIC/P<char>`;
- data type: dictionary type `NUMC`/`INT`/`DEC`/... is `Numeric`, everything else `String` (no boolean in BW);
- measures: key figures of the cube (`RSDCUBEIOBJ`) with standard and exception aggregation SUM, not non-cumulative;
- table and column names: `/BI0/` plus the name without its leading 0 for SAP objects, `/BIC/` plus the name otherwise;
  the fact table is `/BIC/F<cube>` (checked for customer objects only).

Result for `ZFMSALES`: 5 dimensions, 42 hierarchies (one key hierarchy and one per attribute), 42 levels, 3 measures.
The all-member name is `All <name>s`, with the name being `Dimension.Hierarchy` for attribute hierarchies and the dimension
name for the key hierarchy (checked against eMondrian by the case mdschema_hierarchies).

The field `seq_no` is not called `position`: that is a reserved word and the table would not activate (rc 8).
