# Background: how Mondrian models hierarchies and time dependency

## Hierarchies

Mondrian stores no hierarchy data. A hierarchy is declared in the schema XML and evaluated against ordinary tables with
SQL at query time.

- **Level-based hierarchy (almost everything in FoodMart):** each level is one column of a flat dimension table
  (`Store Country`, `Store State`, `Store City`, `Store Name`). Members are the distinct values per level; cell values
  come from grouping the fact table on the level columns. `uniqueMembers` says whether a value is unique on its own at
  that level or only within its parent. Optional per level: `nameColumn`, `captionColumn`, `ordinalColumn`,
  `<Property>`, `levelType` (`TimeYears`, ... enable `YTD`, `ParallelPeriod`). Levels may come from different joined
  tables (snowflake). A dimension can have several hierarchies (`[Time]` and `[Time].[Weekly]`). `hasAll` adds an
  "All" root. Ragged hierarchies use `hideMemberIf`.
- **Parent-child hierarchy:** a self-referencing column (`ParentColumn`, e.g. `employee.supervisor_id`), plus a
  `<Closure>` table listing every (ancestor, descendant) pair so a subtree can be aggregated in one SQL query. The
  closure table must be built outside Mondrian. This is the only kind that needs more than flat columns.
- The eMondrian fork adds an SSAS-style layer: `<DimensionAttribute>` per column (each also gets a single-level
  attribute hierarchy unless `attributeHierarchyEnabled="false"`) and `<Level sourceAttribute=...>`. Classic
  `<Level column=...>` still works; both produce the same SQL.

## Time dependency

Mondrian has no built-in support (no valid-from/valid-to or key-date concept in its schema); neither do SSAS or Power
BI. All use data-warehouse patterns:

- SCD type 1 (overwrite): flat table, native.
- SCD type 2 (versioned rows with surrogate keys and valid_from/valid_to): works without special support; facts point
  at the version valid when posted ("historical truth").
- As of any date: not native; Power BI uses DAX filters on a date slicer, Mondrian would need a parameterised view.

BW's time-dependent attributes (the Q table, `DATEFROM`/`DATETO`) are the "as of any date" kind: the fact row holds the
characteristic's SID and the query picks a key date (today by default). Post-MVP options:

1. Key-date view per characteristic joining the Q table with `DATEFROM <= key date <= DATETO` (key date = today behaves
   like type 1, no engine change; a different key date would be a session/connection parameter of the SQL layer).
2. Historical truth: resolve the version per fact row (range join on a date column) into a view or table - effectively
   building type 2. More expensive, probably not needed early.
