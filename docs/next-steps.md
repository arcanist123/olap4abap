# Next steps

State on 2026-10-05, after the set functions, compound slicers, the aggregates and set algebra, named sets,
`Generate`, the member functions, the operators `IN`, `IS`, `MATCHES` and `Existing`, the remaining functions
(`VisualTotals`, `CurrentDateMember`, `Parameter`, ...), the native crossjoin, the member properties of levels and the
period functions: all 244 `reference/` cases pass, and of the 395 statements of Mondrian's tests that run on our schema
(`tests/mdx/applicable.json`) 394 give eMondrian's answer. The reference's own faults and olap4abap's debt are in
`known-issues.md`. Measure progress with

    python scripts/compare-applicable.py                 # eMondrian and SAP side by side, gaps grouped
    python scripts/compare-applicable.py 46 124 126      # some statements

No statement stops at a function the engine does not evaluate any more; #64 differs in the last digits of a sum
eMondrian's database adds in another order (`docs/test-strategy.md`). The run (three statements at once) takes about
two minutes; #85 takes 1 s with the native `Order` (step 8, 105 s before), #46 2.3 s with the native `TopCount` (step
9); everything else is below 10 s.

## The order from here (2026-10-16, evening)

Where things stand: texts steps 1 to 4, 6 and 7 are done; BW hierarchies steps 7.1 to 7.3 are done (members and
cells of a BW hierarchy from the copy, served on SAP's test catalog `ZCLHIER`). New today: SSAS Multidimensional
(`localhost\SSAS_MULT`) holds the clinic with `ZCLDIAG_ICD`, `ZCLPAT_PRG` and `ZCLSERV_CAT` as parent-child
dimensions related to the facts many-to-many through their closures (`scripts/build-ssas-clinic-md.py`,
`docs/environment.md`, The clinic in SSAS Multidimensional). `bw_hierarchy_test.py --ssas` passes (every member of
the three hierarchies BW's, REST_H included), a slicer of two overlapping `ZCLPAT_PRG` nodes counts their shared
visits once, and Excel shows the subtotals right over HTTP (pump on 8089, proxy backend `ssasmd` on 8088).
`capture-execute.py --ssas multidimensional` keeps its answers as cases. It is the oracle for Excel's MDX on what
neither the reference nor BW's MDX can check: shared nodes, links, postable nodes, intervals and REST_H. `ZCLDIAG_ICD`
stays the reference's (its 71 cases); in SSAS it is the control only, no cases are captured on it there. The
time-dependent `ZCLDOC_ORG` and `ZCLDOC_SITE` are served per version at their slice valid to 9999-12-31 since
2026-10-17 (step 6 below).

Checked today in Excel against olap4abap: the setup's catalogs `ZCLVISIT` and `ZCLVISITA` show the flat diagnosis
only (37 diagnoses with visits, every value and the total BW's); a BW hierarchy is in the test catalog `ZCLHIER` only,
since accept does not build them yet (step 3 below).

Next, in this order:

1. Done (2026-10-17): a test catalog on SAP with the three hierarchies: `ZCLPAT_PRG` (caption Care Programs) and
   `ZCLSERV_CAT` (Service Catalog) in `ClinicBW-sap.xml` next to `ZCLDIAG_ICD`, annotated as it is, so
   `bw_hierarchy_test.py --catalog ZCLHIER --names` runs without editing the schema (open of step 7.3): 72, 2,914 and
   92 members, all BW's. Without `--names` only the text nodes' captions differed (their technical names; the node
   texts, step 4, fixed them). No reference case names them; `ZCLPAT_PRG` moves `ZCLDIAG_ICD`'s `HIERARCHY_ORDINAL` from 4 to
   5, which `mdschema_hierarchies_hier` ignores (`ignore.txt`). `xmla_test.py` on the 75 `*_hier*` cases: all pass.
2. Excel's statements on shared nodes, checked by SSAS: a live Excel session against `ssasmd` on `ZCLPAT_PRG` and
   `ZCLSERV_CAT` (expand linked subtrees, slicers and filters on overlapping programs, drill-through on a duplicate
   leaf), captured with `--ssas multidimensional` (`execute_ssasmd_*`); a comparison that rewrites each statement into
   olap4abap's names through `data/foodmart-bw/ssas/members.json` (occurrence `&[POS]` to the path of names), runs it on
   SAP's `ZCLHIER` and compares the cell values per tuple. Taken from SSAS: values only; levels, parents, children
   counts and order are olap4abap's and BW's. SSAS's cells are `xsd:decimal` (measures `Currency`, exact), olap4abap's
   `xsd:double`. The Excel session is done (2026-10-17, `logs/xmla-proxy/20261017-110127/`, connection string with
   `Protocol Format=XML;Transport Compression=None`): linked subtrees, Expand Entire Field, duplicate leaves, the
   postable family nodes and their own leaves, REST_H, filters and slicers of overlapping programs (#0995, #0998,
   #1016) and services (#1259), intervals and the linked text node and interval, both hierarchies crossed (#1173) and
   crossed with Patient and Room, drill-throughs on a node, a duplicate leaf and a postable node's own leaf; no
   fault. Not done: label and Top 10 value filters (known issues). SSAS doubles the rows of a drill-through on a node
   (#0944, #1231; a leaf's are single): compared as distinct rows. Captured (2026-10-17): 36 cases
   `execute_ssasmd_*` (`prg_*` Care Programs, `srv_*` Service Catalog, `prg_srv_*` both crossed, `pat_prg_*`,
   `room_srv_*`, `drillthrough_*`), each the statement Excel sent, its answer's cell count Excel's; left out: member
   lists and children counts (shape, BW's), the capped drill-through #0944 and the Patient grids over 5 MB (#1195,
   #1201, #1204, #1221). `xmla_test.py` skips them (`ssas.txt`). The comparison is `scripts/ssas_compare.py`
   (2026-10-17, `test-strategy.md`): 24 of 36 pass, every drill-through, expand, slicer list and fiscal year
   slicer and the subselects on another hierarchy; every value of a tuple both answers have is SSAS's. The 12 others
   were a subselect on the axis' own BW hierarchy: olap4abap showed the members outside the subselect that share
   facts with it. Fixed the same day (`ZZXXMLA1_CL_MDX_ENGINE=>restrict_to_subcube`): a NON EMPTY axis keeps a BW
   hierarchy's members related to the members a subselect names (one of them, an ancestor or a descendant), as SSAS
   does; all 36 pass, the 372 other cases too. Only NON EMPTY axes: without, the reference keeps the others as empty
   positions on `ZCLDIAG_ICD` (`execute_hier_subselect_rows`), and where no value is shared NON EMPTY drops the same
   members. Only member sets restrict (`{}`, CrossJoin, Union); a subselect on the hierarchy by `-`, Head, Filter or
   Members does not, nor do set functions under the subselect (SSAS's restriction of `Members`, `Count`, ... there
   waits for a case).
3. Done (2026-10-17) for InfoCubes: hierarchies in the schema builder (open 5 below). Decided with the user: offered,
   not proposed: the proposal names none, its answer (and those of fix, schema and accept) lists per table the
   hierarchies `RSHIEDIR` has for the characteristic of its view (`bwHierarchies`,
   `ZZXXMLA1_CL_BW_HIERARCHY_COPY=>offered`: name, text in the logon language, supported or why not), and the
   dimension pane's "BW hierarchies" ticks them: a ticked one is a `<Hierarchy>` named by BW, captioned by its text,
   annotated `olap4abap.bwHierarchy`. Time- or version-dependent ones could not be ticked then (step 6). The schema API's check (and
   so accept) creates the copy tables of an InfoObject a ticked hierarchy names, since the schema reader reads the
   levels from the copy (a change of check, which wrote nothing before: the tables stay when the hierarchy is
   unticked). The clinic setup ticks every one BW serves (`ZCLVISIT`: `ZCLDIAG_ICD`, `ZCLPAT_PRG`, `ZCLSERV_CAT`;
   accepted so on SAP, `bw_hierarchy_test.py --catalog ZCLVISIT --names` passes). Tests: `schema_api_test.py`,
   `schema_ui_test.py`. Done (2026-10-17): a BW hierarchy on an aDSO, whose fact column holds the value, not the SID
   the closure has: the closure joins of the facts (`ZZXXMLA1_CL_MODEL=>fact_join_table`, `bw_member_condition`,
   `bw_members_condition`) map the SID to the value on the characteristic's view (`bw_fact_value`: the dimension
   table joined on `SID`, its key column the one the facts refer to); the schema reader, the UI and the clinic setup
   no longer leave aDSOs out. `ZCLVISITA` has the three hierarchies (`bw_hierarchy_test.py --catalog ZCLVISITA
   --names` passes: 72, 2,914 and 92 members as BW's); a slicer, compound slicer, subselect, label filter and
   drill-through of a node give the InfoCube's answers (the aDSO's drill-through has fewer rows of the same sum: it
   aggregates visits with equal keys).
   Done (2026-10-17): external characteristics in hierarchies. The clinic's `ZCLSERV_LOC` (Service Locations: all
   locations > site `ZCLSITE` > room `ZCLROOM`, compounded > service) has nodes of other InfoObjects; members, levels,
   children and values are BW's (`bw_hierarchy_test.py`). Done (2026-10-17): such a node is named and captioned by
   its characteristic's view, on the SID BW gives it (`/BIC/K-OSID`, the copy's `VALUE_SID`;
   `ZZXXMLA1_CL_BW_HIERARCHY_COPY=>externals`, `external_nodes_sql`): named as the characteristic's members are
   (`COMPOUND_KEY`, else `KEY_NAME`, else the key: `[LOCATIONS].[NORTH].[NORTH/R01]`) and captioned by the same text
   as its members (the preferred text, medium, else long, else short; else `KEY_CAPTION`: Consultation Room 1); a
   characteristic without a view keeps BW's node name. BW's MDX captions such a node by the short text (Room 1), but
   its text properties (`[ZCLSERV].[1ZCLSERV]`, `[5ZCLSERV]`, `[4ZCLSERV]`: short, medium, long) give the
   characteristic's texts; the probe reads them and `bw_hierarchy_test.py` compares the caption with the medium text
   (else long, else short). Without `--names` only the text nodes' captions differed (fixed by the node texts, step 4). And the clinic generator deploys
   the test catalog `ZCLHIER` (`ClinicBW-sap.xml` and its `sap-files.py deploy` are gone): a clinic run deleted the
   views the deployed file named, so the next accept was refused.
4. Done (2026-10-17): the node texts. BW keeps them in `RSTHIERNODE` (per language, `HIEID` and node name: `TXTSH`,
   `TXTMD`, `TXTLG`; the table is not `RSTHIENODE`), for the text nodes only. `levels_sql` reads the node rows
   through `ZZXXMLA1_CL_BW_HIERARCHY_COPY=>node_rows_sql` wherever the levels have a caption column: a text node is
   captioned by its English text (medium, else long, else short, as BW's MDX gives its text properties and as the
   views caption the characteristics), else by its name; read live, as the leaves' texts from the view, so the copy
   is unchanged. A postable node (the characteristic's own value) is captioned as its value in the dimension's view
   (`VALUE_SID`), as its leaf is (it was the key), and REST_H as BW's MDX captions it, `Not Assigned Service (s)`
   from the characteristic's long text in `RSDIOBJT` (`rest_caption`, read by `current`). The initial value under
   REST_H stays `''` (BW: Not assigned), the rule of `Now: texts and captions`; `bw_hierarchy_test.py` accepts it
   without `--names` now. The reference's flattened `ZZXXMLA1_HL_ZCLDIAG_ICD` and the SSAS model (`H_<h>.CAPTION`)
   caption the text nodes by the texts `build-bw-reference-db.py` now exports with the copy (`hierarchy_<h>.json`,
   `texts`). Checked: unit tests of the copy (9), `bw_hierarchy_test.py --catalog ZCLHIER`, `ZCLVISIT` and
   `ZCLVISITA` without `--names` (every caption BW's), `--reference`; 56 `*_hier*` cases recaptured (captions only),
   `xmla_test.py` 372 of 372, `ssas_compare.py` 36 of 36. `bw_hierarchy_test.py --ssas` fails on `ZCLSERV_LOC`,
   which the SSAS model has never had (not in `SSAS_HIERARCHIES`).
5. Smaller: texts step 5 (the check against blank texts); the debt that keeps hierarchy cases red on SAP (measure
   captions, member names on `sourceAttribute` levels, `known-issues.md`); `xmla_test.py` passes all 372 today.
6. Done (2026-10-17): version-dependent and entirely time-dependent hierarchies, as the texts (decided with the
   user): each version is a hierarchy of its own, its version part of the name, served at the slice valid to
   9999-12-31, no key date. BW keeps a row of `RSHIEDIR` per name, version and slice, each its own `HIEID` with one
   SID structure in `RSRHIEDIR_OLAP` (`HDATE` blank), so the copy is unchanged: `ZZXXMLA1_CL_BW_HIERARCHY_COPY=>current`
   takes the version and picks the row valid to 9999-12-31 (`c_valid_to`); a refill deletes the copies of the
   name's slices that no longer are (`delete_old_slices`). The schema names it by `olap4abap.bwHierarchy` (the
   name) and `olap4abap.bwHierarchyVersion` (the version), the `<Hierarchy>` `<name>_<version>`
   (`hierarchy_name`: `ZCLDOC_ORG_001`); `offered` lists one per name and version with the latest slice's text
   (followed by `(version)` where two versions share it) and refuses a time-dependent structure
   (`RSDCHABAS-HIENDTFL`, none in the demo) and a version without a slice valid to 9999-12-31. The schema builder
   shows the version, the clinic setup ticks all four (`ZCLDOC_ORG_001`, `_002`, `ZCLDOC_SITE_001`, `_002`).
   Checked: `bw_hierarchy_test.py --catalog ZCLVISIT`, `ZCLVISITA` and `ZCLHIER` (the probe asks BW's MDX at key
   date 9999-12-31; 34, 32, 28 and 28 members, all BW's), `schema_api_test.py` (also the refusal of a
   version-dependent one without its version), `schema_ui_test.py`'s BW hierarchy checks, unit tests of the copy,
   `xmla_test.py` 372 of 372, `ssas_compare.py` 36 of 36, `hierarchy_copy_test.py`. Open: other slices than
   9999-12-31 wait for the key date; a time-dependent structure.

Later, as noted: the key date (then the other slices of time-dependent hierarchies, and time-dependent structures); the performance risks (below, Paused:
query planning); query planning step 7.

## Now: texts and captions

Decided with the user 2026-10-16: the texts are the active work again, ahead of the rest of the BW hierarchies,
which depend on them (a leaf's name and caption are the characteristic's). Paused 2026-10-15 because a report showed
a characteristic as BW does, key and text side by side; now the text is the member's caption, the key its name.

The rules (decided 2026-10-16):

- **Names are keys, the same in every hierarchy.** A flat dimension is a hierarchy with one root: its members and a
  BW hierarchy's leaves follow the same rules, no special case for either. SSAS's convention for a key without value
  (`NullProcessing` `ZeroOrBlank`: `''` for a string, `0` for a number) applies to BW's initial value (SID 0, BW's
  "not assigned"): it is named `''` for every key type, CHAR, NUMC, DATS and TIMS alike (`[ZCLDIAG].[]`); its key
  (`MEMBER_KEY`) stays BW's value (`0000`). NUMC is a string of fixed length (SSAS `WChar`), not a number.
- **A compounded characteristic is named by its key fields separated by `/`**, compounding first, each as BW holds
  it (NUMC with its zeros), an initial CHAR part empty (`K4/2024001`, `1000/` for a blank cost centre); fully initial
  (SID 0) it is `''`, as above. Decided 2026-10-16 for the medium term, instead of BW's concatenation at full length
  (`K42024001`, CHAR parts padded with blanks): CDS cannot write blanks inside a string (tested 2026-10-16 through
  ADBC: `rpad`, `concat` and `replace` trim them in the SQL HANA runs, only `concat_with_space` with a literal count
  keeps them); the blank handling is to be investigated (Later).
- **The caption of a characteristic with texts is its text field** as configured (short, medium or long), a value
  without text `''`, the initial value too. Blank captions are the modeller's to fix, not the engine's (step 5).
- **The caption of a characteristic without texts is its key**, `#` for the initial value; a compounded one is
  captioned as `COMPOUND_KEY` names it today, the parts separated by `/` and `#` for an initial part (`K4/2024001`,
  `#/#`).
- **`Caption` means the caption column** wherever the engine compares it: `.Caption`, Excel's label filters (the
  subcube's `label_predicate`) and the native label filter (`get_level_members_where`), as SSAS does. The reference's
  patched subcube filter compares the level's column there (`scripts/patches/subcube-filter-member-caption.patch`), so
  these answers have no oracle where caption and name differ.
- **The characteristic's own text is its caption, no member property any more:** its `Text` property and its
  drill-through `(Text)` column go (to be revisited on user feedback). The key stays a member property `Key` on
  every dimension, an aDSO's too. A display attribute keeps both its properties, its key and its text: a property
  has a caption (`PROPERTY_CAPTION`) but its values have none, so its text property is the only way to show an
  attribute's text (corrected 2026-10-16). A navigation attribute's hierarchy (`<char>__<attr>`) is captioned by the
  attribute's text like any other.
- **NUMC as numbers leaves the schema builder:** "As numbers" and `intColumns` of the API go; the views keep their
  `COLUMN_INT` columns for FoodMart's schemas, which name numbers as the reference's tests do (`mvp-scope.md`, NUMC
  decision). Restored if a user needs it.

The steps:

1. Done (2026-10-16): captions in the engine, by the reference's rule (`RolapLevel.createFromXml`, `RolapDimension`,
   checked on the test catalog `ZFMCAPT`, `reference/schema/FoodmartBWCaption.xml`): a level with `sourceAttribute` is
   keyed by the attribute's `KeyColumn`, named by the level's own `nameColumn` (else by the key) and captioned by the
   attribute's `NameColumn`; an attribute's hierarchy is named by its key and captioned by its `NameColumn`; a level
   with `column` is named by its `nameColumn` and captioned by its `captionColumn`. A caption of the column that names
   the member is none. `ZZXXMLA1_CL_SCHEMA` gives a level its `caption_column` (a `captionColumn` on a level with
   `sourceAttribute`, which the reference ignores, is refused); `ZZXXMLA1_CL_MODEL=>members_of_rows` reads it after
   the name in every member read (the native reads and `cells_first` read members through it too); the engine's
   member has a `name` beside its `caption`: lookups, `.Name`, `Item` by name, calculated children and the
   hierarchize order of calculated members use the name, `.Caption`, `MEMBER_CAPTION` (axes, `MDSCHEMA_MEMBERS`) the
   caption, and `property_reference` gives `Caption` the caption column, so the subcube's label conditions and the
   native label filter compare it (`Name` the name column; the reference compares the key column there, the cases
   `execute_caption_subcube_*` take their answers from equivalent member sets, `capture-execute.py --answer-of`). A
   measure's `caption` is its caption (known issue fixed: `Visits`, not `ZCLVISNO`). `DBSCHEMA_COLUMNS` has no
   `$caption` (the reference's neither).
   Known issue 1 (members of `sourceAttribute` levels named by the attribute's `NameColumn`) is gone with it: the
   proposal writes the key attribute's `NameColumn` as the level's `nameColumn` too, so a member is named by its BW
   key on the reference and on SAP alike (the key attribute's `NameColumn` is the same column, so no caption yet);
   `ZZXXMLA1_CL_SCHEMA_FIX` rewrites a level's `nameColumn` with the attribute's, the schema builder gives a level it
   adds over an attribute the attribute's `NameColumn` as `nameColumn` and "As numbers" switches it; `ClinicBW.xml`,
   `ClinicBW-sap.xml` and SAP's accepted `ZCLVISIT`, `ZCLVISITA` and `ZXMLWIDE` got the `nameColumn`s, and the clinic
   cases were recaptured (58 answers: names by key, not SID; `execute_hier_drillthrough_subselect` names
   `[ZCLVTYPE].[Emergency]`).
   Checked: `xmla_test.py` 369 of 372 (the 26 caption cases new; of the clinic cases only
   `execute_hier_hierarchize_post` and `execute_hier_visualtotals`, `_pattern` fail, `known-issues.md`),
   `compare-applicable.py` 394 of 395 as before, `schema_api_test.py`, `fixed_selection_test.py`, `clinic_test.py`
   and `schema_ui_test.py` pass, the unit tests of `ZZXXMLA1_CL_SCHEMA`, `_MODEL` and `_SCHEMA_FIX` pass.
2. Done (2026-10-16): the views (`ZZXXMLA1_CL_BW_VIEW_GEN`), so that changing a caption needs no new view. A view
   only gains columns, none is renamed: a view is shared by every catalog whose cube has the characteristic, and
   accepting one schema regenerates it under the others.
   - every text BW has, each its own column, `coalesce( text, '' )` instead of `coalesce( text, key )` (as data, so
     the reference shows the same: it falls back to the name for a NULL caption): the characteristic's `TXTMD`,
     `TXTLG`, `TXTSH` (as far as it has them, in this order), each attribute's `<ATTR>_TXTMD`, `_TXTLG`, `_TXTSH`, and
     `<ATTR>_TXT`, the medium, else long, else short text, kept under the name views had before; the layout marks
     each text's field (`text_field`) and the one a value is shown with (`preferred`, which the provider reads);
   - `KEY_NAME`, the key with `''` for SID 0, where the key is NUMC, DATS or TIMS (CHAR's initial value is `''`
     already; also for `0FISCPER` under one fixed variant, which has no `COMPOUND_KEY` there);
   - `COMPOUND_KEY` is the name (`K4/2024001`, an initial CHAR part empty, NUMC with its zeros, SID 0 `''`), and
     `KEY_CAPTION` the form with `#` for an initial part (`#/#`);
   - `KEY_CAPTION` for every characteristic, not only those without texts (the key, `#` for SID 0), so that the
     schema editor can switch any dimension's caption to the key.
   Regenerated on SAP 2026-10-16: the plain views of FoodMart, the clinic, the wide demo and `0D_NW_C01`; the
   filtered views of `0D_NW_C01`'s fiscal defaults follow at its next accept. The schemas are unchanged, so nothing
   names the new columns yet (step 3); what changes in the answers is a blank text where BW has none (a member
   property `Text`, a drill-through `(Text)` column) and the name and caption of a compounded characteristic's
   SID 0 (`''`, was `#/#`), until the reference database's views are rebuilt (step 7). HANA holds the blanks as
   `N''` (length 0, not a space). Checked: `xmla_test.py` 368 of 372, the new failure
   `execute_hier_drillthrough_subselect` (patient `000000` and physician `000`, SID 0, have no text: their `(Text)`
   column is blank, the reference's still the key); `compare-applicable.py` 394 of 395 as before.
3. Done (2026-10-16): the proposal (`ZZXXMLA1_CL_SCHEMA_PROPOSAL`) and the schema builder: each characteristic's key attribute gets its
   text as `NameColumn` (the caption of a level with `sourceAttribute`, step 1; not a `captionColumn`, which the
   reference ignores there), the medium text, else the long, else the short one, the key caption column if it has
   none; the level's `nameColumn` stays the key (written since step 1), and so does a BW hierarchy's leaf name, which
   `ZZXXMLA1_CL_SCHEMA` takes from the key attribute's `NameColumn` today (`bw_value_name`: take the level's
   `nameColumn` instead); the name stays the key and `Key` is a member property; no `Text` property and no `(Text)` drill-through column of the
   characteristic itself, while each display attribute keeps its key and its text as properties (and its drill-through
   columns). The schema editor switches a dimension's caption between the key and each text field the view has.
   "As numbers" goes.
   Built: the provider reads the view's `KEY_NAME`, `KEY_CAPTION` and the characteristic's text columns
   (`key_name_column`, `caption_column`, `text_columns`); the level's `nameColumn` is `COMPOUND_KEY`, else `KEY_NAME`,
   else the key (`name_column_of`; an aDSO's CHAR key has none, the key names it), so SID 0 of a NUMC key is named
   `''`; the key attribute's `NameColumn` the text, else `KEY_CAPTION` (`caption_column_of`); the property `Key` on
   every dimension (on an aDSO the key attribute itself); a navigation attribute's attribute captioned by its
   `<ATTR>_TXT`, no `... Text` attribute and no `Text` property for it. `intColumns` of the API became
   `captionColumns` (`{table, column}`: `KEY_CAPTION`, `TXTMD`, `TXTLG`, `TXTSH` of a view, from the provider or the
   dictionary), the dimension pane's "Member caption" sets the key attribute's `NameColumn`, and a level the UI adds
   over an attribute is named as another level over it is. `ZZXXMLA1_CL_SCHEMA_FIX` names a characteristic whose
   compounding becomes fixed by `KEY_NAME` and leaves its caption; `ZZXXMLA1_CL_SCHEMA` names a BW hierarchy's leaves
   by the `nameColumn` of the level over the key attribute (`value_name_column`). Found on the way: a property on
   the key column read the column twice, which HANA refuses in the `ORDER BY` ("column ambiguously defined"); a
   column read again is aliased now (`ZZXXMLA1_CL_MODEL=>level_columns`). The accepted catalogs on SAP (clinic, wide
   demo) are unchanged until they are proposed again (the setup) or edited; the reference copies follow in step 7.
   Checked: the unit tests of `ZZXXMLA1_CL_SCHEMA_PROPOSAL` (19), `_SCHEMA_FIX` (8, `captions` new), `_SCHEMA` (13)
   and `_SCHEMA_API` (27) pass; `schema_api_test.py`, `fixed_selection_test.py`, `fiscal_default_test.py` (both now
   compare member names, from the unique names: the captions are texts, blank for `0FISCYEAR`) and `clinic_test.py`
   pass; `schema_ui_test.py` passes but for the fiscal defaults' period selection, which it still expects as the
   twelve-row preset (the defaults are `I BT` with five `E CP` rows since 2026-10-15, a stale test); `xmla_test.py`
   368 of 372 (the four of step 2); `compare-applicable.py` 394 of 395 as before.
4. Done (2026-10-16): the key display in the schema builder (decided with the user 2026-10-16: Excel shows only captions, it cannot
   switch between a member's name and its caption, so how a key is shown is the modeller's choice). Three modes per
   dimension, each a form of the schema, so no annotation is needed and the builder reads a dimension's mode back
   from the XML when it is reopened:
   - **text as caption, key as attribute** (the proposal's default, as step 3 writes it): the key attribute's
     `NameColumn` is the text, the property `Key`;
   - **key as caption, text as attribute**: `NameColumn` `KEY_CAPTION`, a property `Text` with the text column
     (back, in this mode only);
   - **key only**: `NameColumn` `KEY_CAPTION`, no `Text` property (and no `Key` property, which would repeat the
     caption).
   The dimension pane's "Member caption" becomes the mode plus the text field (medium, long, short) that the caption
   or the `Text` property shows. A characteristic without texts is key only whatever the mode and does not count in
   the comparison below; a schema whose dimension matches none of the three (raw XML) is "custom". The mode is the
   dimension's: its navigation attributes' hierarchies follow it (the attribute's key or its text as caption).
   On the cube pane a three-position slider sets the mode of every dimension. When the dimensions' modes differ the
   slider is greyed out at no position; a click on a position still applies, setting every dimension to it, and each
   dimension's pane can change its own mode again afterwards. The cube's mode is not stored (no annotation, decided
   with the user 2026-10-16): it is a convenience of the builder over what the schema says, read from the
   dimensions, so a dimension added later gets the default mode. The proposal writes every dimension in the default
   mode.
   Built in the UI only (`web/schema/app.js`, `keyDisplayParts`, `keyDisplayOf`, `setKeyDisplay`): no ABAP changed.
   The proposal already writes the default mode, and `ZZXXMLA1_CL_SCHEMA_FIX` touches neither the key attribute's
   `NameColumn` (but `COMPOUND_KEY` of a fixed compounding) nor the properties, and its filtered views have the same
   columns, so it keeps a dimension's mode. The text is an attribute `<C> Text` (as before step 3) keyed by the text
   field; it is made by the key modes and stays after, so a dimension switched back (key only has no property to
   remember it by) keeps its text field. A navigation attribute's hierarchy has the key as caption by having no
   `NameColumn` (its key column, no `#` for the initial value), its text then the property `Text` on `<C>__<A> Text`.
   A dimension's mode needs `KEY_CAPTION` in its view's `captionColumns` and a text: FoodMart's characteristics but
   `0CALMONTH` and `0CALQUARTER` have none, so they have no key display and keep their property `Key`. The note
   under the greyed slider counts the dimensions per mode. Checked: `schema_ui_test.py` (the month's three modes and
   text field, the slider: proposed, key only, greyed with one dimension set apart, all set back) passes but for the
   stale fiscal-period check of step 3. The server's check accepts all three forms (the test loads each one).
5. A schema check against blank texts: the schema API's `check` (and accept) reports, per dimension, the members whose
   caption is blank (a count and examples), so the modeller sees them. A warning, never a refusal (decided
   2026-10-16): a modeller who wants blank captions keeps them.
6. Done (2026-10-16): BW hierarchies: a leaf is named and captioned as the characteristic's member; text nodes keep
   their technical name, their captions (RSTHIENODE's texts) come later. `levels_sql` names a leaf by the view's
   column the level over the key attribute names the members by (`value_name_column`), SID 0 too (`c_initial_name`
   `#` is gone: `''` by `KEY_NAME`, or the view's key where a schema still names by the key), and, where the key
   attribute's `NameColumn` captions the members (`attribute_caption_column`, `bw_value_caption` of the schema and the
   model), gives each level a column `Lnn_CAPTION` (a node's `NODE_NAME`, a leaf's caption from the view, REST_H's
   rows as wide), the level's `caption_column`. The reference's flattened `ZZXXMLA1_HL_ZCLDIAG_ICD` names its
   initial leaf `''` (`build-bw-reference-db.py`, rebuilt with `--no-export`: its views stay those of before step 2
   until step 7); `execute_hier_slicer_initial` and `execute_hier_ascendants` name `[NO_DIAGNOSIS].[]`, and the 9
   cases with the initial leaf were recaptured (the name and caption `''`, nothing else changed).
   `bw_hierarchy_test.py --names` accepts `''` for the initial value (BW's MDX names it `#`). `known-issues.md`'s
   entry on `#` is gone: the initial value has one name in a cube.
   Checked: the unit tests of `ZZXXMLA1_CL_BW_HIERARCHY_COPY` (7, `leaf_names` new), `_SCHEMA` (13) and `_MODEL` (9)
   pass; `xmla_test.py` 371 of 372 (`execute_hier_drillthrough_subselect` waits for step 7; the Discover cache held
   `members_hier_all`'s old answer until `sap-files.py deploy` cleared it); `bw_hierarchy_test.py --reference` and
   `--catalog ZCLHIER --names` pass, the latter also with `ZCLPAT_PRG` and `ZCLSERV_CAT` added to `ZCLHIER` for the
   run (72, 2,914 and 92 members), with names and with the three key attributes captioned by `TXTMD` (leaves
   captioned by their texts, `[ZCLSERV.ZCLSERV_CAT].[REST_H].[0000]` by `''`).
7. Done (2026-10-16): the reference database's copies of the views rebuilt (`build-bw-reference-db.py`, a full
   export: the views of step 2), and the reference schemas `ClinicBW.xml` and `ClinicBW-sap.xml` moved to step 3's
   naming (decided with the user 2026-10-16, instead of rebuilding only the view copies), as SAP's proposal for
   `ZCLVISIT` writes it: the level named by `KEY_NAME` for the NUMC and DATS keys (patient, physician, date,
   service), `COMPOUND_KEY` for the compounded ones, else the key; the key attribute's `NameColumn` `TXTMD`; the
   property `Key` first; no `Text` attribute, property or `(Text)` drill-through column of the characteristic itself.
   The reference's flattened `ZZXXMLA1_HL_ZCLDIAG_ICD` gained `Lnn_CAPTION` (a leaf's medium text from
   `/BIC/TZCLDIAG`, '' without one; a text node's technical name), the levels' `captionColumn`, so its leaves are
   captioned as olap4abap's. The 64 clinic answers were recaptured (captions by text). Excel's label filters on the
   hierarchy (`execute_hier_excel_label_begins`, `_between`) compare captions, which the reference does not (its
   patched subcube filter compares the level's column): they got an `equivalent.txt` (Joint pain; the eight
   diagnoses whose texts lie between `E00` and `I99`). Docs: `bw-schema-design-guide.md` 1, 3.1 to 3.4, 3.6, 3.7 and
   the checklist, `test-strategy.md`; `schema-generator.md` was current.
   Checked: `xmla_test.py` 372 of 372 (`execute_hier_drillthrough_subselect` passes); `compare-applicable.py` 394 of
   395 as before; `bw_hierarchy_test.py --reference` and `--catalog ZCLHIER --names` (`ZCLDIAG_ICD`) and
   `clinic_test.py` pass.

## Then: time-independent BW hierarchies

Waits for the texts (above, decided 2026-10-16): steps 7.1 to 7.3 are done, the rest follows their names and
captions. Decided with the user 2026-10-15: the next big piece of work is BW's external hierarchies (`/BI0/H<char>`,
`/BIC/H<char>`, directory `RSHIEDIR`) that are neither time nor version dependent, ahead of planning step 7 (paused
below). Users report on BW hierarchies, and none of them can be shown today. A plain hierarchy
needs no key date, so this does not wait for one. Afterwards the key date (time-dependent attributes, texts and
navigation attributes read on a date instead of 9999-12-31; open: how a client, Excel above all, sends it), then the
other slices of time-dependent hierarchies (the clinic demo's `ZCLDOC_ORG`, `ZCLDOC_SITE`; their versions and the
slices valid to 9999-12-31 are served since 2026-10-17, the order from here, step 6).

Test cases: the clinic demo's `ZCLDIAG_ICD` (All Diagnoses > chapter > group > diagnosis, 69 nodes, plain;
`clinic-demo.md`, The hierarchy of the diagnoses) and, for shared nodes, `ZCLPAT_PRG` (care programs > program >
patient, plain: link nodes, a subtree under two parents, recursively, and patients under two programs as duplicate
and link leaves; `clinic-demo.md`, The hierarchy of the care programs) and, for intervals, `ZCLSERV_CAT` (services >
category > interval of codes: overlapping intervals, a linked text node with its interval, a linked interval;
`clinic-demo.md`, The hierarchy of the services).

BW's tables (looked at on `ZCLDIAG`): `/BIC/H<char>` is the node tree (`NODEID`, `PARENTID`, `CHILDID`, `NEXTID`,
`TLEVEL`, `LINK`); `/BIC/I<char>` (SID structure, written by BW on activation) has a row per node with its parent's
SID (`PRED`), its own (`SUCC`), its position in depth-first order (`LISTNO`), `TLEVEL`, the node type (`NTYPEID`:
5 a text node, else the characteristic's) and `FACTOR` (sign reversal), and the not-assigned node (`LISTNO`
999999998, 999999999). Neither holds ancestor and descendant pairs. Looked at on the clinic demo 2026-10-15:
`/BIC/I` holds every occurrence, the linked subtrees expanded; an interval is no row of its own but its values, each a
row directly under the interval's parent with the interval's `LISTNO` (so a `LISTNO` is unique per node but not per
leaf: a leaf occurrence is `LISTNO` and `SUCC`); and rows with `LISTNO` 0 are BW's corrections for values reached by
more than one path: per ancestor and value a row with `FACTOR` -(n-1) (-1, -2), at the ancestor's `TLEVEL`, so that
the rows of a subtree summed with their factors count each value once. BW's MDX (`bw_hierarchy_test.py`) shows a
member per occurrence, but its unique names repeat for the occurrences of a node (`[HEART<pad>0HIER_NODE]` three
times), no member for an interval, a postable node as a node whose first child is its own value, and the not-assigned
node `REST_H` (`1HIER_REST`) as a second root after the hierarchy with the values below it (`#` among them).

Decided with the user 2026-10-15:

- **Multiple parents.** A node can be under several parents, recursively: as a link node (`LINK` = `X`, no children
  of its own, BW shows its original's subtree) or, for a value of the characteristic, as a duplicate node (BW takes a
  value more than once without a link, each occurrence with children of its own). Its subtree has the same shape under
  each (decided with the user 2026-10-15): BW lets one duplicate of a value have a subtree and another have none or a
  different one, which we refuse; a link node has its original's subtree, so it always qualifies. Members are its occurrences (one per path, as BW shows it): every member has one parent,
  so `Parent`, `Ancestor` and drill-down keep their meaning, and unique names are paths, stable across rebuilds while
  the structure is (an occurrence id would change with each rebuild and break saved Excel pivots). Since 2026-10-17
  (decided with the user) the path is of keys, not of names, as SSAS names a member by a composite key: InfoObject and
  name per level, `[ZCLSERV.ZCLSERV_LOC].[Level 02].&[0HIER_NODE]&[LOCATIONS]&[ZCLSITE]&[NORTH]` (a text node's
  `0HIER_NODE`, REST_H's `1HIER_REST` as BW's MDX names it, a leaf's the characteristic). BW keys a node by InfoObject
  and name, so a text node `NORTH` and the site `NORTH` can be siblings, and a path of names could not tell them
  apart; the member's own pair alone is not enough either (a leaf under two parents is two members). Checked on SSAS
  Multidimensional with such siblings and a duplicate leaf: it names them so, finds them by the key with or without
  the level, by a path of names the first one, and gives a partial key no member (olap4abap: not found). The clinic's
  `ZCLSERV_LOC` has such siblings, the site `NORTH` and the text node `NORTH` (a partner laboratory) under
  `LOCATIONS` (2026-10-17, `bw_hierarchy_test.py` passes on `ZCLVISIT`, `ZCLVISITA` and `ZCLHIER`). The facts
  still join the closure by SID; the key only names and finds. Names and captions stay as they were. A path of names
  (`[ZCLDIAG.ZCLDIAG_ICD].[DIAGNOSES].[RESPIRATORY]`) finds the first member of each name, also in an
  `MDSCHEMA_MEMBERS` restriction (SSAS's way; the reference takes only the unique name there); the reference cases,
  whose answers name ZCLDIAG_ICD's members by the path of names, are compared through `scripts/bw_names.py`.
- **No double counting.** A node's value is the sum over the distinct values below it: a value reached by two paths
  counts once. The rows are a materialized closure `(ancestor occurrence, SID)`, distinct, which the facts join by an
  equi-join, filtered to the ancestors asked for; no range join, `DISTINCT` or hierarchy function at query time
  (100 million facts joined to a closure built in the query would not run). The All member is a closure row to every
  SID. Consequences for the engine: a parent is never summed from its children (no `roll_up`, no grouping set that
  leaves the closure column out, as for distinct count); every closure in a statement is grouped or filtered to one
  ancestor; a set of a hierarchy's members (slicer, subselect, `Aggregate`, `VisualTotals`) is one semi-join
  `sid IN (SELECT sid FROM closure WHERE ancestor IN (...))`, as BW counts a selection of nodes, not a sum per member.
- **Flattened levels** (ragged, up to 99 level columns) are ruled out: a value under two paths is two rows, and the
  facts joined to them double.
- **Depth** is at most 99. A value that is in the hierarchy twice, once as an inner node and once as a leaf, is
  refused.
- **Postable nodes** (an inner node that is a value of the characteristic and has facts of its own): the sync adds an
  extra leaf occurrence under it, named as the node, with its own facts (SSAS's `NonLeafDataVisible`), so that the
  children add up to their parent. BW's `/BIC/I` does the same already: the node gets a negative node SID and its
  value is its first leaf, before the children (`ZCLPAT_PRG`, Family Care), so the build takes the leaf from
  `/BIC/I` and adds none of its own.
- **Order:** BW's, from `LISTNO`; a shared subtree keeps its original's order. Members are never read as a whole
  hierarchy into ABAP (Member decision in `mvp-scope.md`): children by parent, descendants by the depth-first
  range, a level by depth, all in SQL on the node table, ordered by the stored number.
- **The build** stays in the database, never row by row through ABAP: the node table (occurrences, shared subtrees
  expanded, depth, depth-first number and subtree end) and the closure by `INSERT ... SELECT` (the closure in one
  statement, a range join over `LISTNO`: a node's subtree ends before the next row at its level or above; the rows
  with `LISTNO` 0 and the not-assigned rows left out; a node's distinct values cross-checked with BW's: its leaf rows
  plus its correction rows' factors). It is lazy: a query compares the hierarchy's current row of `RSRHIEDIR_OLAP`
  (`SVER`, `TIMESTMP`) with the copy's (one key read) and refills a stale hierarchy under an enqueue lock
  (`ENQUEUE_E_TABLE` on the directory table, decided with the user 2026-10-15): another query that resolves the
  hierarchy waits for the lock, so it reads a consistent state. No limit on occurrences: shared subtrees are expanded
  whatever their size (a limit was considered and not agreed). The refusals (a duplicate value with another subtree,
  a value both an inner node and a leaf, more than one current row of `RSRHIEDIR_OLAP`) are faults of the query that
  resolves the hierarchy.
- **Where the copies live** (decided with the user 2026-10-15): a node table and a closure table per InfoObject,
  holding all of its hierarchies, as BW's `/BIC/I<char>` does. Not one table pair for all hierarchies of all
  InfoObjects (it would grow beyond what HANA handles well) and not a table pair per hierarchy. They are DDIC
  tables (decided with the user 2026-10-15; plain database tables created through ADBC need HANA's enterprise license
  and are hard to transport), generated in `$TMP` as the views are and found by the generator through a registry
  table as `ZZXXMLA1_VIEW` (a DDIC table name has at most 16 characters, so the names are generated). They are
  created when a schema that names a hierarchy of the InfoObject is accepted, never by a query: a query only refills
  them. They are client-independent, as BW's hierarchy tables are (no `MANDT`).
- **Ids are BW's** (decided with the user 2026-10-15): every inner node occurrence has its own negative node SID in
  `/BIC/K<char>`, also the occurrences inside an expanded link subtree (`ZCLPAT_PRG`: the link SENIOR -13, the HEART
  and FALLS under it -14 and -15, `LINKNO` 2 and 1), the postable nodes and `REST_H`; node SIDs are unique per
  InfoObject across its hierarchies. A leaf has the characteristic's SID, so a leaf occurrence is (parent node SID,
  SID). No ids of our own: unique names stay paths of BW's keys (InfoObject and name, above), and a rebuild takes
  BW's numbering as it is.
- **The All member and the hierarchy key** (decided with the user 2026-10-15): `RSRHIEDIR_OLAP` gives each
  hierarchy its own virtual root `ROOTSID`, not-assigned leaf `RESTLEAFSID` and `REST_H` node `RESTTOPSID`, in the
  same per-InfoObject range (`ZCLDOC`: -2, -16, -31, ... for its eight hierarchies). The All member is the `ROOTSID`,
  a node like any other with closure rows to every SID below it, so the closure needs no hierarchy key; the node
  table's hierarchy column is `ROOT_SID` (roots are the children of `ROOTSID`, a level is `ROOT_SID` and depth).
  `HIESID` is no key: `RSRHIEDIR_OLAP` can have several rows per `HIESID`.
- **Versions** (decided with the user 2026-10-15): BW's `SVER` is a read-consistency version: while a hierarchy is
  changed, its previous structure stays under the old `SVER` for the queries running, and `RSRHIEDIR_OLAP` points
  new ones to the new version. The current version is the row of `RSRHIEDIR_OLAP` with `DELETETIMESTMP` 0; the old
  one keeps its row with `DELETETIMESTMP` set to when it was replaced (`COPY_OF_ZCLSERV_CAT`, `HIESID` 246: `SVER`
  1 deleted at 16:36:21, `SVER` 2 written then, node -22 moved under -23). Both versions are in `/BIC/I` (120 rows
  each); `/BIC/K` has no `SVER`, so the versions share their node SIDs (a moved node keeps its SID), and `ROOTSID`
  and the rest SIDs stay. The build reads `/BIC/I` of the `HIESID` and `SVER` of the current row only. The copy does
  the same, because HANA's read consistency is per statement, not per query: both tables have BW's version in
  their keys (node table: `HIESID`, `SVER` and node occurrence; closure: `HIESID`, `SVER`, ancestor and SID), the build writes a new
  version next to the old one, commits and switches the hierarchy's directory row (`ROOT_SID`, current version, the
  `HIESID`, `SVER` and `TIMESTMP` it was built from); a query reads the directory row once and binds the version in
  each statement; an old version is deleted by the build after next. For now the build refuses a hierarchy whose
  current rows (`DELETETIMESTMP` 0) are more than one (rows with `SVER` `?`, `TMPJOIN`, `HDATE` or a negative
  `HIESID`, as on `0D_FC_PERS`, are not understood yet).
- **Statements and HANA's plan cache** (decided with the user 2026-10-15): HANA reuses a plan only for the same
  statement text, and a statement on a view is compiled with the view's definition, so literals in a statement mean
  a compile each time. The hierarchy statements bind their single values (`?`, `cl_sql_statement->set_param`, new in
  `ZZXXMLA1_CL_SQL`): children `PARENT_SID = ?`, a level `ROOT_SID = ? AND DEPTH = ?`, descendants `ROOT_SID = ? AND
  POS BETWEEN ? AND ?`, a leaf's value `SID = ?`, the version. Lists stay literals for now (`ANCESTOR_SID IN (-5,
  -7)`), as in the rest of the engine; padding lists to fixed lengths was considered and set aside.
- **Interval leaves** (`/BIC/J<char>`) are no members: their values are leaves under the interval's parent, as BW
  shows them. The build takes them from `/BIC/I`, which holds them expanded as they were when the hierarchy was
  activated (`ZCLSERV_CAT`), not from `/BIC/J`.
- **Not assigned** (values of the master data under no leaf) is a configuration of the hierarchy, as in BW (shown or
  suppressed), read live by a view (`closure UNION ALL` the rest node with every SID that is no leaf), so that it
  follows master data loads without a rebuild. The schema and the UI offer no switch for it (decided with the user
  2026-10-15): the copy follows the hierarchy's own setting in BW (its attribute Suppress 'Unassigned' Node).
- **Several hierarchies on one characteristic** are allowed: they are more hierarchies of its dimension, next to the
  flat one and the navigation attributes'; one on its All member needs no closure.
- **Sign reversal** (`FACTOR`) is out of scope.
- **Portable SQL:** no HANA-only features (BW's cached column hierarchy views, hierarchy functions, CDS
  hierarchies): plain tables and standard SQL, so that the engine can later run on another database (Later: DuckDB).
- **Demo:** the clinic demo gets a hierarchy with shared nodes (link nodes, recursively), a postable node and an
  interval leaf. Done: the shared nodes and postable nodes (`ZCLPAT_PRG` on the patient) and intervals,
  overlapping and linked (`ZCLSERV_CAT` on the service).

Part one (agreed with the user 2026-10-15): the copies. The node, closure and directory tables (created on
accept), their refill from `/BIC/I` and `/BIC/K` on a stale `RSRHIEDIR_OLAP` row under the lock, the refusals, and
the not-assigned values as the hierarchy's BW setting says; everything the queries need to read a hierarchy
consistently. The schema, the names, the engine and the UI (open 2 to 5) build on it.

Done (2026-10-15): `ZZXXMLA1_CL_BW_HIERARCHY_COPY` (`create_tables`, `current`, `values_of`), the directory
`ZZXXMLA1_HIEDIR` (a row per copy, keyed by `HIEID`, `HIESID` and `SVER`, with the `TIMESTMP` it was copied from)
and the registry `ZZXXMLA1_HIETAB` (an InfoObject's tables `ZZXXMLA1H` and `ZZXXMLA1C` and its not-assigned view
`ZZXXMLA1R`, DDL source `ZZXXMLA1_R`, followed by the same 7 digits; `create_tables` makes objects of an older layout
or with one missing again under their names), bound parameters in
`ZZXXMLA1_CL_SQL` (`params`, `execute`), the fault `ZZXXMLA1_CX_BW_HIERARCHY`. `python
scripts/hierarchy_copy_test.py`: the four plain hierarchies of the clinic demo copy and pass the cross-check with
BW, a second run refills none (a query's check of a current copy: 4 to 9 ms), and node rows and not-assigned values
are the members BW's MDX shows. Settled while implementing:
- A copy is keyed by BW's `HIESID` and `SVER` (decided with the user 2026-10-15, for analysing a copy next to
  `/BIC/I`): both tables start with them, in place of a version of our own and the node table's `ROOT_SID` column
  (children `HIESID = ? AND SVER = ? AND PARENT_SID = ?`, a level `... AND DEPTH = ?`, descendants `... AND POS
  BETWEEN ? AND ?`). BW does not change a structure once its `SVER` is written; a change, also of the not-assigned
  setting, is a new `SVER` (up to 33 per hierarchy, then given again), and a time-dependent hierarchy has a `HIESID`
  per time slice. So the staleness check compares `HIESID` and `SVER` only.
- Built first and replaced by the decisions below: the closure had rows of inner node occurrences only, and the
  not-assigned values were a statement of the class (`values_of` the `RESTTOPSID`). Switching the setting makes a new
  `SVER` (`COPY_OF_ZCLSERV_CAT`: `SVER` 3 without the rows of `LISTNO` 999999998 and 999999999).
  `RSRHIEDIR_OLAP-CARDREST` is no count of the not-assigned values (0 on `ZCLSERV_CAT`, where BW's MDX shows `#`
  under REST_H as the copy does).
- BW's correction rows are cumulative: a node's distinct values are its leaf rows plus the factors of the correction
  rows of the node and of every inner node below it (`ZCLPAT_PRG`'s PROGRAMS: 1,071 rows, -439 at it, -154 below,
  478 values). The virtual root has none, so it is not cross-checked.
- Accept does not create the tables yet: the schema does not name BW hierarchies before open 2; until then the test
  creates them.

Decided with the user 2026-10-15 and built the same day (`python scripts/hierarchy_copy_test.py`: the four plain
hierarchies pass; every leaf value has its identity row, the All member's values are the table's ones plus, where the
node is shown, the view's not-assigned ones):
- **Identity rows.** The closure has a row (`ANCESTOR_SID` = `SID`) for every leaf, so that every member, node or
  leaf, is an ancestor and every fact read is the same join (facts to the closure on `SID`, filtered on `HIESID`,
  `SVER` and `ANCESTOR_SID IN (...)`, grouped by `ANCESTOR_SID`), never a read for the nodes and another for the
  leaves. Leaf SIDs are positive, node SIDs negative, so they never meet.
- **Not assigned is a view, one per InfoObject.** It is generated and registered with the InfoObject's tables on
  accept, also for an InfoObject none of whose hierarchies shows not assigned (its live part is empty then). The
  closure table holds everything about the assigned values, of every hierarchy alike: the nodes' rows, the root's
  rows and the leaves' identity rows; a hierarchy that suppresses not assigned and one that shows it have tables of
  the same shape. The view is the table's rows and, for every hierarchy of the InfoObject that shows not assigned
  (`RSHIEDIR-NORESTNODES` blank), three rows per SID of the SID table under no leaf of the hierarchy: the
  not-assigned node to it (`REST_TOP_SID`), the root to it (`ROOT_SID`) and its identity row. These SIDs are one
  anti-join, the SID table left-outer-joined to the root's rows of the closure (no `DISTINCT`: the closure's key
  lists each SID below the root once) where none is found (7.50's CDS has no `NOT EXISTS`); the hierarchies and their
  `HIESID`, `SVER`, `ROOT_SID` and `REST_TOP_SID` come from the directory, so the view has no parameters, follows a
  new `SVER` once the directory names it, and follows master data loads without a refill. The directory is joined to
  the SID table on `s.sid > d.root_sid`, true for every pair (node SIDs are negative), as 7.50's CDS has no cross
  join; the anti-join compares `NORESTNODES <> 'X'`, not with a blank literal, which HANA would not trim. No row of the view is
  twice. The executor reads the table for a hierarchy that suppresses not assigned and the view for one that shows
  it (the directory row says which). HANA pushes a filter on `ANCESTOR_SID` through the union and the joins, so a
  query that does not ask for the not-assigned node pays next to nothing for the anti-join (to be measured). The
  members of the not-assigned node are no rows of the node table: REST_H is a root after the hierarchy's roots, as
  BW's MDX shows it, and the member reader takes its values, in key order, from the view's rows of `REST_TOP_SID`.
  They are directly below REST_H, one level deeper (decided with the user 2026-10-15): BW gives them the hierarchy's
  deepest level (level 4 below REST_H on level 0 in `ZCLPAT_PRG`), which would skip levels, where a parent-child
  hierarchy has every member one level below its parent, as the reference models it and Excel lays levels out;
  `bw_hierarchy_test.py` accepts this difference for the not-assigned values only.

  Example: InfoObject `ZTEST` with three SIDs, the initial value and two values, and two hierarchies of the same
  structure, a text node `TOTAL` with the value `A` below it; `ZTEST_SUPP` suppresses not assigned, `ZTEST_SHOW`
  shows it. BW's node SIDs are negative and per InfoObject (`ROOTSID`, `RESTLEAFSID`, the nodes, `RESTTOPSID` of
  each hierarchy, as `RSRHIEDIR_OLAP` and `/BIC/K` give them).

  SID table `/BIC/SZTEST`:

  | SID | `/BIC/ZTEST` |
  |----:|--------------|
  |   0 | (initial, `#`) |
  |   1 | `A`          |
  |   2 | `B`          |

  BW's SID structure `/BIC/IZTEST` (`FACTOR` 1 throughout; the not-assigned rows of `ZTEST_SHOW` abbreviated to the
  link from the root to REST_H, BW writes some more with internal SIDs and none for `ZTEST_SUPP`):

  | HIESID | SVER | LISTNO    | PRED        | SUCC | TLEVEL | NTYPEID              |
  |-------:|------|----------:|------------:|-----:|-------:|----------------------|
  |     10 | 1    |         0 | -2000000101 |   -2 |     00 | (root)               |
  |     10 | 1    |         1 |          -2 |   -4 |     01 | 5 (text node)        |
  |     10 | 1    |         2 |          -4 |    1 |     02 | `ZTEST`'s            |
  |     11 | 1    |         0 | -2000000101 |   -6 |     00 | (root)               |
  |     11 | 1    |         1 |          -6 |   -8 |     01 | 5 (text node)        |
  |     11 | 1    |         2 |          -8 |    1 |     02 | `ZTEST`'s            |
  |     11 | 1    | 999999998 |          -6 |   -9 |     01 | (not assigned)       |

  Directory `ZZXXMLA1_HIEDIR` (a row per copy, keyed by `HIESID` and `SVER`):

  | HIESID | SVER | HIENM        | TIMESTMP       | NORESTNODES | ROOT_SID | REST_TOP_SID |
  |-------:|------|--------------|----------------|-------------|---------:|-------------:|
  |     10 | 1    | `ZTEST_SUPP` | 20261015120000 | `X`         |       -2 |           -5 |
  |     11 | 1    | `ZTEST_SHOW` | 20261015120000 |             |       -6 |           -9 |

  Node table `ZZXXMLA1H...` (`PARENT_SID` 0 for the virtual root, the All member):

  | HIESID | SVER | PARENT_SID | SID | DEPTH | POS | END_POS | NODE_IOBJ    | NODE_NAME | VALUE_SID |
  |-------:|------|-----------:|----:|------:|----:|--------:|--------------|-----------|----------:|
  |     10 | 1    |          0 |  -2 |     0 |   0 |       2 |              |           |         0 |
  |     10 | 1    |         -2 |  -4 |     1 |   1 |       2 | `0HIER_NODE` | `TOTAL`   |         0 |
  |     10 | 1    |         -4 |   1 |     2 |   2 |       2 |              |           |         0 |
  |     11 | 1    |          0 |  -6 |     0 |   0 |       2 |              |           |         0 |
  |     11 | 1    |         -6 |  -8 |     1 |   1 |       2 | `0HIER_NODE` | `TOTAL`   |         0 |
  |     11 | 1    |         -8 |   1 |     2 |   2 |       2 |              |           |         0 |

  Closure table `ZZXXMLA1C...`, the same for both hierarchies:

  | HIESID | SVER | ANCESTOR_SID | SID | row                  |
  |-------:|------|-------------:|----:|----------------------|
  |     10 | 1    |           -2 |   1 | root                 |
  |     10 | 1    |           -4 |   1 | `TOTAL`              |
  |     10 | 1    |            1 |   1 | identity of `A`      |
  |     11 | 1    |           -6 |   1 | root                 |
  |     11 | 1    |           -8 |   1 | `TOTAL`              |
  |     11 | 1    |            1 |   1 | identity of `A`      |

  The view: the six rows of the table and, for `ZTEST_SHOW` only, the SIDs under no leaf, 0 and 2 (`ZTEST_SUPP`'s
  directory row has `NORESTNODES` `X`, so it adds nothing):

  | HIESID | SVER | ANCESTOR_SID | SID | row                        |
  |-------:|------|-------------:|----:|----------------------------|
  |     11 | 1    |           -9 |   0 | not assigned (REST_H)      |
  |     11 | 1    |           -9 |   2 | not assigned (REST_H)      |
  |     11 | 1    |           -6 |   0 | root                       |
  |     11 | 1    |           -6 |   2 | root                       |
  |     11 | 1    |            0 |   0 | identity of `#`            |
  |     11 | 1    |            2 |   2 | identity of `B`            |

  So `ZTEST_SUPP` (read from the table) is All {1} > `TOTAL` {1} > `A` {1}, and `ZTEST_SHOW` (read from the view)
  is All {0, 1, 2} > `TOTAL` {1} > `A` {1}, then REST_H {0, 2} > `#` {0}, `B` {2}. The cells of `TOTAL`, REST_H and
  `B` of `ZTEST_SHOW` are one statement: the facts joined to the view on `SID`, `HIESID = 11 AND SVER = '1' AND
  ANCESTOR_SID IN (-8, -9, 2)`, grouped by `ANCESTOR_SID`.
- **Copies live as long as BW's versions.** BW keeps an old `SVER` (its row of `RSRHIEDIR_OLAP` with
  `DELETETIMESTMP` set) until no query needs it, so the copy keeps a copy for every `(HIESID, SVER)` that has a row
  in `RSRHIEDIR_OLAP`, current or old, and deletes a copy once BW's row is gone, checked at every refill under the
  lock. A query pinned to an old `SVER` keeps its copy as long as BW keeps its own, however many changes (up to 33)
  came in between. The directory gets a row per copy, keyed by `HIESID` and `SVER`, with the `TIMESTMP` it was
  copied from, instead of a row per hierarchy with the `SVER` before. Built with `HIEID` before them in the key
  (a `HIESID` belongs to one hierarchy): DDIC activation refuses to make the old key field `HIEID` a non-key field
  while the table has rows, and adding key fields after it needs no conversion. BW gives an `SVER` again only after its row is
  gone; a copy whose `HIESID` and `SVER` are BW's current row's but whose `TIMESTMP` is not is of an earlier use of
  that `SVER`, and is deleted and refilled. A query reads BW's current row as now and the copy of its `HIESID`,
  `SVER` and `TIMESTMP`, refilled if there is none. (This replaces deleting the `SVER` before at the next refill and
  the rows of the same `SVER` before a refill, which could delete a copy a query still reads.)

Open:

1. Answered 2026-10-15 on `ZCLPAT_PRG`: `/BIC/I` holds the shared subtrees expanded, every occurrence with its own
   `LISTNO` (613 nodes, 1,072 numbered rows; with the postable nodes since, 626 and 1,090), so the closure is one
   statement (with intervals: see BW's tables above).
   Test (2026-10-15): `python scripts/bw_hierarchy_test.py` compares olap4abap's members of the three hierarchies with
   BW's MDX, asked live (`ZZXXMLA1_CL_BW_HIERARCHY_PROBE`), position by position: level, children, caption, values
   (`test-strategy.md`, BW hierarchies). BW's side passes its own checks; olap4abap's fails until the hierarchies are
   served (`[ZCLDIAG.ZCLDIAG_ICD]` not found).
2. The schema: `parentColumn` with `<Closure>` as the reference models it, with our extensions (the closure's child
   is the SID, members are occurrences); `ZZXXMLA1_CL_SCHEMA` refuses both today. Members are on the levels by depth
   (decided 2026-10-16, reference scenario below). The reference can be the oracle for hierarchies with a level form
   only (as a level hierarchy, the reference scenario below); for shared nodes, BW's own MDX
   (`ZZXXMLA1_BW_AUTH_PROBE`).
3. Done (2026-10-17, order step 4 above): names and captions of nodes: a text node's name is its technical name, a
   leaf's the characteristic's key; a text node is captioned by its `RSTHIERNODE` text, a leaf and a postable node by
   the view, REST_H as BW's MDX.
4. The engine: members of a parent-child level and the closure in the fact reads; the planner marks such members
   computed at first, so the evaluator answers them, native and grouped reads later.
5. Done (2026-10-17, order step 3 above), aDSOs too: the proposal and the UI offer the hierarchies a characteristic
   has in `RSHIEDIR` (no not-assigned switch: the hierarchy's setting in BW holds).
6. Measure HANA's plan cache (`M_SQL_PLAN_CACHE`: entries, `PREPARATION_COUNT`, `TOTAL_PREPARATION_TIME` against
   `TOTAL_EXECUTION_TIME`): a statement on a view with two literals and with a bound parameter, and the share of
   preparation in a FoodMart run. It decides whether the engine's fact and member reads move to bound parameters and
   whether lists need more than literals.
7. The other rows of `RSRHIEDIR_OLAP` (`SVER` `?`, `TMPJOIN`, `HDATE`, negative `HIESID`s): what they are, before
   time-dependent hierarchy structures.

### Reference scenario: the clinic's hierarchies in the reference server

Proposed 2026-10-15 (the user: a reference scenario for hierarchies without duplicates, link nodes and intervals, run
in the reference server, to validate against). `bw_hierarchy_test.py` compares members and their values with BW's
MDX, but BW's MDX knows little of the MDX the engine has to answer on a hierarchy (`Descendants` with flags,
`Ancestor`, `DrilldownMember`, `VisualTotals`, subselects and slicers of nodes, `NON EMPTY`, crossjoins, drill-through,
the schema rowsets). A hierarchy in which every node occurs once is a parent-child hierarchy with a closure table as
the reference models it (FoodMart's `Employees`), so the reference answers all of it, as it does for FoodMart. It is
built before the engine (open 4), so the engine is developed against it, and BW's MDX stays the oracle for what
the reference cannot model: shared nodes (`ZCLPAT_PRG`), intervals (`ZCLSERV_CAT`), postable nodes (the reference
shows a member's own facts in its value, BW as a first child of its own) and later time and versions.

- **Hierarchy:** `ZCLDIAG_ICD` (69 nodes, shows not assigned). The copy maps one to one: node SIDs are negative, value
  SIDs positive, so `SID` of the node table is a key; `PARENT_SID` is the parent; the closure's `(ANCESTOR_SID, SID)`
  is the reference's `<Closure parentColumn childColumn>`, its `SID` the fact's `SID_ZCLDIAG`. The reference's
  members are paths as ours (`[Employees].[Sheri Nowmer].[Derrick Whelply]`), and every member one level below its
  parent, the not-assigned values below REST_H too (as decided above). Its All member counts every fact, so a
  hierarchy that suppresses not assigned would differ there. Decided with the user 2026-10-15: the reference is the
  oracle of the narrow case, single-parent trees that show not assigned; a hierarchy that suppresses it is validated
  against BW's MDX only.
- **Reference database:** `build-bw-reference-db.py` gets the InfoCube `ZCLVISIT` next to `ZFMSALES` (`CUBES`): its
  fact table, the SID and attribute tables of its characteristics, the views its accepted schema names, and the copy
  of `ZCLDIAG` (node table and the not-assigned view `ZZXXMLA1R...`) with the `HIESID` and `SVER` current at the
  export. Per hierarchy two reference views over them, under placeholder names as the characteristic views have
  (`ZZXXMLA1_HN_ZCLDIAG_ICD`, `ZZXXMLA1_HC_ZCLDIAG_ICD`; not `ZZXXMLA1_C_`, the characteristic views' prefix): the
  nodes without the virtual root, a root's parent `NULL`, REST_H and the not-assigned values added, a node's name
  (`NODE_NAME` of a text node, the key from the characteristic's view for a value); and the closure rows of the
  hierarchy. Captured data, not live, as the clinic data is static anyway: one script exports BW's side and builds
  the reference (decided with the user 2026-10-15), so a regeneration of the demo or of its hierarchies is one run of
  it (and new captures where answers change).
- **Schema:** the reference's own schema `reference/schema/ClinicBW.xml`, plain parent-child: a `Hierarchy` of the
  dimension `ZCLDIAG` with a level `column="SID" parentColumn="PARENT_SID" nameColumn="NAME"` on the node view and
  its `<Closure>` on the closure view; not SAP's schema (decided below).
- **Cases:** catalog `ZCLVISIT` in the reference's `datasources.xml`, cases captured with `capture-execute.py`
  under `reference/` and replayed by `xmla_test.py`: `MDSCHEMA_HIERARCHIES`, `_LEVELS`, `_MEMBERS` (tree operators)
  of the hierarchy; `Members`, `Children`, `Parent`, `Ancestor`, `Descendants` (levels, distances, flags),
  `DrilldownLevel`, `DrilldownMember`, `Hierarchize`, `IsLeaf`, `Level.Ordinal`, `VisualTotals`, `Aggregate` of nodes;
  `NON EMPTY` and crossjoins with the physician and the visit type; a node in the slicer, in a subselect (Excel's
  filter on a hierarchy) and in a compound slicer; Excel's queries on the hierarchy (captured from Excel against the
  reference); `DRILLTHROUGH` on a node. Before capture, the reference's values of every member are checked against
  BW's MDX (`bw_hierarchy_test.py`'s BW side), so the export is known to be BW's hierarchy.
- **Later:** a second single-parent hierarchy only if a case needs one the clinic's lacks (a hierarchy of unequal
  depth, a root with values of its own), made in the clinic generator, not in the reference database.

Decided with the user 2026-10-15: the InfoCube `ZCLVISIT` (the simpler export, no reporting view; the hierarchy is
the characteristic's, the same on the aDSO); single-parent hierarchies that show not assigned only; the export is
automated (above).

Decided with the user 2026-10-15 too: the reference's schema is its own (`ClinicBW.xml`, plain parent-child, no
annotation); SAP serves the schema the proposal makes (open 2), and the test compares the answers of the catalogs of
the same name. On SAP olap4abap reads the hierarchy from the copy at BW's current version, not from the frozen views.

Done (2026-10-15): the reference serves `ZCLDIAG_ICD`.
- Export: `build-bw-reference-db.py` exports `ZCLVISIT` (its fact table, the SID, attribute and text tables the
  characteristics' views read, the views) and the copy of `ZCLDIAG` at BW's current version (`HIESID` 43, `SVER` 1:
  70 node rows, 183 rows of the not-assigned view), and builds `ZZXXMLA1_HN_ZCLDIAG_ICD` (nodes: `SID`,
  `PARENT_SID`, `NAME`, `POS`; REST_H's value of the initial value is named `#`, as BW's MDX names it) and
  `ZZXXMLA1_HC_ZCLDIAG_ICD` (closure: `ANCESTOR_SID`, `SID`, without the virtual root's rows).
- Schema: `ClinicBW.xml` is SAP's accepted schema of `ZCLVISIT` without annotations and with the placeholders, plus
  the hierarchy `[ZCLDIAG.ZCLDIAG_ICD]` (caption Diagnoses by ICD-10 Chapter, All member `All Diagnoses by ICD-10
  Chapter`): one level `ZCLDIAG`, `column="SID" parentColumn="PARENT_SID" nameColumn="NAME" ordinalColumn="POS"`
  (BW's order of siblings), its `<Closure parentColumn="ANCESTOR_SID" childColumn="SID">`. The dimension has no
  `table`: the reference gives every hierarchy of a dimension with a table that table (`RolapHierarchy`), so each
  hierarchy names its own, the flat one first, so that the drill-through's attributes bind to the characteristic's
  view. Open 2 (the proposal's form) has these names to match.
- Check: `bw_hierarchy_test.py --reference` passes: the reference's 71 members (and its All member, the provider's
  total) are BW's in depth, children, name, values and order. BW is asked on the aDSO, which holds the same visits.
- Cases: 60, captured with `capture-execute.py` and `capture-case.py`; 1,212 of their cells recomputed from the
  exported facts and the closure, all the same, and the NON EMPTY rows complete. Excel's queries are the shapes Excel
  sent through `xmla-proxy.py` before (pivot rows, expand, crossjoin, item path, filter list, children count, member
  search, slicer), applied to the hierarchy; the live Excel session against the reference is below (it fails).
- What the reference answers on a parent-child level: every member is on the one level (`LNum` 1, its `DEPTH` the
  depth), `MDSCHEMA_LEVELS` shows the hierarchy as `Level 01` to `Level 04`, `PrevMember`/`NextMember` step to the
  member of the same depth in hierarchy order, a compound slicer or an `Aggregate` of a node and a member below it
  counts that member twice (the reference sums the tuples, as Microsoft's `Aggregate` does for Sum: "the sum of values
  over the set", only Distinct Count counts a member and its children once; olap4abap does the same, and Excel
  multiselects with subselects, which count every fact once). It has no `IsLeaf` and no
  `IsAncestor` (`Children.Count = 0` and `Ascendants` stand in for them in the cases).
- Fixed in the reference (2026-10-16, `scripts/patches/parent-child-closure.patch`, `docs/environment.md`): a
  subselect of a node (Excel's filter on a hierarchy) constrained the facts to the node's own key, so a node had no
  facts (`{RESPIRATORY, J06}` kept J06 only), and a drill-through of a node gave no rows (a leaf's gave them). Now a
  node in a subselect is its own key and the keys of its descendants on the fact's column, and a drill-through is
  constrained by the closure as the cell is. 8 more cases: `execute_hier_subselect` (`_node_leaf`, `_rows`,
  `_nested`, `_minus`, `_excel`) and `execute_hier_drillthrough` (`_subselect`); their values checked against the
  same members in the slicer and on the axes, a drill-through's rows without `MAXROWS` against its cell (834). A
  binary `-` (`{All} - {node}`) in a subselect is not understood by the reference on any hierarchy (only Excel's
  unary `- {...}`), so it is not a case.
- Excel against the reference (2026-10-16, through `xmla-proxy.py`, catalog `ZCLVISIT`): Excel cannot work with the
  hierarchy there. Rows of the hierarchy show the All member's children, and expanding DIAGNOSES works; expanding a
  chapter then changes nothing. Excel puts every expanded member into one `DrilldownMember({DrilldownLevel({All})},
  {DIAGNOSES, RESPIRATORY, ...})`, as it does for members of one level, because the reference answers every member
  with `LNum` 1; the chapters are not in the first set, so none is expanded, and Excel shows them at DIAGNOSES' depth
  without +. Expand Entire Field sends `DrilldownLevel({DrilldownLevel({All})}, [ZCLDIAG.ZCLDIAG_ICD].[Level 01])`,
  the level `MDSCHEMA_LEVELS` lists, and the reference fails: "MDX object '[ZCLDIAG.ZCLDIAG_ICD].[Level 01]' not
  found" (its schema has one level `ZCLDIAG`; only its rowset shows the levels by depth). The session stopped there.
- Decided with the user 2026-10-16:
  - The reference is the oracle for everything but parent-child hierarchies. It is patched only to fix an answer
    that is wrong by its own rules with a small fix (as `parent-child-closure.patch`), never to change its model
    (levels by depth in its parent-child engine would be that). Changed later that day (with the user): the
    reference is not patched any more; its patches stay, and an answer it gets wrong waits for SSAS, the spec for
    hierarchies and Excel's behaviour (step 6).
  - olap4abap serves a BW hierarchy as SSAS serves a parent-child one: unbalanced, nothing hidden, every member one
    level below its parent and on the level of its depth (`Level 01` the roots, `LNum` the depth), which
    `MDSCHEMA_LEVELS` lists and MDX resolves; so Excel nests `DrilldownMember` per level and `DrilldownLevel` of a
    level works. Excel handles unbalanced hierarchies; it does not hide the members of a ragged level hierarchy
    (`HideMemberIf` needs `MDX Compatibility=2`, Excel sends 1), which olap4abap does not need. Excel integration is
    ours, with SSAS as the spec; Excel cannot connect to BW's XMLA.
  - A BW hierarchy with a level form is served by the reference as a balanced level hierarchy instead of a
    parent-child one, so the reference answers Excel's statements and lays members out by depth as olap4abap does.
    `ZCLDIAG_ICD`: `Level 01` the real root DIAGNOSES and REST_H, `Level 02` the chapters, `Level 03` the groups,
    `Level 04` the diagnoses; under REST_H one placeholder member `REST_H` on `Level 02` and one on `Level 03`, the
    not-assigned values on `Level 04`. Nothing is hidden: the reference's ragged hierarchies are weak where two
    levels in a row are hidden (`RaggedHierarchyTest`'s Vatican tests are disabled, they return a `[null]` member),
    and Excel would show placeholders anyway. The real tree must be balanced (the build fails otherwise, no padding
    outside REST_H). REST_H's branch differs from olap4abap's (its values one level below REST_H, decided
    2026-10-15, and unique names without placeholders), so no case looks inside it (a whole level's members start
    from DIAGNOSES); REST_H's value and the All member's total stay in the cases. Its branch is checked against BW's
    MDX by `bw_hierarchy_test.py`.
  - BW's MDX is the oracle for what has no level form: shared nodes (`ZCLPAT_PRG`), intervals (`ZCLSERV_CAT`),
    postable nodes; their subselects are checked as the node in the slicer, their drill-throughs by the facts' count
    under the closure. The reference gets no export of these hierarchies.
- Next (the reference as a level hierarchy):
  1. Done (2026-10-16): `build-bw-reference-db.py` builds `ZZXXMLA1_HL_ZCLDIAG_ICD` (`hierarchy_levels`, computed
     from the exported copy) instead of the copy's node and closure tables and the views `ZZXXMLA1_HN_`/`_HC_`: a
     row per value SID (37: 36 diagnoses and `#` under REST_H), per level `Lnn_SID` (the key, the node's SID; REST_H's
     placeholders -37), `Lnn_NAME` and `Lnn_POS` (rank among its siblings in BW's order; REST_H 2 on `Level 01`). It
     fails if a leaf of the real tree is not at the depth of the others, a text node is a leaf, a node occurs twice,
     a value has children or a value of the SID table has no row.
  2. Done (2026-10-16): `ClinicBW.xml`'s `[ZCLDIAG.ZCLDIAG_ICD]` has the levels `Level 01` to `Level 04` on
     `ZZXXMLA1_HL_ZCLDIAG_ICD` (`column` `Lnn_SID`, `nameColumn`, `ordinalColumn`), deployed with the jar. The
     reference answers `DrilldownLevel(..., [ZCLDIAG.ZCLDIAG_ICD].[Level 01])` (Expand Entire Field) and nested
     `DrilldownMember` with `LNum` the depth.
  3. Done (2026-10-16): `bw_hierarchy_test.py --reference` passes (70 members, the All member the total): it leaves
     out what is below REST_H on both sides and its children count, so only REST_H's value is compared there.
  4. Done (2026-10-16), but for three Excel cases: 64 of the 67 cases recaptured. 41 changed only in their levels
     (`LNum`, `LName`, `PARENT_LEVEL`, `MDSCHEMA_LEVELS`; `Level.Ordinal` is the depth). 16 requests were rewritten
     because they named the old level `[ZCLDIAG]` or looked inside REST_H's branch:
     - `Level 01` to `Level 04` take the old level's place.
     - `[REST_H].[#]` is left out.
     - `[ZCLDIAG.ZCLDIAG_ICD].Members` became `Except(... .Members, Descendants([REST_H], 1, SELF_AND_AFTER))`, and
       a level's members are taken `Except` REST_H's members on that level, so the request means the same on
       olap4abap, where REST_H's values are one level below it.
     - `members_hier_all` is DIAGNOSES with its descendants (`TREE_OP` 24); `members_hier_level` is `Level 01`.
     `members_hier_children_rest` is dropped. Every cell of a member answered before and now is the same as before
     (values checked when they were captured).
     Changed by the model, not by the rewrite:
     - VisualTotals members have their real `DEPTH` (the parent-child form gave 1).
     - `members_hier_descendants` (`TREE_OP` 16) gives the whole subtree.
     - The Discover tree operators come in the reference's order.
     Left for the Excel session: `execute_hier_excel_search` and `_slicer_count` (they name the old level) and
     `_item_path_rest` (inside REST_H's branch); Excel's own statements replace them. Against the reference
     `xmla_test.py` passes 337 of 344 cases: those three and the `session_*` cases, which fail there by design.
  5. Done: the reference does not need `parent-child-closure.patch` any more (the user, 2026-10-16).
  6. Done (2026-10-16, `logs/xmla-proxy/20261016-091021/`): rows, expanding member by member, two chapters,
     collapsing, crossjoin, show items with no data, the tree filter, Keep Only/Hide (item paths of a group and of a
     diagnosis), the Filters area, the slicer (Excel offers no level choice: the count is `Level 01`'s), search (the
     level is chosen at the ▼ of the search box, not by Select field) and the label filters on `Level 04` work, their
     values checked against the same members in the slicer. New cases from Excel's statements:
     `execute_hier_excel_search` (now `J` on `Level 04`), `_search_level03`, `_search_pick` (a ticked search hit),
     `_label_begins`, `_label_between`, `_slicer_count` (now `[Level 01].allmembers.count`) and `_item_path_leaf`
     (J20; `_item_path_rest` is dropped, it was inside REST_H's branch). Against the reference `xmla_test.py` passes
     345 of 348, all but the `session_*` cases. Postponed until SSAS is available (decided with the user; the
     reference stays the oracle for the rest):
     - Expand Entire Field: the reference answers with duplicates (nested `DrilldownLevel(..., [Level 01])` to
       `[Level 03]`: 203 tuples of 75 members);
     - the Top 10 value filter: refused (`Generate(... AS [XL_Filter_Set_0], ...)`: "MDX object '[XL_Filter_Set_0]'
       not found");
     - a label filter on an upper level (contains `RESP` on `Level 02`, `Filter([Level 02].AllMembers, InStr(...))`
       in a subselect): every cell empty, the All member's too, where RESPIRATORY has 9,900 visits; the same filter on
       an axis and the label filters on `Level 04` are right (`subcube-filter-label.patch`,
       `Query.getCurrentMemberPropertyReference`). olap4abap answers it since 2026-10-17 (9,900;
       `execute_hier_excel_label_upper`).
     Original plan: repeat the live Excel session against the reference (rows, expand a member, expand entire field, crossjoin,
     the tree filter, Keep Only Selected Items, search, Filters area, slicer, label and value filters, double-click)
     and capture the statements it sends as cases.
  7. The engine (open 4) serves members on the levels by depth; the level-dependent expectations then hold on SAP,
     and Excel against olap4abap (port 8082) is the last check.
     1. Done (2026-10-16): the annotation, the levels and the test catalog. A `<Hierarchy>` annotated
        `olap4abap.bwHierarchy` names a BW hierarchy (`RSHIEDIR-HIENM`, value only, decided with the user); its
        InfoObject is the characteristic of the dimension's table (a placeholder or a view registered in
        `ZZXXMLA1_VIEW`, `ZZXXMLA1_CL_BW_VIEW_GEN=>characteristic_of_view`), and it has no `<Level>`.
        `ZZXXMLA1_CL_SCHEMA` reads the copy's `current` when it reads the schema (a refusal fails the catalog) and makes
        `Level 01` to `Level nn` from `ZZXXMLA1_CL_BW_HIERARCHY_COPY=>depth` (the deepest node row; 2 at least when
        REST_H is shown), keyed by the dimension's key column (the SID), and `ty_hier-bw_hierarchy` keeps the copy;
        `ZZXXMLA1_CL_MODEL` carries it, counts a level's members in the copy (`level_cardinality`: the node rows of
        that depth, REST_H and its values when shown) and refused a read of its members until step 7.2. The test catalog is `ZCLHIER` on both sides (decided with the user: SAP's `ZCLVISIT` is the
        demo's, annotated, and a cube name is one cube of the server): the reference's catalog and cube renamed, the
        71 cases rewritten (names only; all pass against the reference), `reference/schema/ClinicBW-sap.xml` on SAP
        (`sap-files.py deploy`; the dimension `ZCLDIAG` has its table there). `mdschema_hierarchies_hier` and
        `mdschema_levels_hier` pass on SAP. Fixed on the way: a property given twice in a request (12 captured
        requests carry `Catalog` twice) has its last value, as in the reference's `DefaultXmlaRequest` (a map).
     2. Done (2026-10-16): the members of a BW hierarchy from the copy. Not by reads of their own: the copy is a
        level hierarchy to the model, so every member read the engine has (children, a level, by name, key or path,
        `Lag`/`Lead`, ranges, children counts) works on it unchanged. `ZZXXMLA1_CL_MODEL=>member_table` of such a
        hierarchy is the derived table `ZZXXMLA1_CL_BW_HIERARCHY_COPY=>levels_sql`: a row per member occurrence,
        node or leaf, with per level of its path `Lnn_SID`, `Lnn_NAME` and `Lnn_POS` (read up the parents, a join per
        level: an inner node's SID is its occurrence's), the levels below it NULL, so a member is on the level of its
        depth; a level read and a children count ask for the level's column not NULL. Names: a node's `NODE_NAME`, a
        leaf's key from the dimension's view (`#` for the initial value, as BW's MDX), unique names the paths of
        names; order BW's (`POS` the ordinal). REST_H, when shown, follows the roots, its values (the closure's rows
        under it) below it by name. The schema's levels are these columns, `uniqueMembers` false on a level where a
        SID repeats (`repeated_levels`: a leaf under two parents). The 10 `members_hier_*` cases and the two Excel
        cases that list members only (`execute_hier_excel_filter_children`, `_filter_roots`) pass on SAP;
        `ZCLPAT_PRG` (links, postable nodes, duplicate leaves, REST_H) and `ZCLSERV_CAT` (intervals) read every level
        with the copy's `level_cardinality`. A fact read joining such a hierarchy fails with "The cells of the BW
        hierarchy ... are not supported yet" (`ZZXXMLA1_CL_MODEL=>fact_join_table`): 54 `execute_hier_*` cases.
        Also found: `Hierarchize(..., POST)` is not evaluated yet (`execute_hier_hierarchize_post`), and
        `execute_hier_drillthrough_subselect` names `[ZCLVTYPE].[2]` by key (`known-issues.md`, `sourceAttribute`).
     3. Done (2026-10-16): the cells through the closure, in the fact reads themselves rather than by marking the
        members computed, so every path of the engine (the evaluator's batches, `fast_cells`, the native crossjoin,
        `TopCount` and `Order`, `NonEmpty`, drill-through) reads them. `ZZXXMLA1_CL_MODEL=>fact_join_table` takes the
        level a statement groups or filters the hierarchy by and joins, for a BW hierarchy, the members of that level
        (`levels_sql`'s rows whose level column is set and the one below NULL) to the closure on `ANCESTOR_SID`, the
        closure's `SID` as the dimension's key column: a fact joins each member of the level it is below once, the
        groups by the `Lnn_SID` path columns and the constraints on them are the engine's as for any level
        hierarchy. A hierarchy's All member joins nothing. Members in a predicate (the subcube, a compound slicer, a
        drill-through's cell) are a semi-join `f.fk IN ( SELECT "SID" FROM closure WHERE ... "ANCESTOR_SID" = <its
        SID> )` (`bw_member_condition`); a label condition is one on the members' table, each member joined to the
        closure by its own SID (`bw_members_condition`). `ZZXXMLA1_CL_MDX_FACTS` never derives a BW member from
        others: `roll_up` only between patterns of the same BW levels (`bw_pattern`), `load_sets` a statement per
        such pattern (a grouping set must not aggregate over a joined BW hierarchy), no defaults of a BW hierarchy
        in `load`, `keys_with_facts` only from groups of the same level; the engine's `grid_axes` (cells first)
        refuses a BW hierarchy's axis; the native operands read a level's members with its column set. A
        drill-through's BW member restricts the rows by the closure, its levels are no star columns (a `RETURN` of
        one is a fault for now). Fixed on the way: a drill-through whose items name columns but no measure (the
        default action of the clinic's schemas) selected the cell's measure, the reference does not
        (`DrillThroughCellRequest.includeInSelect`). Checked: `xmla_test.py` 301 of 348 (all 277 other cases pass);
        of the 73 hierarchy cases 26 pass and 70 have the reference's cells and axes (`execute_hier_drillthrough`
        now passes); 30 fail only on the measure caption and the others on `sourceAttribute` names
        (`known-issues.md`), `execute_hier_drillthrough_subselect` on `[ZCLVTYPE].[2]`, and
        `execute_hier_hierarchize_post` waits for `Hierarchize(..., POST)`. `compare-applicable.py` 394 of 395 as
        before. Shared nodes, links, postable nodes, intervals and REST_H, which no reference case has, against
        BW's MDX: `bw_hierarchy_test.py --catalog ZCLHIER --names` with `ZCLPAT_PRG` and `ZCLSERV_CAT` added to
        `ZCLHIER`'s schema for the run (annotated as `ZCLDIAG_ICD`), all members' values BW's (72, 2,914 and 92
        members). The test read an empty cell's value from the next cell (fixed; it accepts `#` for the initial
        value with `--names` and has `--catalog`). Open: a test catalog on SAP with the three hierarchies, so the
        BW check runs without editing the schema (done 2026-10-17, the order from here, step 1); the measure caption (30 cases); a BW hierarchy on an aDSO (done
        2026-10-17, the order from here, step 3); Excel against olap4abap.
        Done (2026-10-16): `Hierarchize(..., POST)` (`hierarchize` with `post`: each member's key ends with
        U+FFFF, so an ancestor sorts after its descendants), and a visual total's `CHILDREN_CARDINALITY` is the
        one of the member it stands for (`VisualTotalMember.getPropertyValue`; it was 0). Checked: `xmla_test.py`
        371 of 372 (`execute_hier_hierarchize_post`, `execute_hier_visualtotals` and `_pattern` pass;
        `execute_hier_drillthrough_subselect` fails on the blank texts of the views until the reference's copies
        are rebuilt, texts step 7), `compare-applicable.py` 394 of 395 as before.
- Simplified (2026-10-16, with the user): the reference cannot be the oracle of REST_H (it needed placeholders and the
  cases kept out of its branch), so it no longer pretends to be. `ZCLDIAG_ICD` assigns every value explicitly, the
  initial one (337 visits) as the leaf `#` under the chapter `NOT_RECORDED` (Not recorded) and the group
  `NO_DIAGNOSIS` (No diagnosis), and suppresses the not-assigned node (`NORESTNODES`, set by the clinic generator).
  This supersedes "single-parent trees that show not assigned" (2026-10-15) above: the reference serves only
  hierarchies that suppress REST_H and assign every value (`build-bw-reference-db.py` refuses others); REST_H is
  checked against BW's MDX on `ZCLPAT_PRG` and `ZCLSERV_CAT`. Done: the clinic demo regenerated (its run now deletes
  the hierarchy copies first, `ZZXXMLA1_CL_BW_HIERARCHY_COPY->delete_tables`, whose not-assigned views blocked BW's
  deletion of the InfoObjects), the copies refilled (`hierarchy_copy_test.py`: 37 leaves, read from the closure
  table), the reference rebuilt (37 rows, no placeholders) and `bw_hierarchy_test.py --reference` passes (72
  members; the All member found by `MEMBER_TYPE`). The 14 requests that named REST_H were rewritten:
  `Except(... .Members, Descendants([REST_H], ...))` is `.Members` again, a level's members are the level's, REST_H
  as a node is `[DIAGNOSES].[NOT_RECORDED]`, and `Ascendants` and the slicer take the leaf `#`
  (`execute_hier_slicer_rest` is now `execute_hier_slicer_initial`). All 71 cases recaptured.
- Decided (2026-10-16, with the user): the hierarchy's form in the schema (open 2) is a `<Hierarchy>` with the
  annotation `olap4abap.bwHierarchy` naming the BW hierarchy and no `<Level>`; the schema reader makes `Level 01` to
  `Level nn` from the copy's depth. The 71 cases run on SAP against a test catalog, as `ZFMDRILL` is one: `ClinicBW.xml`
  with the hierarchy in that form and no olap4abap annotation (`membersWithFacts`, `omitEmptyCells`), deployed with
  `sap-files.py deploy`; the demo's own `ZCLVISIT` has them since the schema builder offers them (2026-10-17, open 5).
- SAP's schema of `ZCLVISIT` is `ClinicBW.xml` but for the hierarchy and the annotations (compared 2026-10-16), yet
  olap4abap names members of a `sourceAttribute` level and shows measure captions differently from the reference:
  debt (`known-issues.md`), which the hierarchy cases on SAP will show until it is paid.

## Paused: query planning

Paused 2026-10-15 before step 7 (decided with the user): BW models what users report as stored key figures, so a
calculated measure over a whole large grid is not a common case; time-independent hierarchies come first.

Decided 2026-10-14 (`query-planning.md`): a planner between the validator and the engine marks every node static,
relational or computed; the static and relational parts are answered from the schema, the member reads and grouped
SQL (`GROUPING SETS`, measured on HANA in the note), and the evaluator runs only for the computed ones. Every step
keeps the answers: both test suites give the same answers with planning on and off.

0. Done (2026-10-14): baseline at 3b4ef55. `xmla_test.py`: 272 of 274 cases pass; `dbschema_schemata` and
   `session_discover_schemadata` fail because the server's `/WEB-INF/datasources.xml` lists more catalogs than the
   capture (`0D_NW_C01`, `1BW_C01`, `NWCOMPANY`, `NWPRODUCT`, the clinic demo's), not the engine.
   `compare-applicable.py`: 394 of 395 the same, #64 as known; 157 s with 3 workers, SAP 291 s in total, slowest #333
   41.9 s, #263 17.3 s, #264 15.5 s, the rest below 7.1 s.
1. Done (2026-10-14): the marking, `ZZXXMLA1_CL_MDX_PLANNER` (static, relational, computed per node; the plan of
   the axes, the slicer and the cells), 19 unit tests on `ZFMSALES`; used by the engine since step 2. The rules are in
   `query-planning.md`, The marking.
2. Done (2026-10-14): all-relational queries. Decided with the user: `cross_values` of `ZZXXMLA1_CL_MDX_FACTS` is
   extended (no parallel reader): it takes all the patterns of the axes' combinations and reads the ones no segment
   covers with one `GROUP BY GROUPING SETS` statement (`load_sets`; `GROUPING_ID` tells the sets apart, the WHERE is
   the OR of their constraints, a group outside its own set's constraint is dropped; one pattern, or more than 62
   columns, as before). The planner runs in `execute` right after `resolve_query`; when the plan of the query is
   relational (`ZZXXMLA1_CL_MDX_ENGINE=>planning`, the switch, on by default):
   - the axes are evaluated as before, but a NON EMPTY axis is not filtered by `non_empty_axis`; its cells filter it
     (`remove_empty_positions`). Kept where that would keep other positions (`axis_filter_needed`: a calculated
     measure in the query, or a member of another axis outside its hierarchy's non-All default member, Time's 1997
     with `[Time].[1998]` on the columns), and where the axes are evaluated once per root member of a hierarchy
     without All member;
   - `fast_cells` reads all combinations with one `cross_values` call, and a compound slicer of plain, disjoint
     tuples (at most 200, the measure not varying) is a predicate of every read, its tuples ORed (`compound_predicate`,
     the drill-through's `slicer_predicate`; read without the cache). Overlapping tuples (`{[Q1], [Q1].[1]}`) are
     still rolled up by the evaluator.
   Tests: unit tests `grouping_sets` and `slicer_predicate` (facts), `planning_on_and_off` (engine: six statements
   the same with the switch on and off). With planning on and off (the switch deployed both ways):
   `xmla_test.py` 272 of 274 (the two datasources cases), `compare-applicable.py` 394 of 395 (#64), SAP 271 s and
   269 s in total. HANA's plan cache shows the `GROUPING SETS` statements, the filter list's as in
   `query-planning.md`, and #218's compound slicer as one read with `CA OR OR`. Not changed: the evaluator's reads
   while the axes are evaluated (`DrilldownLevel`'s context members, the native crossjoin, TopCount, Order).
3. Done (2026-10-14): one read per group (`query-planning.md`, One read per group). Decided with the user: no runtime
   switch for planning (the unit test `planning_on_and_off` compares), the engine's unit tests `DURATION LONG`, and
   BW's master data for every fact is assumed (the grouped statements join every dimension of their patterns). The
   facts roll a pattern up from a finer segment read before; a one-axis relational query's read of members with facts
   also sums under the default members it leaves out (the filter list: one fact statement); NON EMPTY axes that
   `axis_filter_needed` finds are filtered by groups of the same `cross_values` call, the evaluator only for a
   calculated measure of the query; a set without constraint is read alone, a column constrained to all its keys with
   facts not constrained, one grouping set a plain `GROUP BY`; `fast_cells` no longer copies the axes per group and
   formats each value once, and the shortest digits of a double are no longer computed with `decfloat34` logarithms.
   The trace records the SQL statements of each call and their time (`sql_count`, `sql_ms` of `ZZXXMLA1_TRACE`, shown
   on the trace page); `python scripts/planning_measure.py` measures. Filter list 175 to 148 ms, pivot 196 to 185 ms,
   `[Time].[1998]` case 134 to 122 ms, the 1,001 x 1,001 grid from an ICM timeout to 17 s; `xmla_test.py` 272 of 274
   (the two datasources cases), `compare-applicable.py` 394 of 395 (#64; #35 differed once in a parallel run, the same alone, with its
   neighbours and after a restart of eMondrian), SAP 196 to 216 s in total (271 s).
   Left over (`query-planning.md`, Open): the grid's 17 s are ABAP (rows to groups and values about 7 s, placing
   them 5 s, writing 633,830 cells, 119 MB; values are formatted only for `FORMATTED_VALUE` now, 16.7 s); a
   calculated measure in a NON EMPTY query still filters its axis with the evaluator (step 5).
4. Cells first (decided with the user 2026-10-14, `query-planning.md`, Cells first): a query whose NON EMPTY axes
   depend on the facts only (Excel's grid of two characteristics) is one fact statement; its axes are built from the
   result (positions from the keys, totals summed), its cells written from the rows in ordinal order, without the
   axis reads, the group cache and the cell table. The answer's text is benchmarked (`scripts/answer_text_probe.py`,
   `query-planning.md`, Cells first): one string template per cell, UTF-8 in parts of 10,000 cells appended to the
   response (2.2 s to about 1 s for 633,830 cells; no simple transformation: the cell properties are dynamic and
   sapcli cannot sync one). Part 1 done (2026-10-14): the answer is UTF-8 parts from the writer to the response, the
   grid 13.4 to 12.2 s runtime (15.0 to 14.3 s wall); `xmla_test.py` 272 of 274, `compare-applicable.py` 394 of 395
   (#64). Part 2 done (2026-10-14): the cells-first path (`ZZXXMLA1_CL_MDX_ENGINE=>cells_first`,
   `ZZXXMLA1_CL_MDX_FACTS=>grid`) for at most two NON EMPTY axes of a level's members with facts each (`DrilldownLevel`
   of the All member, `Level.Members`, the All member's `Children`); the grid 12.6 to 3.5 s runtime (14.8 to 5.6 s
   wall), the filter list one fact statement as before; `xmla_test.py` 272 of 274, `compare-applicable.py` 393 of 395
   (#64; #46 differed once in the parallel run, the same alone and with its neighbours). Left over: crossjoins and
   `Descendants` on an axis, NON EMPTY axes with a non-All member, filters and ranks (`query-planning.md`, Cells
   first, Open).
5. Done (2026-10-15): mixed queries (`query-planning.md`, Mixed queries): `load_aggregations` reads a pass's misses
   with one `load_sets` call, widened (the computed grid's cells statement 16.8 to 0.9 s), and `prefetch_cells` reads
   the cells' stored inputs in their own context with one `cross_groups` call before the first pass, so that pass is
   the only one. The 1,001 x 1,001 grid with a calculated measure 232 to 108 s, the rest the evaluator's pass per
   cell; `xmla_test.py` 272 of 274, `compare-applicable.py` 394 of 395 (#64). Left over: formulas per group instead of
   per cell, the NON EMPTY filter by the evaluator with a calculated measure.
6. Done (2026-10-15): more set nodes relational (`query-planning.md`, Set nodes by groups): `Filter` of a crossjoin
   of level members by a condition of stored measures is one statement (`RolapNativeFilter`, `native_filter`, only
   conditions false for every tuple without facts, so the answer is the evaluator's), `NonEmpty` (also with a second
   set) one `cross_groups` read and a lookup per pair (`non_empty_groups`). `Filter` of the 10,281 customers 2.4 s to
   0.18 s, of 100,000 members 18.3 to 3.7 s, `NonEmpty` with a second set 1.7 to 1.0 s; `xmla_test.py` 272 of 274,
   `compare-applicable.py` 394 of 395 (#64).
7. Paused (2026-10-15, see above): formulas per group (decided with the user 2026-10-15): a calculated measure whose formula is
   arithmetic of stored measures of its own cell (`[Store Sales] - [Store Cost]`, `[ZXMLAKF] * 2`; no navigation, no
   other member) is computed once per group from the groups the cells' statement read, not by the evaluator per cell
   (the 1,001 x 1,001 grid with such a measure: 108 s, nearly all of it the evaluator's pass at about 100 µs per
   cell; the stored measure's grid 3.5 s). First in ABAP from the groups: `ZZXXMLA1_CL_MDX_FORMAT` stays the one
   formatter, and empty cells, division by zero and errors keep the reference's semantics. Later, for the simple
   operators, as a SQL expression of the grouped statement in HANA, once the mapping of MDX's empty and number
   semantics to SQL is settled. Also: the NON EMPTY filter of a query with such a measure from the groups, not by
   the evaluator (`filter_by_evaluator`). Tests: the computed grid measured with `planning_measure.py`, mixed
   statements of `planning_on_and_off`, both suites.

### Performance risks: reporting that is hard to push down (noted 2026-10-16)

Raised by the user 2026-10-16; hierarchies stay first. The engine pushes down a cell that is a stored measure summed
over keys (native crossjoin, `cross_values`, cells first, native `TopCount`/`Filter`/`Order`); what falls back to
the evaluator per cell or per tuple in ABAP is the risk. Common Multidimensional reporting that does, most frequent
in BW and finance first:

1. Calculated measures on large NON EMPTY grids (margin %, variance to plan, price x quantity on a tabular-form
   table of 4-6 fields): one calculated member switches `fast_cells` and cells first off, and NON EMPTY evaluates
   the formula for every combination. Step 7 above, then the formula as a SQL expression of the grouped statement.
2. Time calculations (YTD, rolling 12 months, prior year, growth %): `Sum(PeriodsToDate(...))`,
   `Sum(LastPeriods(12, ...))` are a set aggregate per cell; to SQL as window functions or range joins.
   `ParallelPeriod` is one more batch and cheaper.
3. Distinct counts (customers, patients, documents): not additive, no `roll_up`, a `COUNT(DISTINCT)` per level and
   subtotal (`GROUPING SETS`); refused today (`check_aggregator`).
4. Non-cumulative key figures (stock, balances, headcount): the value at a period is the opening balance plus the
   movements, last value over time, not sum; BW's reference point and markers. A running sum per combination in
   HANA; refused today.
5. BW hierarchies with sign reversal and formula nodes (P&L, balance sheet): the closure join sums; a sign per node
   is a signed closure (sign x amount through the closure, in HANA), a formula node a calculation. To design with
   the BW hierarchies.
6. Top-N per group (`Generate(..., TopCount(...))`, Excel's Top 10 with a row field) and `Rank()` per tuple: the
   native `TopCount` runs once per group; `ROW_NUMBER() OVER (PARTITION BY ...)` in one statement.
7. Value filters and sorts on calculated measures (margin < 10 %, sort by variance): the native `Filter` and `Order`
   take stored measures only; the expression compilation of 1 covers them.
8. Ratios to parent or total: the parent's cells come in the same batch, two grouped reads and a division per cell
   in ABAP; fine for hundreds of rows, slow for 100,000.
9. Excel: Expand Entire Field on a large level, "Show items with no data" (no NON EMPTY: the whole crossjoin, up to
   the result limit), and every click resending the whole query with no cell cache across requests (the Discover
   cache only).

Next when this resumes: measure before optimising, with about ten reports shaped like finance reporting rather than
the reference's tests (a margin-% grid, YTD against prior year, top 5 per group, a distinct count, a value filter
on a ratio, a wide tabular-form list) on `ZXMLWIDE` and the clinic, timed with the trace (`planning_measure.py`) and
the planner's computed nodes listed. Expected most gain for the effort: 1, 2 and 7 (arithmetic and time windows
compiled to SQL); 4 and 5 are the large BW-specific pieces to scope early.

## Paused: fixed selections

Not a priority since 2026-10-14; the open steps (13, 19, 20, and 21's fiscal hierarchy) wait.

Decided 2026-10-13; the model is in `bw-schema-design-guide.md`, section 3.8. A cube fixes characteristics of its
provider to one value each (`0FISCVARNT = K4`); a characteristic whose compounding is all fixed is then not
compounded (`0FISCPER` named `2024001`), and the fixed characteristic is a dimension with one member. The selection
is in generated views, the engine is not changed. Since 2026-10-13 fixing is an edit of the schema (steps 9 to 12
below), no longer a parameter of the proposal; a default selection in the proposal (the only variant with facts,
...) is open.

1. Done: table `ZZXXMLA1_VIEW` (kind, object, selection; view and DDL source), `src/zzxxmla1_view.tabl.xml`.
   `ZZXXMLA1_CL_BW_VIEW_GEN` finds and registers views through it, a plain view of an older run by its description.
2. Done: views with a selection: a characteristic's view filtered on its fixed compounding (no `COMPOUND_KEY` when all of
   it is fixed); a provider's fact view filtered on the fixed characteristics, on an InfoCube too (inner join to the
   SID tables), with `SID_<field>` only for the characteristics still compounded.
3. Done (replaced by steps 9 to 11): provider and proposal: `ZZXXMLA1_CL_BW_PROVIDER=>read` and the proposal take the selection; the proposal drops
   the fixed dimensions, treats the fully fixed compounded ones as plain and writes the annotations
   `olap4abap.fixed.<characteristic>` on the cube. A value without SID, or a compounded characteristic fixed without
   its compounding, is refused.
4. Done (the selection moved to `POST fix`, step 10): API: `GET proposal?provider=X&fixed.<characteristic>=<value>`; accept generates the views of the cube's selection
   for the placeholders; check refuses views of another selection than the cube's annotations and a dimension shared
   by cubes with different selections; accept and remove delete the views with a selection no schema file names.
5. Done: test data. The clinic demo has its own fiscal time in `ZCLVISIT` and `ZCLVISITA` (`clinic-demo.md`): the
   variant `ZCLFISCVR` (K1, K2, K4, each visit under one), the period `ZCLFISCPR` and the year `ZCLFISCYR` compounded
   with it. Not BW's `0FISC*`: BW checks their values against the source system's fiscal year variants, and
   the warehouse's truth is its SID and fact tables. Its hand-written schemas have the fiscal time as dimensions
   (variant, year and period compounded), and the setup deploys a second catalog per provider with the variant fixed
   to K4 (`ZCLVISIT_K4`, `ZCLVISITA_K4`; 2026-10-13), so the demo shows both without a call of the API.
   `scripts/fixed_selection_test.py` (2026-10-13, all passed): the plain catalogs as oracle (periods `K1/2024001`
   ...), the K4 catalogs (11,318 visits, periods `2024001` ... `2025012`, no variant), then the proposal with K4
   fixed accepted into a test catalog and removed, the filtered views kept as the K4 catalogs name them;
   `schema_api_test.py` checks the refusals and `GET values`.
6. Done (2026-10-13, replaced by step 11): the UI. A proposal's section "Fixed characteristics" picks characteristics (with their
   compounding) and values (`GET values`, the SID table) and proposes again; an accepted cube shows its fixed
   characteristics read only (`schema-generator.md`, UI; `scripts/schema_ui_test.py`).
7. Done (2026-10-13, step 22 below): a default selection in the proposal: K4 fixed when the provider has `0FISCYEAR`
   or `0FISCPER`.
8. Done for `0FISCYEAR` and `0FISCPER` (2026-10-13, step 22); later: the rest of (`time-master-data.md`, open step 6 of compounded
   characteristics); a fiscal year > period hierarchy on a fiscal period.

### Fixing as an edit (decided 2026-10-13)

Steps 3, 4 and 6 made the selection part of the proposal: it was chosen before the schema existed, and changing it
proposed again and discarded the edits. Now a selection is an ordinary edit of the cube, made on the dimension's pane,
which the server applies to the schema as it is. Decided with the user:

- **A proposal is always the plain one** (revised 2026-10-13: but for the fiscal defaults, step 22) (no `fixed.` parameters, no "Propose again", no selection in the URL). The
  catalog keeps its default name, the provider's: a selection never renames it (five fixed characteristics would make
  an unusable name). Who wants the plain and a fixed cube side by side names one catalog differently.
- **A fixed characteristic keeps its dimension, with one member**: its view is filtered on its value too, so every
  hierarchy of it has that member under All, and the user's hierarchies, properties and double-click columns stay. The
  facts are the filtered fact view, so totals hold whatever MDX asks. Removing the dimension from the cube stays an
  ordinary edit. This replaces "a fixed characteristic has no dimension" (`bw-schema-design-guide.md`, section 3.8).
- **The server rewrites the schema** (option c): `POST fix?cube=X&fixed.C=v...`, body the current XML and the whole
  new selection, answer the new XML; the UI replaces the document, which is one edit (undo). It needs BW's metadata:
  which views the cube reads, the compounding, the fact view's column names.
- **Views are found or generated on accept** through table `ZZXXMLA1_VIEW` (kind, characteristic or provider,
  selection), as now: schemas that fix the same values reuse one view, another selection gets its own. The cleanup of
  unused views after accept and remove stays for now (its runtime is the thing to watch: it reads every schema file).

Steps:

9. Done: views: a fixed characteristic's own view is filtered on its value (`WHERE key = v`, selection `C=v` with the
   fixed compounding); `fixed_compounding` becomes `view_selection` (the characteristic itself included). An aDSO's
   compounded characteristic is keyed by its SID in the fact view also when all its compounding is fixed (until now by
   its value), so fixing changes no attribute name, only columns. Not filtered: a reference characteristic (its view
   is its basic one's, which other characteristics share); fixing a basic characteristic that another characteristic
   of the provider references is refused.
10. Done: proposal and API: the proposal keeps the fixed characteristics' dimensions; `GET proposal` takes no selection.
    `POST fix?cube=X&fixed.C=v` (new class `ZZXXMLA1_CL_SCHEMA_FIX`): the provider found from the cube's fact table
    (placeholder, registered fact view or BW's fact table), read for the old selection (the cube's annotations) and the
    new one; then the annotations, the fact table, the measure columns, the foreign keys (a usage found by the old
    one) and the tables of the dimensions found so are replaced, and a characteristic whose compounding becomes all
    fixed is named by its own key (`COMPOUND_KEY` replaced by the key column, its `OrderByColumn` removed) or the
    other way. The answer has the XML, the outline, the tables replaced and the new tables' NUMC numbers. `GET
    proposal`, `GET schema` and `POST fix` list the cube's characteristics (name, text, compounding, the dimension
    that is on it, the fixed value), which the UI needs to offer fixing on a dimension.
11. Done: UI: the dimension pane of a characteristic has "Fixed value" (values from `GET values`, a compounded one only
    once its compounding is fixed; un-fixing a characteristic un-fixes those compounded with it); the cube pane lists
    the fixed characteristics, read only, with links to their dimensions. The proposal's section goes.
12. Done: tests (2026-10-13, all passed): unit tests of the views and of `ZZXXMLA1_CL_SCHEMA_FIX` (fix, round trip,
    refusal, the characteristics); `fixed_selection_test.py` (44 checks) fixes K4 on the plain proposal through
    `POST fix`, accepts, queries (11,318 visits, periods by their own key, the variant with one member), un-fixes (the
    plain tables back) and removes; `schema_api_test.py` checks the refusals of `POST fix`; `schema_ui_test.py` fixes,
    undoes, refuses a value and un-fixes on the dimension's pane; `clinic_test.py` passes. The clinic demo's K4
    catalogs have the variant as a dimension with one member (the demo regenerated). A fix takes about 0.4 s (two
    provider reads).

Accepted for now (2026-10-13), the user disagrees with both long term: an aDSO's compounded characteristic keyed by
its SID when all its compounding is fixed (chosen so that fixing never renames the key attribute, only columns), and
a fixed reference characteristic left unfiltered (the view is per basic characteristic). Both are debt,
`known-issues.md`.

### Selections (decided 2026-10-13)

Fixing is not enough to make `0FISCPER` a time dimension: its SID table holds the special periods 013 to 016 when
any provider posts to them, and the positional time functions (`Lag(12)`, `ParallelPeriod`, `ClosingPeriod`) count
them. Usually the cube's own facts have the twelve regular periods only. Decided with the user, the model in
`bw-schema-design-guide.md`, section 3.8:

- **A fixed value is one case of a selection**: a BW range table per characteristic (`I`/`E`, `EQ` ... `CP`, `NP`,
  BW's patterns), in one of two modes: **filter the cube** (members and facts, as fixing does now; the fixed value is
  `I EQ v`) or **restrict members** (only the characteristic's view; the facts are not filtered at query time).
- **The facts must agree with restricted members**: a probe of the facts (distinct values of the fact column against
  the SID table with the negated selection) refuses the schema whenever the facts hold an excluded value, always, not
  only for time dimensions; no unsynced schema is written. A fiscal period whose facts have special periods is not
  time in that cube; the calendar characteristics are, or the cube is filtered.
- **Not chosen:** folding the special periods into period 012 in the fact view (a computed column over hundreds of
  millions of rows on every query, and period 012 no longer BW's); excluding them from the facts by default (silently
  changes BW's year totals); `olap4abap.membersWithFacts` (a semi-join over the facts per query, not allowed on time,
  and it drops regular periods without facts, which breaks the positional functions as much).
- **A global probe** in the schema builder's start page runs the probes of all catalogs, because a load after the
  accept can bring an excluded value into the facts.

Steps:

13. Selection class: a global class (`ZZXXMLA1_CL_BW_SELECTION`) with the range table type, parsing and writing the
    annotation text, the canonical text for `ZZXXMLA1_VIEW`, the SQL condition (CDS and native; `CP`/`NP` to `LIKE`
    with `%`/`_` escaped, `NB`, `NE`), its negation for the probe, "one `I EQ` value" for the uncompounding rule, and
    the checks (`EQ` needs a SID, `BT`/`NB` a high value, no quote). Unit tests.
14. Done: table `ZZXXMLA1_VIEW`: `SELECTION` is a CHAR 255 key field, too short for range tables. It becomes an `SSTRING`
    of 1,333 (enough for now; the table is read with ABAP SQL only, not through ADBC), no longer key: 1,333
    characters do not fit the table's key length, so the key is `DDL_NAME` (one row per view anyway), and the
    generator finds a view by kind, object and selection in the `WHERE` as now. The existing rows keep their values.
    Decided 2026-10-13: no hash. A view is found by its selection's canonical text, which only the selection class
    writes (characteristics sorted, rows sorted by sign, option, low, high and without duplicates, one format per
    row, one `I EQ` row written `C=v`); a hash would only be a shorter form of the same text. Selections equal in
    meaning but written differently (`I BT '001' '012'`, `E CP '*013'`...) get views of their own, a duplicate and
    never a wrong one. Uniqueness is the generator's: it looks the view up before it generates one.
15. Done (2026-10-13): views: a characteristic's view filtered on the selections of its key fields (both modes); the
    fact view filtered on the filter-the-cube characteristics only, and none when there are none.
    `ZZXXMLA1_CL_BW_VIEW_GEN` takes a selection (`ty_t_selection`, `ZZXXMLA1_CL_BW_SELECTION`'s characteristics with
    mode and rows) instead of fixed values: `WHERE` with the selection class's condition on the key field; only a
    single `I EQ` value of the compounding leaves `COMPOUND_KEY`. An InfoCube's fact view joins the SID table of a
    filtered characteristic on the SID alone and has the condition in `WHERE` (a condition of several rows is no join
    condition; the demo's K4 view regenerated gives the same visits). The callers still speak fixed values until step
    16 and passed `selection_of( fixed )` (filter the cube, one `I EQ` row each; same canonical text, so the existing
    rows of `ZZXXMLA1_VIEW` stay valid). Checked on SAP: views of the clinic demo for `ZCLFISCVR` in K1 or K4 with a
    period range in restrict members (`I BT`, `E EQ`), and for K4 with the period filtered (`I CP`, `E NB`), activate,
    the period views have the rows of their SID table under the same condition and the aDSO's fact views the aDSO's
    visits.
16. Done (2026-10-13): schema and API: annotations `olap4abap.filter.<characteristic>` and
    `olap4abap.members.<characteristic>` (the rows as `ZZXXMLA1_CL_BW_SELECTION=>rows_text` writes them), the old
    `olap4abap.fixed.` read as filter `I EQ` and rewritten by `POST fix` (`ZZXXMLA1_CL_SCHEMA_FIX=>cube_selection`,
    refused if a characteristic has two); `POST fix` and `GET values` take `filter.C=<rows>`, `members.C=<rows>` and
    `fixed.C=v`; the uncompounding rule on one `I EQ` value in either mode (the view generator's, unchanged);
    `characteristics` of the answers carry `mode` (`filter`, `members` or null), `rows`, `selection` (their text) and
    still `fixed`/`value` for one `I EQ` value; check and accept work on selections (only filter-the-cube
    characteristics need a fact view) and refuse different selections of a shared dimension as for fixed values.
    `ZZXXMLA1_CL_BW_PROVIDER` reads for a selection (`read( selection = ... )`, `ty_provider-selection`) and
    `check_selection` replaces `check_fixed`: the rows checked by the selection class, an `EQ` value needs a SID
    under the selection of its compounding where that is restricted. A compounded characteristic no longer needs its
    compounding restricted (section 3.8: its rows compare its own key under every value of its compounding), and
    `GET values` of it answers under every value of its compounding without parameters. `selection_of`,
    `selection_text( fixed )` and `ty_t_fixed` of the view generator are gone; the clinic generator writes the new
    annotation (the demo's existing K4 catalogs keep the old one, which is read the same). The UI reads the new
    annotations and passes selections other than fixed values through `POST fix` unchanged (its selection editor is
    step 18). Tests: unit tests of `ZZXXMLA1_CL_SCHEMA_FIX` (old annotation, restrict members, two selections);
    `schema_api_test.py` (refusals of rows, two selections, `EQ` without SID under the compounding, restrict members
    through `POST fix`), `fixed_selection_test.py`, `schema_ui_test.py` and `clinic_test.py` pass.
17. Done (2026-10-13): the probe (`ZZXXMLA1_CL_SCHEMA_PROBE`): per cube and restrict-members characteristic, the
    excluded values in its facts with their counts (at most 20, by value; a compounded one as `K4/2024013`). Run by
    `POST fix` (400 with the values), accept and `check?probe=true` (400 on a refusal, else the answer has `probe`),
    and `POST probe[?catalog=X]` (every catalog, or one: `{catalogs: [{catalog, ok, cubes: [{cube, ok,
    characteristics: [{name, ok, values: [{value, facts}]}]}]}], runtime}`, runtime in ms, nothing written).
    Decided with the user (2026-10-13): the probe reads the cube's facts as the cube reads them, the facts filtered on
    the filter-the-cube characteristics, so values outside the cube refuse nothing; a catalog `POST probe` cannot
    probe (its schema file missing or unreadable, a cube that restricts members not on a BW provider's tables) is an
    entry with `error` and no cubes, the other catalogs are probed. Built: the facts are read from BW's tables as the
    fact view is made of them (`ZZXXMLA1_CL_BW_VIEW_GEN->fact_metadata`), not from the fact view, so the probe needs
    no generated view and runs before accept (on `POST fix` the view of a new selection is only a placeholder): an
    InfoCube's SIDs grouped, then joined to the SID table with the negated selection on the key field; an aDSO's
    reporting view grouped on the values where the negated selection holds. A cube without restrict-members
    characteristic is not looked at (FoodMart's catalogs probe as ok). Measured on the wide demo (1,000,000 facts):
    the probe adds 0.2 to 0.4 s to a `POST fix` (which takes 1.4 to 1.8 s there, the provider of 100 characteristics
    read twice); all ten catalogs of the server probe in 65 ms (none restricts members). A bigger load is still to
    measure (`ZXMLWIDE` with more records, members with facts step 4). Tests: unit tests of the statements (InfoCube
    with a filter, aDSO, no field) and the refusal; `schema_api_test.py` (refusals of `POST fix` on both providers,
    also under a filter on K4, `POST probe` of all catalogs and of one, 404, 405); `fixed_selection_test.py`,
    `clinic_test.py` and `schema_ui_test.py` pass.
18. Done but for the probes (2026-10-13): UI: the dimension pane has "Selection" under "Fixed value": a table of rows
    (sign, option, low, high; values from `GET values`, free text for patterns), the mode switch, presets (`0FISCPER`:
    the regular periods) and Apply through `POST fix`; a fixed value stays one click (`I EQ`) (`schema-generator.md`,
    UI; `schema_ui_test.py`: a members range the clinic's facts contradict is refused with the values, the same range
    filtering the cube is applied and removed; the fiscal defaults of `0TSC0T001` are twelve rows, removed and brought
    back by the preset). Open: Accept's dialog runs `check?probe=true` and shows a refusal's values (accept refuses
    already, with the values); the start page gets "Probe all catalogs" with a result per catalog.
19. Test data: the clinic demo's period `ZCLFISCPR` gets special periods (013 to 016) in its master data only, for a
    restrict-members catalog, and facts in period 013 under one variant only, so the probe refuses that variant and
    accepts the others.
20. Tests: unit tests of 13 and 15; `fixed_selection_test.py` extended (ranges in both modes, the probe's refusal,
    the old annotation); `schema_api_test.py` (`POST probe`, refusals); `schema_ui_test.py` (the selection table, the
    probe on the start page).
21. Fiscal time: done in step 22 but for a fiscal year > period hierarchy on a fiscal period marked as time (open).
22. Done (2026-10-13): fiscal defaults of the proposal and the fiscal time master data. Decided with the user:
    - **K4 is proposed**: a provider with `0FISCYEAR` or `0FISCPER` (compounded with `0FISCVARNT`) is proposed with
      `0FISCVARNT` filtering the cube on `I EQ 'K4'`, the most common variant; the user changes it on its dimension.
    - **The period is restricted to the regular periods** (`olap4abap.members.0FISCPER`, `I CP '*001'` to
      `I CP '*012'`, K4's months), and **year and period are marked as time**, less friction for the user.
    - **A cube whose facts post to period 000 or 013 to 016 has no fiscal time dimension**: the probe refuses the
      restriction, the period is neither restricted nor time there (a note with the values), and the model has to
      make `0CALMONTH` the time, with its own logic of binding the fiscal period to the calendar month (open, below).
    - **Only `0FISCPER` and `0FISCYEAR`** get defaults.
    - **The time generator fills them as it fills `0CALYEAR` and `0CALMONTH`**.
    Built: `ZZXXMLA1_CL_SCHEMA_DEFAULTS` (new; `propose` checks K4 through the provider read and probes the period;
    `fiscal_defaults` and `regular_periods` unit-tested), called by `GET proposal` before the proposal, which reads the
    provider for the selection; `ZZXXMLA1_CL_SCHEMA_PROPOSAL=>propose( time = ... )` writes the time dimensions as the
    UI marks one (level types, no members with facts); its notes join the proposal's (the schema pane's "Not proposed"
    is now "Notes"). `ZZXXMLA1_CL_TIME_MD` fills `0FISCYEAR` and `0FISCPER` as it fills `0CALYEAR` and `0CALMONTH`, for K4
    only (its years are the calendar years, its periods 001 to 012 the months; `time-master-data.md`); filled on
    the development system for 1995 to 2029: BW's SID conversion
    made all 17 periods of every year (595 SIDs, 420 regular), which is why the restriction is needed.
    Tests: unit tests of the defaults, the time dimension of the proposal and the fiscal master data;
    `scripts/fiscal_default_test.py` (new, 19 checks: the proposal of BW's content cube `0TSC0T001`, accepted into
    `ZZFISCTEST`, twelve periods per fiscal year, `Lag(1)` of `2025001` is `2024012`, removed); `schema_api_test.py`,
    `fixed_selection_test.py`, `clinic_test.py` and `schema_ui_test.py` pass.
    Open:
    - the derived `0CALMONTH` time for a cube whose facts post to special periods (the binding of the fiscal period
      to the calendar month);
    - the probe's refusal path of the defaults is not tested live: no provider with `0FISCPER` has facts in special
      periods (step 19's test data is the clinic demo's own `ZCLFISCPR`, which gets no defaults);
    - a fiscal year > period hierarchy (`0FISCPER` has `0FISCYEAR` as an attribute), so `ParallelPeriod` and `Ytd`
      work on the period's dimension.

## Now: members pushed down to HANA

Decision in `mvp-scope.md` (Member decision, 2026-10-12). Found with Excel on the wide demo `ZXMLWIDE`: a label filter
on `[Dimension 00]` (100,000 members) made every query read and sort all 100,000 members in ABAP to show one
(`DrilldownLevel` → `get_member_children` → `load_members`), 2-3 s per query. Order, each step with all `reference/`
cases and the applicable statements passing:

1. Done (2026-10-12): hierarchy order without positions: members carry an order key built from their typed keys
   (`RolapMemberBase.compareTo`; `ZZXXMLA1_CL_MODEL=>order_key`, the key columns' types from HANA's catalog);
   `Hierarchize`, `Order`, ranges and the native crossjoin's order use it instead of the position in the loaded
   hierarchy.
2. Done (2026-10-12): the schema reader reads members by SQL and caches them (`SqlMemberSource` in
   `ZZXXMLA1_CL_MODEL=>read_members`, `MemberCache`): children of a member, a member by name under its parent or on a
   level (UPPER on both sides, a plain comparison for names without letters or of number columns), by key, a
   member's parent (by its path), a level's members only when asked for, ranges and `Lag`/`Lead` along a level (one
   query each, `order_condition`), children counts in one grouped query per level (DisplayInfo,
   `CHILDREN_CARDINALITY`), the ancestors kept with every read, each query answered once per request.
   `load_members` is gone.
3. Done (2026-10-12): members from the facts (native crossjoin) are read by their paths in one query per 1,000
   (`get_members_by_paths`; an IN list on the key of a level of unique members), not looked up in the level's members.
4. Done (2026-10-12): `Children`, `Members` (above 300 members), `Descendants`, `DrilldownLevel` and
   `DrilldownMember` under a non-empty evaluator: only the members with facts in the context and the subcube, their
   paths from one grouped fact query (`context_children`, `context_level_members`). Excel's label filter on
   `[Dimension 00]` of `ZXMLWIDE`: 0.13 s per query instead of 2-3 s, the same answers.
5. Done (2026-10-12): `MDSCHEMA_MEMBERS` reads through the schema reader only what its restrictions can select (a
   member and its TREE_OP relatives, the restricted levels); `MDSCHEMA_HIERARCHIES`' default member of a hierarchy
   without All member is its first member (LIMIT 1).
6. Open: a wide-demo characteristic with millions of members to measure against.
7. Done (2026-10-12): cell values are read as the reference reads them (`FastBatchingCellReader`, `CellRequest`,
   `Segment`): each phase of a query (slicer, axes, named sets, cells) is evaluated with a batching reader that records
   the cells it misses (their value 0 for the pass, `RolapUtil.valueNotReadyException`), then the recorded cells of each
   pattern of hierarchies and levels are read with one grouped query whose level columns are constrained to the keys
   asked for (`IN` lists, `ZZXXMLA1_CL_MDX_FACTS=>load_aggregations`), and the phase is evaluated again until it misses
   none (`RolapResult.phase`, at most `MaxEvalDepth` 10 passes). What was read is kept as segments: a cell a segment
   covers without a group has no facts. The native crossjoin's tuple read is constrained to its fixed members the same
   way. Applicable statements: same answers, the whole run 191 s instead of about 240 s; #46 and #85 (Order/TopCount
   over 100,000+ tuples) take about 105 s instead of about 80 s, the second pass evaluating every value again.
8. Open (`known-issues.md`, Performance): an unqualified member name (`[USA]`) is looked for by name in every hierarchy, one query each (100 on
   `ZXMLWIDE`).
   Done (2026-10-12): `Order` over large sets. #85 (`Head(Order(...), 5)` over the 85,000 tuples of a
   `NonEmptyCrossJoin` of customers and products, the query a pivot client generates) took 105 s: the merge sort made
   1.4 million comparisons, each finding the key's dependent members again (`depends_on` over the key's tree) and its
   value by a string key. Two changes:
   - Native `Order` (our extension; the reference has no `RolapNativeOrder` and sorts in memory, `Sorter`):
     `ZZXXMLA1_CL_MDX_ENGINE=>native_order`, `ZZXXMLA1_CL_MDX_FACTS=>ordered_paths` (`top_count` is now one of its
     callers). Keys `BASC`/`BDESC`, each the `OrderKey` of an operand's current member or of its `Ancestor` at a level
     (its level's key column: a number as a number, a string `LOWER`, then as it is, `Util.caseSensitiveCompareName`;
     the All level orders nothing), or a stored measure, also through calculated measures that are only that measure
     (`[*SORTED_MEASURE]` -> `[*FORMATTED_MEASURE_1]` -> `[Store Sales]`). The set: what the native crossjoin reads
     (`NonEmptyCrossJoin`, `CrossJoin` under a non-empty evaluator), also through named sets (their context is the
     slicer's) and `Generate(set, {(the current members of its hierarchies)})`, which gives the set as it is. One
     query as native `TopCount`'s: the native crossjoin's tuples (inner join to the facts of the set's context), the
     measures' values left-joined (no facts: NULL, first ascending, last descending), `ORDER BY` the keys, then the
     members' keys (the set's order), and `Head(Order(...), n)` (also of a named set not evaluated yet) is `LIMIT n`.
     Not native: `ASC`/`DESC` (hierarchical), any other key or set, calculated members in the context of a measure key.
   - The interpreted sort (`sort_tuples`, also `TopCount`/`BottomCount` that are not native): with break keys only,
     the positions of the members each key depends on are found once, every key's value is evaluated once per tuple
     into a table (an error kept for the comparison that meets it; equal dependent members compare as 0 by an id),
     and the tuples' indexes are merge-sorted by these values. A hierarchical key keeps the old comparator
     (`merge_sort_tuples`).
   #85: 1 s (eMondrian 3.6 s). All 90 applicable statements with `Order`, `Head`, `TopCount` or `BottomCount` and 16
   edge cases (`BDESC`, ties, string keys, an ancestor key, the All level, slicer, subselect, a chain of calculated
   measures, empty values in another context, named sets with `Generate`, the fallbacks, evaluation errors) give
   eMondrian's answers; the whole run takes 104 s. Still open (`known-issues.md`, Performance): a second pass of a phase evaluates the sort values of
   an interpreted `Order` again (`sort_values` are kept per run).
9. Done (2026-10-12): native `TopCount`/`BottomCount` (`RolapNativeTopCount`, `ZZXXMLA1_CL_MDX_ENGINE=>native_top_count`,
   `ZZXXMLA1_CL_MDX_FACTS=>top_count`): by a stored measure, of a crossjoin (`CrossJoin` or `*`, our extension: the
   reference's `CrossJoinArgFactory` knows only the function names, so it sorts #46 in memory) of level members,
   `Children` or `Descendants`, or of one of them. One query: the crossjoin of the operands' members (the distinct key
   columns of each dimension table) left-joined to the facts grouped by these columns with the context and the
   subcube, `ORDER BY` the value (`DESC NULLS LAST` for TopCount, `ASC NULLS FIRST` for BottomCount: the empty value
   is the smallest), then the members' keys (the stable sort keeps the set's order), `LIMIT` the count. Under a
   non-empty evaluator only a `CrossJoin` the native crossjoin would read, inner-joined to the facts of the context
   without the default members (its tuples) and left-joined to the value's. The whole crossjoin's size is counted
   first (one query) and fails on the result limit as the interpreted one does. Not native with calculated members in
   the context (a compound slicer, #73 and #297-#301: about 8 s each), a calculated measure or another set
   (`Distinct`, a member list). #46: 2.3 s instead of 104 s (eMondrian 3 s), the same answers; all 47 applicable
   statements with `TopCount`/`BottomCount` and 13 more edge cases (empty tuples, ties, an empty key, `Fact Count`,
   slicer, subselect, `NON EMPTY`) give eMondrian's answers.

## Now: members with facts

Decision in `mvp-scope.md` (Members with facts decision, 2026-10-13): a dimension of a cube can show only the members
that have facts in it, by the annotation `olap4abap.membersWithFacts` on its `DimensionUsage`.

1. Done (2026-10-13): the annotation (`ZZXXMLA1_CL_SCHEMA`, refused on a time dimension), member reads from
   `ZZXXMLA1_CL_MODEL=>member_table`, the clinic demo's 300 patients without a visit (region Coastal without any) and
   its schemas annotated on every dimension but time; `scripts/clinic_test.py` (71 checks on `ZCLVISIT` and
   `ZCLVISITA`: every level, children and descendants equal to NON EMPTY over all facts, members without facts not
   found, counts, ranges, native `TopCount`, `LEVEL_CARDINALITY`, time not restricted). FoodMart unchanged: the
   `reference/` cases and the applicable statements give the same answers.
2. Open: time dimensions (decide whether and how a period without facts is a member).
3. Done (2026-10-13): the schema generator proposes the annotation on every `DimensionUsage` (on by default:
   a characteristic is shared by many providers, which use few of its values); the cube pane's "Members with facts"
   column switches it per dimension, and marking a dimension as time removes it (`scripts/schema_ui_test.py`).
4. Open: measure the semi-join on a large provider (`ZXMLWIDE` with more records).
5. Open (noted 2026-10-15; `known-issues.md`, Performance): on an aDSO the existence check of a member keyed by its value should read the aDSO's own
   fact table (its reporting view `/BIC/A<aDSO>7`), without the join. Today every check is
   `IN ( SELECT <key> FROM <the cube's fact table> )`, and with a compounded characteristic that is the fact view
   (`ZZXXMLA1_F_<aDSO>`, e.g. `ZZXXMLA1V0000015` of `ZCLVISITA`), which joins the SID of each compounded
   characteristic. Only a characteristic keyed by that SID needs the fact view; every other one has its value in the
   aDSO's table. Seen in Excel's filter list on `ZCLVISITA`: before the validator looked up the query's named sets
   first, each of the 91 lookups of a named set's name as a member was such a semi-join.

## Then: the schema generator

Design in `schema-generator.md`. Order:

1. Done: the decisions written down (`schema-generator.md`).
2. Done: the cube-type aDSO `ZFMSALESA` with the FoodMart facts and standard time characteristics, created and loaded
   by `ZZXXMLA1_CL_BW_FOODMART_GEN` (`environment.md`, FoodMart data for the BW cube).
3. Done (2026-10-06): the provider reader `ZZXXMLA1_CL_BW_PROVIDER` and the proposal `ZZXXMLA1_CL_SCHEMA_PROPOSAL`;
   `ZZXXMLA1_CL_BW_VIEW_GEN` takes its table names from BW (`schema-generator.md`, Implementation). The `ZFMSALES`
   proposal loads in `ZZXXMLA1_CL_SCHEMA`.
4. Done (2026-10-06): the `/zzxxmla1/schema/api` endpoints (`ZZXXMLA1_CL_SCHEMA_API`, `schema-generator.md`, The
   API); accepted schemas of the InfoCube `ZFMSALES` and the aDSO `ZFMSALESA` are served by the XMLA endpoint. An
   aDSO is modelled as an InfoCube: its time characteristics are dimensions on their views, no time dimension on the
   fact table (`schema-generator.md`, Time; decided 2026-10-06).
   Then (2026-10-06) `GET schemas`/`GET schema` to reopen an accepted schema (an existing catalog keeps its schema
   file), `POST check` (accept's checks, nothing written), and a clear reader error for an unnamed hierarchy next to
   an attribute of the dimension's name.
5. Done (2026-10-06): the Preact UI (`schema-generator.md`, UI), served as files of the server by
   `ZZXXMLA1_CL_WEB_APP` (since 2026-10-07 from the code, `ZZXXMLA1_CL_WEB_APP_FILES`), checked with `scripts/schema_ui_test.py`.
   Then (2026-10-06) removing a catalog (`POST remove`, Remove… on the start page; checked end to end with a
   throwaway catalog). One cube per catalog for the MVP (`mvp-scope.md`, Catalog decision).
   Open: an accept through the UI checked by hand (the API's accept was); calculated members of the schema (check
   and accept refuse them, a query of their cube fails) and aggregators other than `sum`/`count` (a query that reads
   such a measure fails; a BW key figure with MIN or MAX is proposed so) are not implemented.
## Done: compounded characteristics

Built 2026-10-12; the model is in `bw-schema-design-guide.md`, section 3.7. A compounded characteristic (`0FISCPER`
with `0FISCVARNT`, a cost centre with its controlling area) is unique only by all its key fields: `2024001` exists
under K4 and under V3. On an InfoCube the members' unique names collided; on an aDSO, keyed and joined by the value, a
fact was counted once per compounding value, in cells and in the native crossjoin, `TopCount` and `Order`.

1. Done: test data. The clinic demo (`docs/clinic-demo.md`) has the room `ZCLROOM`, compounded with the site
   `ZCLSITE`: R01 to R04 at both sites, R05 only in the north, in `ZCLVISIT` and `ZCLVISITA`. Joined by the value, the
   aDSO's visits were 64,516 instead of 33,956.
2. Done: the HANA plan on `ZCLVISITA`. A query without the room has no join to its SID table (pruned); one with it
   joins the facts to the SID table's index on both key fields. A compounded characteristic costs nothing where it is
   not used.
3. Done: the fact view. `ZZXXMLA1_CL_BW_VIEW_GEN` (`fact_layout`, `generate_fact_view`) reads an aDSO's compounded
   characteristics (`RSDIOBJCMP` of the basic characteristic) and writes a CDS view on `/BIC/A<adso>7`: every field
   without namespace and `SID_<field>` per compounded characteristic. `ZZXXMLA1_CL_BW_PROVIDER` reads the aDSO from it
   (a placeholder `ZZXXMLA1_F_<aDSO>` until it exists, generated on accept by `ZZXXMLA1_CL_SCHEMA_API`); the proposal
   keys the compounded dimensions by `SID`. No engine change for the joins.
4. Done: names. The characteristic's view has `COMPOUND_KEY` (`NORTH/R01`, `#/#`), the key attribute's `NameColumn`;
   the own key is the member property `Key`. Not the caption: `captionColumn` is not supported.
5. Done: order. `ZZXXMLA1_CL_SCHEMA` reads an attribute's `OrderByColumn` (and `orderBy`) and a level's
   `ordinalColumn` as the reference does (`RolapLevel`, `RolapDimension.resolveOrdinalColumn`); members are read
   ordered by it, then by the key, their order key is the ordinal's, then the key's, `order_condition` (`Lag`, `Lead`,
   ranges) compares the ordinal first, and the native `Order`/`TopCount` (`ordered_paths`) order by it. The clinic's
   south rooms get the lower SIDs and still come after the north ones.
6. Done for `0FISCPER` and `0FISCYEAR` (2026-10-13, selections, step 22): the fiscal time characteristics in the
   time master data (
   `time-master-data.md`): an aDSO's fact whose value has no SID has no `SID_<field>` and drops out of the engine's
   inner join.

Not done, decided: no hierarchy with the compounding as a level above (`[0FISCPER.Fiscal].[K4].[2024001]`), the
schemas are flat; no join on two generated string columns (HANA cannot use the columns); no SID columns for the characteristics without compounding (a join each,
up to 100 on the wide demo, and SID order); no keys of several columns in the engine (not in the reference's schema,
which then could not serve these schemas).

## Done: Time is a TimeDimension

The schema's Time dimension has `type="TimeDimension"` and time level types on its levels and attributes
(`TimeYears`/`TimeQuarters`/`TimeMonths`, `TimeWeeks`/`TimeDays` for Weekly, `TimeUndefined` for the day name and the
fiscal period). `ZZXXMLA1_CL_SCHEMA` reads the level types with Mondrian's checks, the schema reader carries
`DimensionType` and `LevelType` for the time functions, the rowsets give `DIMENSION_TYPE` 1 and the `LEVEL_TYPE` codes,
and the engine no longer evaluates the axes once per year (`RolapResult.loadSpecialMembers` skips a time dimension), so
value-dependent sets answer as in FoodMart. The generator rule for BW: a characteristic of type date (DATS) or a BW
time characteristic (`0CAL*`, `0FISC*`) becomes a time dimension (`docs/bw-to-schema-mapping.md`).

## Then: the set functions

Done: `Filter` (`FilterFunDef`, with `IsEmpty`) and `TopCount`/`BottomCount` (`TopBottomCountFunDef`); 11 of the 20
statements that stopped at `Filter` and 21 of the 22 that stopped at `TopCount` now give eMondrian's answer, the others
stop at the next function (`:`, `Descendants`, `VisualTotals`, `Avg`, `Sum`). Then `:` (`RangeFunDef`) and
`Descendants` (`DescendantsFunDef`, all signatures, of a set as `Generate`): of the 34 statements that stopped at them,
16 give eMondrian's answer, 13 stop at a compound slicer, 1 at `Count`, 4 are big crossjoins (memory limit,
#144 order). Then the compound slicer (`RolapResult`: unary members, `CompoundSlicerRolapMember` placeholders,
SCOPED solve order with cube scope, `CurrentMember` on a slicer hierarchy an error): 21 of its 26 statements give
eMondrian's answer, 5 stop at `Distinct`, `Tail` or `SetToStr`. eMondrian needed a fix for it
(`scripts/patches/compound-slicer.patch`, `docs/environment.md`). Then the aggregates and set algebra:
`Union`, `Except` (and `set - set`), `Intersect`, `Head`/`Tail`, `Distinct`, `<Set>.Item` (by index and by name, the
validator resolves `SetItemFunDef`'s string resolver), `<Tuple>.Item`, `SetToStr`, `Count` (with `EXCLUDEEMPTY`) and
`<Set>.Count`, `Sum`, `Avg`, `Min`, `Max`, `Rank` (2 and 3 arguments); `Aggregate`'s roll-up now shares their
`FunUtil` arithmetic. `Hierarchize` puts calculated members after their stored siblings (#242). Of the 35 statements
that stopped at them 22 give eMondrian's answer; the others stop at `Existing` (4), `PeriodsToDate` (3), `Generate` (2),
`.Parent`, `.LastSibling`, `AddCalculatedMembers`, `IS EMPTY`. An index or name not in the set gives Mondrian's null
member, which the engine does not have yet ("not implemented"). Then named sets: `WITH SET` (`SetBase`, found by its
name as written, may refer to sets defined after it), aliases `set AS name` (`Query.ScopedNamedSet`, visible in the
call around the AS), `<Set>.Current`, `<Set>.CurrentOrdinal` and `Generate` (set and string forms). A named set is
evaluated once per query, the first time it is used, in the context of the slicer (`RolapNamedSetEvaluator`,
`RolapResult.evaluateExp`); an alias each time its AS is evaluated. The position of the current tuple follows
`Generate`, `Filter` and `Order` (which evaluates its keys in the order of the set, as `Sorter`). Of the 69 statements
that stopped at named sets, aliases and `Generate` 39 give eMondrian's answer; 2 fail in eMondrian too (#2, #358), 3
differ by eMondrian's native crossjoin (#155 and #169 in hierarchy order, #85 a memory-limit crossjoin of all customers
and products), the others stop at `OrderKey`, `Existing`, `MATCHES`, `IN`, `IS`, `DrilldownLevel`, `Ancestor(s)`, ...
Then the member functions: `Parent`, `FirstChild`, `LastChild`, `FirstSibling`, `LastSibling`, `NextMember`,
`PrevMember`, `Lag`, `Lead` (along the level, across parents), `Siblings`, `Ancestor`, `Ancestors`, `Ascendants`,
`Cousin`, `ParallelPeriod`, `PeriodsToDate` (both also without arguments, on the cube's time hierarchy), `Level`,
`Hierarchy`, `Dimension`, `Name`, `UniqueName`, `Caption`, `Ordinal` and `OrderKey` (an `OrderKey` value: calculated
members last, then by key, numbers as numbers, strings ignoring case first, keys of different kinds by unique name).
With them the null member of a hierarchy (`RolapHierarchy.getNullMember`, `[Hierarchy].[#null]`): what these functions
give where there is no member, also `Item` out of range; its cells are null and `{}` leaves out tuples with it. An
empty axis now writes the `HierarchyInfo` of its set type, as Mondrian's axis metadata does. 25 more statements give
eMondrian's answer; #41 differs by the order of eMondrian's native `NonEmptyCrossJoin` (as #155, #169).
Then the operators: `IN`/`NOT IN` and `MATCHES`/`NOT MATCHES` are Mondrian's user-defined functions (`InUdf`,
`MatchesUdf`, which `GlobalFunTable` adds to every schema), so the funtable generator now appends the UDF resolvers
(`UdfResolver`, resolved like a `SimpleResolver`). `MATCHES` is Java's `Pattern.matches`; NetWeaver 7.50 has POSIX
regular expressions only, so leading `(?i)` becomes case-insensitive matching and `\Q...\E` is escaped. `IS`
(`IsFunDef`: tuples member by member, else the same object), `IS NULL` (the null member), `IS EMPTY` (the cell of a
member or tuple), `Existing` (`ExistingFunDef`) and `Exists` (`ExistsFunDef`), both `FunUtil.existsInTuple`: a member
exists if it is on the hierarchy chain (ancestor, descendant or itself) of the member of its hierarchy in the context
(`Existing`) or in a tuple of the second set (`Exists`, else the default member). Other hierarchies of the same
dimension do not matter. A compound slicer's placeholder (`CompoundSlicerRolapMember.isOnSameHierarchyChain`) matches
the members of its slicer tuples, but Mondrian looks for the hierarchy in the first position of the first tuple only, so
under a slicer of tuples of two hierarchies nothing exists (eMondrian answers `{}`; the engine does the same). All 20
statements that stopped at them give eMondrian's answer.
Then the remaining functions, all 46 statements that stopped at one give eMondrian's answer but #64 (a sum's last
digits). `VisualTotals` (`VisualTotalsFunDef`): visual total members keep the unique name of the member they stand for,
so the engine finds their calculation by a `calc_name` of their own (`ZZXXMLA1_CL_MDX_SCHEMA_READER=>get_calculation`),
they are not calculated in the query and contain `Aggregate` (scoped solve order), `.Name` is the member's name, the
caption the pattern's; the evaluator's `set_context` compares `calc_name` too (Mondrian compares identity), else the
visual total of the default member never entered the context. `CurrentDateMember` (`CurrentDateMemberUdf`): the
query's date formatted (`ZZXXMLA1_CL_MDX_FORMAT=>format_date`: Calendar of en_US, weeks from Sunday, the week of
1 January is week 1) and looked up as `Util.lookupCompound` with a match type: BEFORE and AFTER take the closest sibling
by key, then the last or first child down. `Parameter` (`ParameterFunDef`): the default value, typed as a member or set
of the type argument's hierarchy. `DrilldownLevel` (this Mondrian appends the children after the whole set),
`AddCalculatedMembers`, `CalculatedChild`, `LastNonEmpty`, `.Properties` (the standard properties of
`RolapMemberBase.getPropertyValue`; `PropertiesFunDef` types a literal name), `Format`, `Mod`, `CInt` (null for a null
argument, as `JavaFunDef`), `CoalesceEmpty` and `CASE` (`CaseTestFunDef`, `CaseMatchFunDef`), with their resolvers.
The six NON EMPTY crossjoins that ended in memory dumps used up the roll memory of the whole instance when they ran
together (other sessions dumped with `SYSTEM_NO_ROLL`, ADT answered 503 and `ICMENOSESSION`); the engine now has
Mondrian's result limit (`mondrian.result.limit`, `Util.checkCJResultLimit`): a crossjoin larger than
`ZZXXMLA1_CL_MDX_ENGINE=>result_limit` (1,000,000 tuples) fails with "Size of CrossJoin result (n) exceeded limit (m)"
before it is built. More memory would only move the limit; a native NON EMPTY crossjoin would answer these queries.

Then the native crossjoin (`RolapNativeCrossJoin`, `CrossJoinArgFactory`, `SqlTupleReader`): while the evaluator is
non-empty (a NON EMPTY axis; `NonEmptyCrossJoin`, which also puts the slicer members of its hierarchies at All), a
`Crossjoin` or `NonEmptyCrossJoin` whose operands are Level.Members, Member.Children, Descendants(member, level or
depth) or an enumeration of stored members of one level is read from the facts: the combinations of the
operands' level keys with facts in the context, one grouped query (`ZZXXMLA1_CL_MDX_FACTS=>non_empty_paths`, cached
like the cells), ordered by hierarchy order, the first operand first. The context are the stored non-All members of
the other hierarchies that are not their hierarchy's default member (`makeContextConstraintSet`,
`removeCalculatedAndDefaultMembers`); a context with calculated members (an Aggregate or a compound slicer) is not
ported, the crossjoin is then evaluated as before. Other operands go through eMondrian's multi-variant expansion: each is
evaluated and split by level (in the order of their first member), every combination of the levels is read natively,
one after the other, the first operand slowest; this gives eMondrian's order of #41, #144, #155 and #169. Neither an
enumeration nor a level group has a bound on its members (our deviation: eMondrian drops the native read for an
enumeration of more than 1,000 members, `MaxConstraints`, and for a group of more than 15,000,
`MAX_MEMBERS_PER_OPERAND_STATE`, to keep its SQL `IN` list small; our read has no `IN` list, so the bounds would only
send Excel's `Hierarchize({DrilldownLevel({[X].[All X]})})` on a large level, or a long member list, to the interpreted
crossjoin and the result limit). So an enumeration of more than 1,000 members comes back in hierarchy order, as a
shorter one does, where eMondrian keeps the order it was written in. Not valid
(and so not native): all operands with the All member or empty, a calculated member, a calculated measure whose formula
names a member of an operand's hierarchy below none of its members. The seven crossjoins of the result limit answer
now (about 60,000 combinations instead of 16 million tuples). `Format` with the empty format string (a measure without
one) keeps the integer digit (Java's `#,##0.###`: 0.67, not .67).

Then the member properties of levels (2026-10-05). The reference schema had none (Excel's "Show Properties in Report"
offered nothing, eMondrian too listed no property): it now has FoodMart's, as `<Property sourceAttribute=...>` on the
Store Name level (Store Type, Store Manager, Store Sqft, Grocery Sqft, Frozen Sqft, Meat Sqft, Has coffee bar, Street
address) and on the customer Name level (Gender, Marital Status, Education, Yearly Income). The schema reads them
(`RolapLevel.createProperties`: the attribute's column and type), the model reads their columns with the members, the
schema reader keeps the values (`getPropertyFromMap`, case-insensitive) and finds a property of a level or a level above
(`Util.lookupProperty`, `isValidProperty`). `.Properties` gives the typed value (null for a property of a level above,
an error for any other name) and the validator types a literal name from the hierarchy's last level
(`deducePropertyCategory`); an identifier whose last segment is a property of the member or level before it is a
property call (`Util.lookup` with allowProp), so `[Store 14].[Store Sqft]` fails as in Mondrian ("No function matches
signature '<Member>.Store Sqft'") and `[Store].[USA].[Caption]` is the caption. `DIMENSION PROPERTIES
[Store].[Store Name].[Store Sqft]` (also `[Store Name].[Store Sqft]`) is olap4j's `MondrianOlap4jProperty`: listed in
the `HierarchyInfo` of its hierarchy without a type, written with `xsi:type` for the members that have a value; element
names are encoded as `XmlaUtil.encodeElementName` (`Store_x0020_Sqft`). `MDSCHEMA_PROPERTIES` lists them for
PROPERTY_TYPE 1 (the default), `DBSCHEMA_COLUMNS` as columns of their level. Eight `reference/` cases cover them
(`mdschema_properties_level`, `execute_level_properties_*`, `execute_properties_*`, `execute_property_*`).

Excel's label and value filters (recorded on eMondrian through `scripts/xmla-proxy.py`) are `Filter` in a subselect:
`Filter([Store].[Store Country].AllMembers, ([Store].CurrentMember.member_caption = "AAA"))`, with `<>`, `Left(...,n) =`,
`InStr(1, ..., "x") > 0`, `>= AND <=`, a measure (`[Measures].[Unit Sales] > 5`) and for Top 10 a
`Generate(... AS [XL_Filter_Set_0], TopCount(Filter(Except(DrilldownLevel(...)))))`. eMondrian refuses every one of
them: `addFilterToSubcubePredicates` accepts only `[Level].CurrentMember.Name/Caption/Key` compared by `=` or `<>`
(Excel writes the hierarchy and `member_caption`), and the Top 10 form fails with "MDX object '[XL_Filter_Set_0]' not
found". Ported 2026-10-12: `Filter` in a subselect is `addFilterToSubcubePredicates` (`ZZXXMLA1_CL_MDX_ENGINE=>
add_subcube_filter`: `=`, `<>`, `NOT`, `AND`, `OR`, `IsEmpty` of the current member's `Name`, `Caption`, `Key` or
`Properties(...)` against a literal, as a `VALUE` predicate on the level's column), and `MEMBER_CAPTION`/`MEMBER_NAME`
count as `Caption`/`Name` in olap4abap and in the reference (`scripts/patches/subcube-filter-member-caption.patch`), so
Excel's "equals"/"does not equal" label filters work. The current member of a hierarchy compares its lowest level
(`getCurrentMemberComparisonLevel`), so they worked on flat hierarchies (the schema builder's), not on a level above
the lowest of a user hierarchy; since 2026-10-17 olap4abap compares the level the `Filter` filters (`known-issues.md`,
deliberate deviations). Extended 2026-10-13 to all of Excel's label filters in both servers (comparisons,
between, begins/ends with, contains; `scripts/patches/subcube-filter-label.patch`, `label_predicate`; cases
`execute_subselect_filter_label_compare` and `_text`); value filters and Top 10 still fail as in the reference. One
deviation: a constant true condition (`1 = 1`) makes eMondrian fail with a NullPointerException
(`LiteralStarPredicate` has no column); olap4abap does not restrict the subcube.

Suggested next: the functions Mondrian's tests do not reach
(`StrToSet`, `StrToTuple`, `Extract`, `Cache`, ...); `checkDimensionFilter` (a native `Filter` operand). Re-running
`scripts/extract-mdx-tests.py` after the level properties found 13 more statements that run on eMondrian (appended as
#382-#394, the earlier indexes kept); all give eMondrian's answer now. For them: `OpeningPeriod`/`ClosingPeriod`
(`OpeningClosingPeriodFunDef`: without a member the time hierarchy's current member, without a level the one below the
member's, `getDescendant` by first or last child, Mondrian's check that level and member share a dimension), `Ytd`,
`Qtd`, `Mtd`, `Wtd` (`XtdFunDef`: `PeriodsToDate` at the cube's first time level of the type, `CubeBase.getTimeLevel`;
typed without arguments, "must belong to Time hierarchy"), `Subset` (`SubsetFunDef`). `CurrentDateMember` with BEFORE
or AFTER now gives the member it makes up for the search (`findBestMemberMatch`) a unique name, which orders keys of
another kind (`[All Weeklys]` against the years). The evaluator finds an infinite recursion as Mondrian does:
`setExpanding` records the calculation being expanded, `checkRecursion` runs once the stacks have grown by 16 commands
per hierarchy and finds an earlier state with the same context and calculation, and the message carries
`getContextString` (a frame per savepoint after which the context changed). For the same message the command stack has
Mondrian's widths and shape: `executeBody` records `setCellReader`, `executeStripe` takes a savepoint per tuple, a tuple
value takes its savepoint before its members and sets them in turn, and a tuple with a null member is null without
evaluation (`MemberArrayValueCalc`; before, `([Measures].[Foo], [Time].CurrentMember.FirstChild)` on a month looped).

## Later

- Blank handling in HANA and CDS (decided 2026-10-16 to look into later): a compounded characteristic's name with its
  parts at full length, as BW concatenates them (`next-steps.md`, Now: texts and captions), needs blanks inside a
  string. CDS gives its string functions ABAP's blank semantics in the SQL it generates: `rpad( 'AB', 6, ' ' )` is
  `AB`, `concat( rpad( 'AB', 6, ' ' ), 'C' )` and `replace( concat( rpad( 'AB', 6, '~' ), 'C' ), '~', ' ' )` are
  `ABC` in HANA, `concat_with_space( 'AB', 'C', 4 )` is `AB    C` (a throwaway view read through ADBC). To try: a CDS
  table function (AMDP, SQLScript is HANA's own), a `<NameExpression>` with native SQL in the schema (the reader
  refuses expressions; the reference database needs its dialect), `concat_with_space` with a CASE per length of a
  part; and whether trailing blanks survive HANA, ADBC, the XMLA answer and Excel.
- The Discover cache not seeing BW loads is debt (`known-issues.md`): clear it, or the answers of the cube
  concerned, when BW activates master data of a characteristic or loads a request into a provider of a catalog.
- Done: compound slicer (a set of several tuples in WHERE); Mondrian aggregates over the slicer tuples
  (`RolapResult`, `CompoundSlicerRolapMember`).
- Done: `VisualTotals`, `CurrentDateMember`, `Parameter`, `LastNonEmpty`, `CASE`, `CoalesceEmpty`,
  `AddCalculatedMembers`, `.Properties`, and the result limit.
- Runtime of a large axis with member properties (measured 2026-10-15): Excel's `NON EMPTY CrossJoin(Hierarchize(
  {DrilldownLevel({[ZCLDIAG].[All Diagnosis]},,,INCLUDE_CALC_MEMBERS)}), Hierarchize({DrilldownLevel({[ZCLPAT].[All
  Patient]},,,INCLUDE_CALC_MEMBERS)}))` on COLUMNS of `ZCLVISITA`, with the 26 `DIMENSION PROPERTIES` of both
  characteristics (Patient's attributes and texts, Diagnosis's), takes 11.9 s, of which its 9 SQL statements take
  0.2 s; the answer is 26,512 tuples and 75 MB, 70 MB of it axis members, each patient's properties written once per
  tuple. The same cells with Patient on COLUMNS and Diagnosis on ROWS take 1.36 s (8 MB). Done (2026-10-15): the
  method trace showed the writer's `tuple_xml` 10.7 of 15.6 s (traced), `element_name` alone 7.5 s (672,612 calls,
  6.9 million `uccpi`); `axis_xml` now encodes the property names once per axis and writes each distinct member's
  `Member` element once (2,053 for the 26,512 tuples), the same answer byte for byte: 12.0 to 3.7 s runtime (13.5 to
  5.1 s wall; `python scripts/planning_measure.py --case properties_axis`). Left: the engine about 2 s (native
  crossjoin, `fast_cells`, `set_display_info`, `axis_properties`), the 70 MB of axes copied as strings in `build`
  about 1.2 s (they could go to the parts as the cells do), sending 0.5 s. Excel shows at most 16,384 columns, so the
  layout is unusual, but a crossjoin of two characteristics on rows is not.
- Long term: other databases reached from ABAP, DuckDB first. The engine's SQL stays standard for it (no HANA-only
  features such as BW's cached column hierarchy views; decided 2026-10-15 with the BW hierarchies).
- Long term (decided 2026-10-16): the project transpiles to JavaScript with the abaplint transpiler
  (`@abaplint/transpiler`, runtime `open-abap`) and runs outside SAP too, on the transpiler's databases. The transpiler
  has no CDS views, and the model reads the generated characteristic and fact views (`ZZXXMLA1_CL_BW_VIEW_GEN`), so it
  needs a plugin of ours that makes simple CDS views (`define view` on one table or a join of tables, a projection
  with aliases, `cast`, literals, `where`; no associations, parameters or annotations that change the result) a valid
  target: transpiled to a `CREATE VIEW` of the target database, created with the tables and selectable by ABAP SQL
  and native SQL alike. The code stays transpilable for it: 7.50 syntax as now, no kernel features the runtime lacks,
  and the native SQL through ADBC (`ZZXXMLA1_CL_SQL`) standard, as for DuckDB above; what blocks transpilation is
  found by running the transpiler over `src/` and kept as a list here.
- Long term (decided with the user 2026-10-16): SSAS naming. olap4abap reports itself as SSAS 2016
  (`ProviderVersion` 13.0.5026.0) but names hierarchies as the reference does with `SsasCompatibleNaming=false`:
  `[ZCLDIAG.ZCLDIAG_ICD]`, `[Time.Weekly]`, `[Time].[1997]` (`ZZXXMLA1_CL_MDX_SCHEMA_READER`, `lookup_child_of_cube`
  and `lookup_child_of_dimension`). SSAS names them `[Dim].[Hier]`, members with their hierarchy
  (`[Time].[Time].[1997]`), and resolves a two-part name to a hierarchy before a level (`[Product].[Product
  Family].Members` is the attribute hierarchy, All member included, not the level), and a dimension of several
  hierarchies only with its hierarchy named. It stays as it is: Excel only uses the unique names it is sent, so
  every captured Excel statement works; SSAS names matter for hand-written MDX and clients that build names. The
  parser is not affected (both forms are compound identifiers); BW hierarchies' path names of shared nodes keep
  their shape, only the hierarchy prefix would change. Measured with the reference switched to
  `mondrian.olap.SsasCompatibleNaming=true` (in `WEB-INF/classes/mondrian.properties`, put back afterwards), 344
  cases: 84 the same, 98 only names, 25 other members (two-part names resolved to attribute hierarchies), 134
  requests faulting (81 `[Dim.Hier]`, 37 a bare dimension of several hierarchies, 16 related), 3 session cases as
  always. The switch would rewrite about 135 requests, recapture about 230 answers and change the Mondrian test
  statements of `applicable.json`, whose expectations come from the reference's naming. Revisit when a client needs
  SSAS names, or before a release that claims SSAS compatibility.
  Part of that migration (decided with the user 2026-10-17): SSAS becomes the oracle of the BW hierarchies' members
  too, not of their values only. Until then BW is the oracle of names, captions, levels, parents, children counts and
  order, SSAS of the values only, and SSAS's captions are olap4abap's own (`test-strategy.md`, Clinic demo: BW
  hierarchies, which oracle checks what). With SSAS naming the nodes are named as SSAS names them, the SSAS model is
  built from BW's texts, not from our schema, so that its names and captions are independent of olap4abap, and the
  comparison of `execute_ssasmd_*` takes the whole answer, not the cells only.
- The result limit is a class attribute; a setting (per system, like Mondrian's property file) would let it be changed
  without a transport.
- Done: the native NON EMPTY crossjoin. Not yet: its context constraint with calculated members (Aggregate members
  and compound slicers expanded, `expandSupportedCalculatedMembers`), native `Filter` and member lists
  (`RolapNativeFilter`, `SqlMemberSource`). Native `TopCount` is done (members pushed down, step 9).
