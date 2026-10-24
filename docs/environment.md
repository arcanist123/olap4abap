# Environment and procedures

## SAP system

- ABAP FS connection id `a4h_http`, client 001. Docker container `a4h` (image `sapse/abap-cloud-developer-trial:2025`)
  publishing 50000-50001, 8443, 3200, 3300, 8002, 30213, 30215 and others.
- ICF service `/zzxxmla1` -> `ZZXXMLA1_MAIN_ENDPOINT`, URL `http://vhcala4hci:50000/zzxxmla1?sap-client=001`. Anonymous
  access is enabled through logon data on the ICF node (dev system only). The earlier 401 happened before that was set.
- Package `$ZZXXMLA1` is created by hand (ADT or SE80); the ABAP FS tool cannot create packages
  ("Parameter recordChanges could not be found. Your client is out of date.").
- Connect Claude Code via `.mcp.json` (git-ignored, it holds credentials): the MCP servers, among them vsp
  (`--url http://vhcala4hci:50000/ --user DEVELOPER --client 001`).

### SAP license

The system is the ABAP Platform developer trial (NetWeaver AS ABAP with BW and HANA), under SAP's "SAP Developer
Center Master Software Developer License Agreement" (the text lies in the container, `/SAP_COMMUNITY_DEVELOPER_License`;
it is not copied into the repository). Exhibit B adds nothing for AS ABAP and BW; HANA's terms there are those of
HANA express edition, which this system is not. What the agreement means here (not a legal opinion; the open
questions are for counsel):

- Use (section 2.a): developing, testing and demonstrating olap4abap, which is our Content; the system is not
  demonstrated for its own sake and serves no one else (section 3.a: no timesharing or service bureau).
- No distribution (sections 3.a, 3.c.ii, 4): no SAP file goes into the repository. `src/` holds only the objects of
  `$ZZXXMLA1`; exports of SAP's objects, its tables' contents beyond our own data, and the license text stay out.
- No modification (sections 3.a.b, 8): SAP's objects are not changed, enhanced or repaired; olap4abap is objects of
  its own in the customer namespace, BW objects it creates (InfoObjects, providers, hierarchies) are data.
- No benchmarks (section 3.a.c): no results of benchmark tests run on or involving the SAP system are published, and
  the public repository is publication. No runtimes of the SAP system, of olap4abap on it, or speed comparisons
  involving it (with eMondrian, SSAS, BW's own MDX) in commits, docs, issues or PRs; measurements stay in the
  git-ignored `.local/`. Statements count (`one grouped statement`), timings do not.
- No reverse engineering but for interoperability (section 3.a.a), no disassembling or decompiling (3.a.b): what
  olap4abap takes from BW is its observed behaviour on our own models: the tables and their contents, BW's MDX
  answers, what a transaction or program does to the tables. A finding names what it was observed on.
- Confidential information (section 13): SAP's source code, programming techniques, processing methods and designs
  are confidential unless public. Tracked files name SAP's tables, fields, function modules, classes and programs as
  interfaces (`RSHIEDIR`, `RSRHIEDIR_OLAP`, `RSADMINS`) and say what we observed (BW's Recreate leaves a table empty),
  not how SAP's code works inside; where help.sap.com, SAP Notes that are public or other public sources describe
  more, the text cites the link. The agent does not read SAP's standard source (`GetSource`, grep of SAP's packages)
  but when the user asks it to for a named question, and copies none of it into files: what it reads goes to a third
  party (Anthropic). Access credentials are confidential too: logon data stays in `.env.sap` and `.mcp.json`.
- No non-public information in the Content (section 3.a.y): olap4abap's code, comments, generated texts and answers
  carry nothing of SAP's that is not public; the texts it writes as BW would (`JAN 1997`, `Not Assigned ...`) are
  BW's visible output, written by our code.
- No AI training (section 3.b): neither the SAP software nor our Content is used to train models; the Claude account
  that works on this repository has training on its chats switched off (claude.ai, Settings, Privacy; checked
  2026-10-23), and so must any other that does.
- Customers (sections 3.a.x, 3.a.z, 3.c.i): olap4abap gives Excel users access to BW data. A customer needs SAP
  licenses for every user who reaches BW through it (indirect use), and olap4abap is a reporting front end, not a
  replacement of BW as the data's system of record.
- Names (section 19): SAP's names describe SAP's software; olap4abap is not advertised with them.
- Checked on every commit: `scripts/license-scan.py` (hooks in `.githooks`, enabled per clone with
  `git config core.hooksPath .githooks`) refuses timings, the SAP-internal names of the git-ignored
  `.local/sap-internal-names.txt` and Mondrian or eMondrian in our code (`src/`, `web/`), in the staged files and in
  the commit message; an exception is a line of `scripts/license-scan-allow.txt` with its reason. Without arguments it
  checks every tracked file.

## Syncing code between SAP and git (vsp, sapcli)

`scripts/sap-sync.sh ping|pull|push`. `pull` uses [vsp](https://github.com/oisee/vibing-steampunk) (`vsp export`),
which serializes the package with the abapGit installed on the system, so `src/` holds exactly the files abapGit
writes and an abapGit repository of the package shows no diffs; `ping` and `push` use
[sapcli](https://github.com/jfilak/sapcli) (ADT based, no SAP GUI).
Setup: copy `.env.sap.example` to `.env.sap` and fill it in (git-ignored; the ABAP trial's documented `developer`
user works on the dev container). The password reaches vsp and sapcli through the `SAP_PASSWORD` environment variable;
`pull` builds vsp's `SAP_URL` from `SAP_ASHOST`, `SAP_PORT` and `SAP_USE_SSL`.

- `ping`: `package stat` of `$ZZXXMLA1` - tested, works.
- `pull`: `vsp export '$ZZXXMLA1'` into a temp dir, then replaces `src/` with the package's files. vsp puts them in
  `src/$zzxxmla1/` although its `.abapgit.xml` says `FOLDER_LOGIC FULL` from `/src/`, where the root package is the
  starting folder itself, so `pull` moves them up into `src/`; the repository's `.abapgit.xml` is not touched. All
  objects come with it, tables (`.tabl.xml`) too; vsp writes no `package.devc.xml`, and the repository has none.
  Generated objects in the package (CDS views) would be exported as well: the generators write them to `$TMP`.
- System prerequisites of `pull` (installed on the A4H system 2026-10-15): abapGit's developer edition (global
  `ZCL_ABAPGIT_*` classes; the single program `ZABAPGIT_STANDALONE` in `$ABAPGIT` is not enough, it was used to pull
  the developer edition from GitHub) and vsp's `ZADT_VSP` (`InstallZADTVSP`, package `$ZADT_VSP`) with its APC/SICF
  setup. vsp v2.61.0's installer fails on `ZCL_VSP_GIT_SERVICE` (its description is longer than 60 characters).
- `push`: `package create ... --record-changes --no-error-existing` (sapcli passes the `recordChanges` parameter the
  ABAP FS tool lacks, so it may be able to create packages where ABAP FS cannot), then `checkin package` from `src/`.
  **Not yet tested.** abapGit (an offline zip of `src/` and `.abapgit.xml`) imports everything, tables too.
- Not covered by `push`: the **ICF service `/zzxxmla1`** (create it in SICF with handler `ZZXXMLA1_MAIN_ENDPOINT` and
  logon data, see below), **DDIC tables** (`ZZXXMLA1_FILE`,
  `ZZXXMLA1_VIEW`, `ZZXXMLA1_TRACE`, `ZZXXMLA1_TRCUSR`, `ZZXXMLA1_DSCACHE`, `ZZXXMLA1_HIEDIR` and `ZZXXMLA1_HIETAB` are in `src/` as abapGit's `.tabl.xml`, pulled by vsp and left out by `push`: a new system gets
  them from abapGit or SE11, a change is made in SE11 and pulled; the rows of `ZZXXMLA1_FILE`, the server's
  files, are written by `scripts/sap-files.py`, those of `ZZXXMLA1_VIEW`, the generated views, by
  `ZZXXMLA1_CL_BW_VIEW_GEN`, those of the trace tables by `ZZXXMLA1_CL_TRACE`, those of the Discover cache by
  `ZZXXMLA1_CL_DISCOVER_CACHE`, those of the hierarchy copies' directory and registry by
  `ZZXXMLA1_CL_BW_HIERARCHY_COPY`, which also generates the copies' tables in `$TMP`; vsp's `CreateTable` creates a
  table (client-independent with `client_dependent` false, as `ZZXXMLA1_HIEDIR` and `ZZXXMLA1_HIETAB` were made);
  the ABAP FS tool cannot create tables, "No ABAP server defined", but sapcli can:
  `sapcli table create ZZXXMLA1_X "text" '$ZZXXMLA1'`, `table write ZZXXMLA1_X - < source` (the `define table`
  source), `table activate ZZXXMLA1_X`, as `ZZXXMLA1_DSCACHE` was made), **CDS views** (generated by code), and BW
  objects. Add generator programs to `src/` for anything abapGit-style files cannot hold.
- Layout: `.abapgit.xml` (`STARTING_FOLDER /src/`, `FOLDER_LOGIC FULL`) and `src/*.clas.abap|.xml`, ... as abapGit
  writes them (XML with a UTF-8 BOM and without sapcli's fields such as `VERSION`; LF line ends, which git's
  `autocrlf` turns into CRLF in the working tree).

## Reference implementation: eMondrian

Docs say JDK 11 / Maven 3.3, but both poms compile with `source/target/release` 17, so **JDK 17 or newer is required**
(JDK 21 also fine). The build downloads Node v16.13.1 / npm 8.1.2 through the frontend Maven plugin. Pinned commits that
were built successfully on 2026-10-02: `SergeiSemenkov/mondrian` branch `eMondrian` @ `746b824a`,
`SergeiSemenkov/eMondrian` branch `main` @ `729fd390`, `SergeiSemenkov/SchemaEditor` branch `main` @ `02c74c08`.

`scripts/setup-reference.sh` does the whole thing: clone, build Mondrian (`mvn install -DskipTests`), run
`clone_schema_editor.sh` by hand, build eMondrian with `-Dexec.skip=true` (Maven's exec plugin cannot launch `.sh`
files on Windows: `CreateProcess error=193`), then build the Docker image from eMondrian's own `docker/Dockerfile` and
start container `emondrian` on port 8080. Unit tests are skipped in both builds.

Our fixes of the fork are patches in `scripts/patches/*.patch`, applied by `setup-reference.sh` after the
checkout (skipped if already applied). `mondrian-multivariant-order.patch` (2026-10-05): eMondrian's multi-variant
native crossjoin (commit 8996c77f3, emondrian.31, `RolapNativeCrossJoin.tryMultiVariantCrossJoin`) appends the results
of its variants one after the other, so a NON EMPTY crossjoin of Excel's `Hierarchize(DrilldownMember(...))` put a
drilled member's children after all members of the level above, and Excel showed the member twice. The patch sorts
the result into the order of the operands (each member's position in its evaluated operand, hierarchy order for an
operand that was not evaluated); `ZZXXMLA1_CL_MDX_ENGINE=>IN_OPERAND_ORDER` does the same. The 2023 release
(v9.3.0.6) is not affected. `mondrian-compound-slicer.patch`: the fork's commit c0d63bce4
("Empty Set in Slicer", 2022) returns empty axes whenever the context holds a null member, but Mondrian's placeholder
of a compound slicer (`RolapResult.CompoundSlicerRolapMember`) delegates to the null member, so every query with a
slicer of several tuples had empty axes and no cells (Mondrian's own tests expect values, e.g. `AccessControlTest`:
4,163). The patch exempts the placeholder. `subcube-filter-member-caption.patch` (2026-10-12):
`Query.addFilterToSubcubePredicates` accepts `.Name`, `.Caption` and `.Key` of the current member but not
`.member_caption`, which Excel's label filters send, so every label filter failed; the patch reads `MEMBER_CAPTION` and
`MEMBER_NAME` as `Caption` and `Name`. `subcube-filter-label.patch` (2026-10-13), our extension: the subcube also
accepts Excel's other label filters (`<`, `<=`, `>`, `>=`, `Left`/`Right(..., Len("s")) = "s"`, `InStr(1, ..., "s")`
compared to 0) as a `LabelColumnPredicate` in `Query.java` (comparison or `LIKE ... ESCAPE ''`, the column cast to a
string for names and captions); olap4abap does the same (`ZZXXMLA1_CL_MDX_ENGINE=>label_predicate`). `parent-child-closure.patch` (2026-10-16): a
member of a parent-child level in a subselect (`Query.addSetToSubcubePredicates`) constrained the fact's key to the
member's own key, so a node had no facts; the patch constrains it to the keys of the member and its descendants (read
without the subcube), not to the closure's parent column (a set of a node and a member below it would join the closure
twice, and a node on an axis under the subselect of its ancestor would find no closure row). And
`RolapCubeLevel.ParentChildLevelReaderImpl` constrained a drill-through to the member's data member, its own facts
only, so a node's drill-through had no rows; the patch constrains it by the closure as a cell is. To put a patched jar into the running container without a full rebuild:

    git -C mondrian apply ../scripts/patches/compound-slicer.patch
    (cd mondrian/mondrian && mvn -B -o install -DskipTests)     # about 30 s
    MSYS_NO_PATHCONV=1 docker cp mondrian/mondrian/target/mondrian-9.3.0-emondrian.38.jar \
        emondrian:/usr/local/tomcat/webapps/emondrian/WEB-INF/lib/ && docker restart emondrian

- eMondrian XMLA endpoint: `http://localhost:8080/emondrian/xmla` (FoodMart sample datasource, unauthenticated).
- Capture a reference exchange:
  `curl -s -X POST -H 'Content-Type: text/xml' -H 'SOAPAction: "urn:schemas-microsoft-com:xml-analysis:Discover"' --data-binary @request.xml http://localhost:8080/emondrian/xmla`

### Second catalog: what the BW generator covers

`reference/schema/FoodmartBW.xml` is a Mondrian schema that contains only what our BW model generator derives from the
metadata of `ZFMSALES` (one dimension per characteristic, every flat attribute as a single-level attribute hierarchy,
FoodMart's level-based hierarchies over those attributes, no properties, Time as a `TimeDimension` with time level types
on its levels and attributes, 3 SUM measures). Compare our engine against it.
`scripts/deploy-reference-schema.sh` adds it to the running container as catalog `ZFOODMART` (the InfoArea of the BW cube; the schema has the cube `ZFMSALES`, caption "FoodMart Sales") next to the untouched
`FoodMart` catalog (so the original tests keep their schema) and restarts the container. Query it with
`<Catalog>ZFOODMART</Catalog>` and `<DataSourceInfo>ABAP BW</DataSourceInfo>` (the data source of the container is named like ours). Verified: totals equal FoodMart's
(Unit Sales 266,773, Store Cost 225,627.2336, Store Sales 565,238.13). In eMondrian the attribute hierarchies are named
`[Store.Country]` (dimension name, dot, attribute name), not `[Store].[Country]`; the unnamed user hierarchy is the
dimension's default hierarchy `[Store]`, and the key attributes are `[Store.Store Id]` etc.

### The reference database holds the BW tables

The schema names the BW tables themselves (`/BIC/FZFMSALES`, `/BIC/S<char>`, `/BIC/P<char>`), so the same file serves
eMondrian and our engine. Its database (the HSQLDB jar) therefore holds copies of those 11 tables with BW's contents,
and the generated characteristic views with the SQL HANA has for them, named by their placeholders
(`ZZXXMLA1_C_ZFMSTORE`, the schema's names; SAP's `ZZXXMLA1V...` is found in table `ZZXXMLA1_VIEW`). The catalog `ZFMDRILL` (`reference/schema/FoodmartBWDrill.xml`, drill-through
actions) needs no tables of its own: its cube is on ZFMSALES's; nor does `ZFMCAPT` (`reference/schema/FoodmartBWCaption.xml`,
captions that differ from names). On SAP it is a catalog of `/WEB-INF/datasources.xml` next
to the ones the schema builder added there. So is the clinic's test catalog `ZCLHIER`, which the clinic generator
deploys with the InfoCube (the reference's `ClinicBW.xml` with the BW hierarchies in olap4abap's form; not from a file
of the repository, `docs/clinic-demo.md`, The schemas). Only views over copied tables are taken; SAP has views of other providers too:

    python scripts/add-empty-members.py           # FoodMart data with the empty members (once, from the original jar)
    sapcli class execute ZZXXMLA1_CL_BW_VIEW_GEN  # the CDS views of the characteristics (logon as in sap-sync.sh)
    python scripts/build-bw-reference-db.py       # export BW tables (sapcli) and views (hdbsql), add them to the jar
    scripts/deploy-reference-schema.sh            # jar and schema into the container, restart

`build-bw-reference-db.py` reads the columns from DD03L and the rows with `sapcli datapreview osql` (raw ABAP values:
NUMC zero-padded, blanks for missing values; the ABAP FS SQL tool is no use here, it drops the leading zeros) into
`data/foodmart-bw/bw/` (git-ignored; `--no-export` reuses them), and adds the tables to `foodmart.script` of the jar
(NUMC/CHAR as VARCHAR, INT4 as INTEGER, DEC as DECIMAL; primary keys as in BW except for the fact table, whose package
key is not unique; indexes on the SIDs), then the views with HANA's SQL from `SYS.VIEWS`, read with `hdbsql` in the
`a4h` container as the ABAP database user (`hdbuserstore` key `DEFAULT` of `a4hadm`; the SQL is read in chunks,
`hdbsql` cuts LOB values after 32 characters). It can run again: lines of an earlier run are replaced. The data preview
rejects long statements, so the columns are read per table. Run it again after the FoodMart generator, whose views
the export finds by their new numbers. After the switch (2026-10-04) all 152 reference cases
gave the same answers as with the FoodMart tables, and the same 59 statements of Mondrian's tests apply.

The same run exports the clinic InfoCube `ZCLVISIT` (catalog and cube `ZCLHIER`, `reference/schema/ClinicBW.xml`; 69 tables
with its text tables, which the views read) and the copy of its hierarchy `ZCLDIAG_ICD` at BW's current version (the
rows of `ZZXXMLA1H...` and `ZZXXMLA1R...` for its `HIESID` and `SVER`; run `ZZXXMLA1_HIERARCHY_COPY` first if the copy
is older), and builds from them the flattened table of the hierarchy, `ZZXXMLA1_HL_ZCLDIAG_ICD` (a row per value SID
with its member on each level, `L01_SID`, `L01_NAME`, `L01_CAPTION`, `L01_POS` to `L04_...`; the build fails unless the tree is
balanced) (`next-steps.md`, Reference scenario). The tables a view reads are taken from its
SQL, listed in `tables.json` of the export; LANG and DATS are VARCHAR too, and a negative number of the data preview
(`37-`) is turned round. After a regeneration of the clinic demo or of its hierarchies: run it again, check the export
with `python scripts/bw_hierarchy_test.py --reference` and capture the changed answers again
(`python scripts/recapture-cases.py execute_hier_ members_hier_ mdschema_hierarchies_hier mdschema_levels_hier`).

## SSAS (Tabular) as reference server

A local SQL Server 2025 Analysis Services instance in Tabular mode (`localhost\SSAS_TAB`, version 17.0,
Developer edition) is the oracle for hierarchies and Excel's behaviour where the reference cannot be
(`next-steps.md`, Reference scenario). Its TCP port changes with every service restart: name the instance, SQL Browser
resolves it. PowerShell reaches it with the `SqlServer` module (`Install-Module SqlServer -Scope CurrentUser
-AllowClobber`; `Invoke-ASCmd -Server 'localhost\SSAS_TAB' -Query ...`, AMO's `Microsoft.AnalysisServices.Server`).
Keep no Microsoft schema files or sample texts in the repository, only our data and captured answers.

Over HTTP it is IIS's `msmdpump.dll`, which `scripts/ssas-http-setup.ps1` sets up once in an elevated PowerShell
(its own site `OLAP` on `http://127.0.0.1:8087/msmdpump.dll`, pool `OLAP` with anonymous access under the pool's identity, `IIS APPPOOL\OLAP` an administrator
of the instance; a development machine only). The SQL Server 2025 pump answers plain HTTP only with
`<RequireSecureChannel>0</RequireSecureChannel>` in its `msmdpump.ini`, which the script sets (the site listens on
127.0.0.1 only). Microsoft documents the setting for test environments, there with the value `false`
([Configure HTTP Access to Analysis Services on IIS 8.0](https://learn.microsoft.com/en-us/analysis-services/instances/configure-http-access-to-analysis-services-on-iis-8-0?view=sql-analysis-services-2025),
step 6); `0` works as well. `scripts/xmla-proxy.py` then logs it as backend `ssas` on
`http://localhost:8086/`. MSOLAP talks to SSAS in binary, compressed XML unless the connection string says
`Protocol Format=XML;Transport Compression=None`; the proxy shows such exchanges as "binary".

### The clinic in SSAS

`python scripts/build-ssas-clinic.py` loads the clinic InfoCube `ZCLVISIT` into SSAS as database `ZCLHIER`, with
`ZCLDIAG_ICD` as a level hierarchy, from the export of `build-bw-reference-db.py` (run that first; its
`--no-export` reuses an export). The rows go into the SQL Server database `olap4abap_ssas` of the same instance
(`MSSQL$SSAS_TAB`, dropped and created again; SSAS's service account `NT Service\MSOLAP$SSAS_TAB` reads it): the
cube's BW tables, `ZZXXMLA1_HL_ZCLDIAG_ICD` (the reference's `hierarchy_levels`) and the characteristics' views
under their placeholder names, created from HANA's SQL as it is (T-SQL runs it with `QUOTED_IDENTIFIER` on), so SSAS
reads SAP's views as the reference does. The Tabular model (compatibility level 1600) is derived from
`reference/schema/ClinicBW.xml` and deployed with a TMSL `createOrReplace` and a full refresh (`Invoke-ASCmd`; the
SQL and TMSL it runs are kept in the git-ignored `data/foodmart-bw/ssas/`): a table per dimension, the level of a
flat hierarchy a column named as the level (from its `nameColumn`, sorted by the key attribute's `OrderByColumn` or
the SID), next to it the key attribute's `NameColumn` as the hierarchy `<level> Text` (the text as a hierarchy of
its own, to watch Excel with repeated texts: `ZCLPAT`, `ZCLROOM`, `ZCLFISCPR`), each display attribute and its text
a hierarchy too (captioned as the level's member properties, `Sex`, `Sex (Text)`; the attributes in the display folder
`Attributes`, every text in `Texts`), `ZCLDIAG_ICD` a user hierarchy with the levels `Level 01` to `Level 04` (sorted by `Lnn_POS`), the fact
table the hidden table `ZCLVISIT` related by its `SID_` columns, a `SUM` measure per measure, the captions an en-US
translation. Tabular cannot model member captions (a member's caption is its name), member properties,
`allMemberName` (the All member is `All`), the drill-through action or the cube's name (always `Model`); its names
are SSAS's (`[ZCLDIAG].[ZCLDIAG_ICD].[Level 03].&[INFLUENZA]`). Checked: SSAS gives the reference's values and order
for `execute_hier_children` and `execute_hier_descendants_distance`.

### The clinic in SSAS Multidimensional

The second instance `localhost\SSAS_MULT` (Multidimensional mode, same SQL Server 2025 Developer edition; its
administrators are set per Windows user, a local administrator's elevated session can add one) holds the clinic with
its BW hierarchies, which Tabular cannot model: `python scripts/build-ssas-clinic-md.py` (`--no-load` keeps the SQL
Server database) loads the database `olap4abap_ssas` as `build-ssas-clinic.py` does and adds per hierarchy of the
export (`build-bw-reference-db.py` exports `ZCLPAT_PRG` and `ZCLSERV_CAT` from their copies too; the time-dependent
`ZCLDOC_ORG` and `ZCLDOC_SITE` are not in the SSAS model) `H_<h>` (a row per occurrence of the copy's node
table, keyed by `POS`, `PARENT_POS` the enclosing occurrence, REST_H and its values after the roots where the
hierarchy shows it), `HV_<h>` (named and captioned as olap4abap names them: a leaf as the characteristic's member, a
node by its `NODE_NAME`) and the bridge `B_<h>` (per occurrence the distinct SIDs of its subtree, the closure). The
model is ASSL (`Create`, then `ProcessFull`, with `Invoke-ASCmd`), database and cube `ZCLHIER`: a dimension per
characteristic (key the SID, named by the level's `nameColumn`, captioned by the text through a 1033 translation with
a `CaptionColumn`, the display attributes member properties), a parent-child dimension per BW hierarchy
(`[ZCLPAT_PRG].[ZCLPAT_PRG]`, levels `Level 01` ..., `NonLeafDataHidden`), the measures `Sum` of `Currency` (exact;
`Double` sums differ in the last digits) in the measure group `Visits`, related to each hierarchy dimension
many-to-many through its bridge's measure group, and the default drill-through action. So a fact counts once per
member however many paths lead to it: link nodes, duplicate leaves, overlapping intervals and overlapping members in
one slicer. `data/foodmart-bw/ssas/members.json` maps each occurrence's SSAS unique name (`&[POS]`) to olap4abap's
(the path of names). Only cell values are taken from this model; the shape of a BW hierarchy is olap4abap's and BW's.
`python scripts/bw_hierarchy_test.py --ssas` checks it against BW's MDX: all members of the three hierarchies have
BW's level, children, caption and values in BW's order (2026-10-16); a slicer of two overlapping `ZCLPAT_PRG` nodes
gives the sum over the union of their values. Over HTTP it is a second pump site next to the first, set up by the
same script with its parameters (`-Instance 'localhost\SSAS_MULT' -Service 'MSOLAP$SSAS_MULT' -Target
'C:\inetpub\olap_mult' -Site 'OLAP_MULT' -Port 8089 -Pool 'OLAP_MULT'`), the proxy's backend `ssasmd` on
`http://localhost:8088/`.

Answers of SSAS are kept as test cases with `--ssas` of `capture-case.py` and `capture-execute.py` (catalog `ZCLHIER`
unless `-p Catalog=` says otherwise; the case gets `ssas.txt`, and `recapture-cases.py` asks SSAS again).
`--ssas multidimensional` captures from the Multidimensional model (its pump on 8089); `ssas.txt` then names that
instance and `recapture-cases.py` asks it there (`execute_ssasmd_*`, the first one Excel's drill-down of
`ZCLDIAG_ICD`).
`scripts/ssas_texts.py` cleans every such answer before it is written, as the license requires (below): it removes
the inline XSD and comments, empties fault and error texts (`faultstring`, `Description`; the codes stay) and the
description columns of `DISCOVER_PROPERTIES`, `DISCOVER_ENUMERATORS`, `DISCOVER_SCHEMA_ROWSETS` and
`MDSCHEMA_FUNCTIONS`, writes olap4abap's provider name and the version it reports where SSAS names itself, `localhost`
and `user` for this machine's server, instance and Windows users, a fixed session id and timestamp for the server's
times; it fails when a text it knows of is left (a new one needs a rule there) and refuses `DISCOVER_KEYWORDS`, whose
rows are SSAS's keyword list. `xmla_test.py` leaves these cases out unless they are named: olap4abap does not write
SSAS's names yet (`next-steps.md`, Later: SSAS naming).

### SSAS license

The instance is SQL Server 2025 Developer edition, under Microsoft's "SQL Server 2025 Developer, Express, Evaluation"
license terms (the PDF lies next to the installation; it is not in the repository, `.gitignore`). What they mean here:

- Use (section 1.a.i): on our machines, to design, develop, test and demonstrate olap4abap; never in production.
- No distribution (sections 2.a, 6): Developer edition has no distributable code. No Microsoft file goes into the
  repository: not `msmdpump.dll` or `msmdpump.ini` (the setup script copies them on the machine), not AMO, ADOMD.NET,
  MSOLAP or the `SqlServer` module, not the license PDF.
- No hosting (section 6): the instance serves this machine only. The pump's site listens on 127.0.0.1, and
  `xmla-proxy.py` keeps its `ssas` port on 127.0.0.1 whatever `--bind` says.
- No benchmarks (section 5): the results of a benchmark test of SSAS are not disclosed without Microsoft's written
  approval, and the public repository is disclosure. No SSAS runtimes or speed comparisons with olap4abap in commits,
  docs, issues or PRs; captured SSAS answers carry no timings.
- No reverse engineering (section 6): SSAS, MSOLAP and ADOMD.NET are not decompiled or disassembled, their binaries
  (`msmdpump.dll` too) are not searched for strings or settings, and nothing is ported from them. A configuration
  setting comes from Microsoft's documentation or from the server's observed behaviour. What olap4abap takes from SSAS is its observed XMLA behaviour against our own models; the protocol
  is Microsoft's published specification (MS-SSAS, MS-SSAS-T, under the Open Specifications Promise). Binary XML is
  read from that specification, or avoided with `Protocol Format=XML`.
- Nothing of the software published (section 6): no texts SSAS ships, i.e. no inline XSD of its rowsets, no
  `MDSCHEMA_FUNCTIONS` descriptions, no description texts of `DISCOVER_PROPERTIES`, `DISCOVER_KEYWORDS`,
  `DISCOVER_ENUMERATORS` or `DISCOVER_SCHEMA_ROWSETS`, no error texts (a fault's code and that it happened stay).
  Captured answers keep only our data and the protocol's structure; SSAS's name for itself (provider name and
  version, fault source), the server and instance names, Windows users, session ids and update timestamps are
  replaced.
- Documentation (section 9): Microsoft's documentation is for internal reference; docs link to it, they do not copy it.
- Data (section 3): SSAS may send usage data to Microsoft; it holds only synthetic or public data (clinic, FoodMart).

## FoodMart data for the BW cube

`python scripts/export-foodmart-csv.py` reads `eMondrian/.../hsqldb-foodmart.jar` (fetched by `setup-reference.sh`) and
writes `data/foodmart/*.csv` (git-ignored): `sales_fact_1997` (86,837 rows), `product`, `product_class`, `customer`,
`store`, `promotion`, `time_by_day`. The jar is not a live database: `sales_fact_1997` and `product_class` are INSERTs
in `foodmart.script`, the dimension tables are INSERTs in `foodmart.log`, and the log has no DDL, so the column lists
are hard-coded in the script. Check: the 1997 totals are Unit Sales 266,773, Store Cost 225,627.23, Store Sales
565,238.13 (FoodMart's published figures), and every fact foreign key resolves.

The BW model is generated by `ZZXXMLA1_CL_BW_FOODMART_GEN` (run with `sapcli class execute`): InfoArea `ZFOODMART`,
cube `ZFMSALES` over `BAPI_IOBJ_CREATE` / `BAPI_CUBE_CREATE`, metadata only. The data only exists to pass tests, so
every run deletes the aDSO `ZFMSALESA` (`CL_RSO_ADSO_API=>DELETE`), the cube (`IWP_ICUBE_DELETE`), the CDS views of
the characteristics (`ZZXXMLA1_CL_BW_VIEW_GEN=>DELETE`) and then all InfoObjects (`RSDG_IOBJ_MULTI_DELETE`) and creates
them again: no skip-if-exists, no migration logic. The providers and the views go first because BW refuses to delete a
characteristic that is used, and a view uses the data elements of the characteristics' attributes ("Data element
/BIC/OIZFMFAMILY still used in table/view ZZXXMLA1V...")). After the load the run generates the views again, under
the next free numbers (other cubes' views, the demos', keep theirs), so the schema files on the server name views that
are gone: run `python scripts/sap-files.py deploy` after it, which puts the new names in (`FoodmartBW.xml` names the
views by placeholder, `ZZXXMLA1_C_ZFMPROD`, the reference database by the same names). Time is not modelled with BW time characteristics: `ZFMDATE` is a plain `CHAR 10` characteristic keyed
by `the_date` (`YYYY-MM-DD`) with the other `time_by_day` columns as flat attributes (BW ignores attributes on `DATS`
characteristics). Writing a key to a characteristic generates its SID automatically; the attribute values are not
generated and must be written by the loader.

The same run loads the data (`load_data`, after the cube is active), so "delete everything, create everything" includes
the rows: master data attributes through `RSDMD_WRITE_ATTRIBUTES_TEXTS` (writing a key generates its SID), the 86,837
facts through `RSDRI_CUBE_WRITE_PACKAGE` in one package. The facts must be rows of the cube's T-view
`/BIC/VZFMSALES2` (InfoObject names without `/BIC/`, `time_id` replaced by `the_date`); any other structure dumps with
ASSIGN_TYPE_CONFLICT in the generated cube writer. Unit sales and store sales equal FoodMart's totals and store cost is
225,627.2336. The names (`product_name`, `fullname`, `store_name`, `promotion_name`) are flat attributes `ZFMPNAME`, `ZFMCNAME`,
`ZFMSNAME`, `ZFMPRNAM` (CHAR 60, longest value 43), like in FoodMart, where they are ordinary dimension table columns; there
are no BW texts (BW generated no text tables for the flagged characteristics, so the flags were dropped).

The same run then creates the cube-type aDSO `ZFMSALESA` (`docs/schema-generator.md`, Test provider):
`CL_RSO_ADSO_API=>CREATE` with the template InfoCube (`GET_ADSO_FLAGS_FROM_MODEL_TMPL( 'C' )`: activate data, cube
delta only) saves and activates it in one call; every characteristic needs a master data check mode
(`SID_DETERMINATION_MODE`, `S` = during staging, else "Invalid master data check mode"). Characteristics `ZFMPROD`,
`ZFMCUST`, `ZFMSTORE`, `ZFMPROMO` and the standard `0CALDAY`, `0CALWEEK`, `0CALMONTH`, `0CALQUARTER`, `0CALYEAR`; the
three key figures with aggregation SUM. `RSDSO_WRITE_API` writes the facts into the inbound table and activates them
(rows of any structure, moved by field name; the run uses the inbound table's). The write API runs no
transformation, so the run derives the calendar characteristics from `the_date` itself (`0CALWEEK` with
`DATE_GET_WEEK`, BW's ISO week, not FoodMart's `week_of_year`). The table and field names are asked from BW, not
assumed, because the prefix depends on the BW namespace: `CL_RSO_ADSO=>GET_TABLNM` gives `AQ` `/BIC/AZFMSALESA1`
(inbound), `AT` `...2` (active), `VR` `...7` (reporting view: inbound and active together), `VE` `...6` (extraction
view), `V1` `/BIC/VZFMSALESA2`; `RSD_FIELDNM_GET_FROM_IOBJNM` gives the field of an InfoObject (`CALDAY`,
`/BIC/ZFMPROD`). Activation merges the 8 facts that share all characteristics, so the 7 view has 86,829 rows; its
totals are FoodMart's (266,773 / 225,627.2336 / 565,238.13).

Key figure precision: BW stores a `DEC` key figure with 3 decimals whatever `BAPI_IOBJ_CREATE` is given (domain
`RSKYFNUM`, DEC 17,3), which rounds FoodMart's 4-decimal `store_cost` (the total came out 225,629.566). The workaround
(SAP Note 460652) is to set `RSDKYF-DOMANM` to the standard domain `RSLONGCURR` (DEC 28,6) in the `M` and `A` rows and
activate the key figure again, which regenerates its data element; `create_keyfigure` does this with an `UPDATE` and
`main` activates the InfoObjects twice. Do not use `FLTP`. Key figure `ZAAA` is a hand-made reference for this setup.

Type rule for the flat attributes (checked against the CSVs: longest string 43 characters, all numeric values are
plain non-negative integers): visible `Numeric` attributes of the Mondrian schema are `NUMC 60`, `String` attributes
are `CHAR 60`, the one `Boolean` (`coffee_bar`) is `CHAR 1`. Hidden keys (`store_id`, `product_id`, `customer_id`,
`promotion_id`, `time_id`) are not attributes: the fact table joins on the SID columns, which BW always types as INT4.
Loader rules that follow from it: an empty numeric source value is loaded as 0 (the four sqft columns are empty for 5
of 25 stores, so the Sales cube shows a 0 member where FoodMart has a null one); `coffee_bar` is loaded as `X` for
true and blank for false; `fiscal_period` is empty in all 730 time rows and is kept as an empty attribute.

### The empty member and the SIDs

BW gives every characteristic an initial member (blank key, SID 0); Mondrian does not insist on one, but FoodMart already
uses id 0 for it in two dimensions (promotion 0 'No Promotion', store 0 'HQ'). `python scripts/add-empty-members.py` writes
a patched copy of the HSQLDB jar (`data/foodmart-bw/hsqldb-foodmart.jar`, git-ignored) with an id 0 row, all attributes
empty or 0 and the name 'No Product' / 'No Customer', for product (and product_class), customer and time_by_day;
`scripts/deploy-reference-schema.sh` installs that jar in the eMondrian container, and
`python scripts/export-foodmart-csv.py data/foodmart-bw/hsqldb-foodmart.jar` makes the CSV from it. The original jar is
not touched. (Existing id 0 rows of store and promotion keep their NULL attributes, which BW holds as blank or 0.)

In BW the SIDs are the FoodMart ids: `insert_sids` of the loader writes the SID table rows (`/BIC/S<char>`) with SID = id
(check flag set, the other flags are set by BW when the SID is used in the cube) before BW writes master data and facts,
and an id of 0 is sent as the initial key (SID 0). BW itself would number the keys in string order. Afterwards
`verify_sids` compares the SIDs used in `/BIC/FZFMSALES` with the foreign keys of the FoodMart facts (equal in all five
dimensions). Caveats: BW's own SID counter (number range BIM...) does not know these SIDs, so loading further data
through BW into these characteristics could hand out SIDs that exist already. The record of the initial key sits in a
modified version (M) after the API write, which only an attribute change run would activate; the loader writes the active
record directly and deletes the pending one.

### Same members in both systems

So that a member has the same name, order and key in the BW cube and in the eMondrian reference, the BW model follows these rules
(and `reference/schema/FoodmartBW.xml` mirrors them):
- the key characteristics (`ZFMPROD`, `ZFMCUST`, `ZFMSTORE`, `ZFMPROMO`, `ZFMDATE`) are `NUMC 10` and hold the FoodMart id (for the
  date the `time_id`); numbers read and sort as numbers, and the initial key `0000000000` is the id 0, the empty member. The
  date text (`the_date`) is the attribute `ZFMTHEDT` "The Date" (hierarchy `[Date.The Date]`);
- the coffee bar flag `ZFMCOFFE` is `CHAR 5` with `true` / `false`, as in the FoodMart data;
- BW has no NULL: missing texts are blank and missing numbers 0. The reference schema reads the FoodMart tables `store` and
  `time_by_day` through the views `store_d` and `time_d`, which give exactly that (manager, the four sqft columns, the date as
  text, fiscal period; `coffee_bar` as text). The data itself is not changed.

### The data lives in the program

The FoodMart rows are embedded in six generated classes in `$ZZXXMLA1`, one per table: `ZZXXMLA1_CL_FM_DATA_SALES`,
`_PRODUCT` (joined with product_class), `_CUSTOMER`, `_STORE`, `_PROMO`, `_TIME`. Each has `GET_CHUNKS`, returning a
`STRING_TABLE`; a line holds whole records, fields separated by `|`, records by `~`. The class header states the
column order, which is the contract with the loader. Only the columns the BW model uses are exported, and fact
decimals lose their trailing zeros. The source is about 4 MB (the fact class alone has 13,684 lines) and activates in
seconds.

Regenerate and redeploy (the classes themselves are not edited by hand):

    python scripts/export-foodmart-csv.py && python scripts/generate-foodmart-abap.py && scripts/deploy-foodmart-data.sh
    scripts/sap-sync.sh pull

Pitfalls found: an ABAP source line is limited to 255 characters (literals are cut at 220); `SPLIT ... INTO TABLE`
drops a trailing empty field, so no record may end with an empty field (`fiscal_period`, always empty, sits before
`quarter` for that reason; the generator stops if a record ends empty). `ZZXXMLA1_CL_CLASSRUN_FMCHECK` (in `$TMP`)
parses all six classes on SAP and prints record counts, field counts, a character checksum and the fact sums, which
equal the CSV and FoodMart's published totals.

## Mondrian's function table

`ZZXXMLA1_CL_MDX_FUNTABLE` is generated, not edited by hand:
`python scripts/generate-funtable.py <file>` runs `scripts/funtable/DumpFunTable.java` in the `emondrian` container
against the web app's jars and writes the class source. Write it into SAP with the ABAP FS tools (a new class first
gets SAP's template, which is replaced as a whole; the 42 KB source went over in three edits joined at a marker
comment), activate, then `scripts/sap-sync.sh pull`. The pulled `src/` file equals the generator's output.
The table holds `BuiltinFunTable` and then the user-defined functions `GlobalFunTable` adds to every schema (`IN`,
`MATCHES`, `CurrentDateMember`, `LastNonEmpty`, ...). `BuiltinFunTable` lists its resolvers in a different order in
each JVM run; only the order of the resolvers of one name matters, so a regenerated file may move lines without any
change in behaviour.

## Mondrian's schema definition

A schema is read into `ZZXXMLA1_CL_SCHEMA_DEF` (Mondrian's `MondrianDef`), which is generated, not edited by hand:
`python scripts/generate-schema-def.py` reads `mondrian/mondrian/src/generated/java/mondrian/olap/MondrianDef.java`
(the classes the pinned Mondrian build generates from `Mondrian.xml`; `scripts/schemadef/model.py`) and writes the
class and its test include into `src/`. The tests are the cases in `tests/schemadef/` and four real schemas
(`reference/schema/FoodmartBW.xml`, eMondrian's `Foodmart.xml`, Mondrian's demo `FoodMart.xml` and `SteelWheels.xml`);
the generator runs each through Mondrian in the `emondrian` container (`scripts/schemadef/DumpSchemaDef.java`) and the
test expects Mondrian's `toXML` output exactly, or Mondrian's error message. The hand-written runtime is the port of
eigenbase-xom: `ZZXXMLA1_CL_XOM_PARSER` (`DOMElementParser` over iXML), `ZZXXMLA1_CL_XOM_OUTPUT` (`XMLOutput`) and
`ZZXXMLA1_CX_XOM` (`XOMException`).

    python scripts/generate-schema-def.py && scripts/deploy-schema-def.sh && scripts/sap-sync.sh pull

`deploy-schema-def.sh` writes the four classes with `sapcli class write` (they must exist; create new ones with
`abapfs_create_object`) because the ABAP FS edit tool decodes backslash escapes, which the PCRE patterns and string
templates of these sources contain. The pulled files equal the generator's output except for line endings.

Rules of Mondrian's reading worth knowing (all covered by a case): children are read in the order of the definition
and whatever is out of place is dropped silently (a `<Dimension>` after the `<Measure>`s); an empty attribute is no
attribute; a Boolean is true only for `true` in any case; a required child is only checked if there is a next child.

## Catalogs (the schemas the server serves)

As in Mondrian, the catalogs are configured, not programmed: the server has files, as Mondrian's web application has
them, and adding a schema or a catalog is writing files. The files are rows of table `ZZXXMLA1_FILE` (path, content,
changed at/by; an object of the package, `src/zzxxmla1_file.tabl.xml`), read by
`ZZXXMLA1_CL_FILES`. Program `ZZXXMLA1_SETUP` (`ZZXXMLA1_CL_SETUP`, also `sapcli class execute ZZXXMLA1_CL_SETUP`)
deletes the schema builder's copies earlier setups wrote below `/schema/` (it is served from
the code, `ZZXXMLA1_CL_WEB_APP_FILES`) and writes, if there is none, a data
sources file with one data source and no catalog (`ZZXXMLA1_CL_FILES=>default_datasources`); the FoodMart catalog is
not part of it (`scripts/sap-files.py deploy`):

- `/WEB-INF/datasources.xml`: Mondrian's data sources file, read by `ZZXXMLA1_CL_REPOSITORY` as Mondrian's
  `FileRepository` reads it (`DataSourcesConfig` through the XOM parser): the data sources (`DISCOVER_DATASOURCES`, the
  `DataSourceInfo` property, matched by name or by the connect string without `Jdbc*`), each with its catalogs, each
  catalog the path of its schema file in `<Definition>`. Our copy is `reference/schema/datasources-sap.xml`: like the
  container's `reference/schema/datasources.xml`, without `Jdbc` (every catalog is read from the SAP database) and with
  an empty `URL` (`DISCOVER_DATASOURCES` then gives the URL of the request).
- the schema files, e.g. `/WEB-INF/schema/FoodmartBW.xml` (= `reference/schema/FoodmartBW.xml` with the views' names
  put in: the repository's schemas name each dimension table by the placeholder of its characteristic's view,
  `ZZXXMLA1_C_ZFMSTORE`, and `deploy` replaces it by the database view SAP has, `ZZXXMLA1V...`, generating the view
  if there is none; a view's number depends on the views of the system's other cubes, so no schema of the repository
  names one). `ZZXXMLA1_CL_SCHEMA`
  reads a catalog's schema file when a request needs its cubes (`load`: an Execute its catalog, a rowset of cubes the
  catalogs its Catalog property and restrictions select), once per session; a broken catalog fails only the requests
  that load it. `LAST_SCHEMA_UPDATE` is the time the file was written.

`scripts/sap-files.py` writes and reads them through `sapcli abap run` as the user of `.env.sap`; the endpoint writes
them only in the schema generator's `accept` (`ZZXXMLA1_CL_SCHEMA_API`: a schema file and its catalog); in Git Bash set `MSYS_NO_PATHCONV=1`, or it turns `/WEB-INF/...` into a Windows path.
A new file is read by the next request.

    python scripts/sap-files.py deploy             # FoodmartBW(Drill).xml with SAP's view names; merges datasources-sap.xml's catalogs into the server's, keeps the others
    python scripts/sap-files.py put my/Sales.xml /WEB-INF/schema/Sales.xml   # a new schema; then a <Catalog> for it in
    python scripts/sap-files.py put reference/schema/datasources-sap.xml /WEB-INF/datasources.xml   # datasources-sap.xml
    python scripts/sap-files.py list | get <path> | delete <path>
    python scripts/generate-web-app-abap.py        # web/schema/ into ZZXXMLA1_CL_WEB_APP_FILES, served under /zzxxmla1/schema/
    scripts/deploy-reference-schema.sh             # the same schema to eMondrian

Limits: a catalog name is one catalog of the server (two data sources may list it only with the same Definition), and a
cube name is one cube of the server (Mondrian allows the same cube in two catalogs; the engine finds cubes by name).
The `DataSourceInfo` of a catalog or a data source is not used for the connection. The rows of `ZZXXMLA1_FILE` go to
another system as table entries (`R3TR TABU ZZXXMLA1_FILE`, delivery class C) in a transport.

`scripts/sap-write.sh <name>...` writes any class (main source and test include)
or interface from `src/` with sapcli and activates it; `scripts/sap-write.ps1 <name>...` does the same in PowerShell
and names the step that failed (it stops that object, it does not retry). Every sapcli call is a session of its own,
one after the other, and sapcli never closes it: the stateful ADT session of each write (for the lock) stays in SM04
until it times out, four or five per class. Prefer `scripts/sap-write.py <name>...` (run with sapcli's Python,
`"$LOCALAPPDATA/pipx/pipx/venvs/sapcli/Scripts/python.exe" scripts/sap-write.py ...`): one connection per object writes
its includes and activates, then ends the stateful context and logs off, so SM04 stays empty. It also writes programs
(`zzxxmla1_setup`).
With `--together` it writes all the objects in one session and activates them in one activation, for objects that
need each other (a changed interface such as `ZZXXMLA1_IF_MDX_EVALUATOR` and the classes that implement or use it). Classes have no local includes (CLAUDE.md): `sap-write.py` empties a local definitions
or implementations include that still holds code in SAP.

Work processes in PRIV mode: an ADT session on a large class (`ZZXXMLA1_CL_MDX_ENGINE`) can exceed its extended
memory and go into private memory; its dialog work process then stays bound to the session ("On Hold, ABAP Session in
PRIV Mode" in SM66) until the session ends or times out. The development system has seven dialog work processes, so a
few writes in a row, or retry loops, leave none free: new sessions fail with `ICMENOSESSION` (HTTP 400) or 503. Write
one class at a time and wait for its result; free pinned work processes in SM04 (end the HTTP sessions of DEVELOPER),
or wait for the timeout. `compare-applicable.py` runs three statements at once (`--workers`), each holding a dialog
work process while it runs. Dimension tables are read with native SQL (`ZZXXMLA1_CL_SQL`, ADBC); a
failed statement is the SOAP fault `Server.00UE001` with the statement and the database's message.

## Checking for NetWeaver 7.50

The code must run on NetWeaver 7.50 (`docs/mvp-scope.md`), but the development system is ABAP Platform 2025 and
activates newer syntax. `scripts/abaplint.sh` checks `src/` offline with abaplint's 7.50 grammar (`abaplint.json`,
version pinned in the script; npx fetches it) and with a syntax check against stubs: SAP's standard objects from
github.com/abaplint/deps. The project keeps no stubs of its own, so that it contains no copy of SAP source: code does
not name the constants of SAP's type pools that deps lacks (BW's RS, RSD, RSDMD) but declares its own in the class
(`c_objvers`, `c_iobjtp`, `c_tabclass`; `abap_true`/`abap_false` for `rs_c_true`/`rs_c_false`). Run it after every
change; it takes seconds.
abaplint does not know the parameters of built-in functions, so the script also searches for `pcre =`.
7.50 replacements used so far: `RAISE EXCEPTION TYPE cx EXPORTING ...` for `RAISE EXCEPTION NEW` (7.52); for a
factory method (`of_code`, `create`) the raising helpers `ZZXXMLA1_CX_XMLA=>raise_code` and
`ZZXXMLA1_CX_MDX_EVALUATION=>raise_error`, because `RAISE EXCEPTION` takes no expression in 7.50; `x = x && ...` for
`&&=` (7.54); POSIX `regex =` for `pcre =` (7.55).

## Tool quirks (ABAP FS MCP)

- Deploy ABAP with these tools: create (`abapfs_create_object`), edit (`replace_string_in_abap_object`, a new object's
  template replaced as a whole), `get_abap_diagnostics`, `abapfs_activate_object`, `abapfs_run_unit_tests`. Use
  `scripts/sap-sync.sh pull` afterwards to mirror SAP into git. There is no delete tool:
  `sapcli class delete <name>` (logon as in `sap-sync.sh`) deletes a class.
- ADT does not store comments between the methods of an implementation section, nor lines over 255 characters.
- `abapfs_run_unit_tests` runs only tests of `DURATION SHORT` and `MEDIUM`: for a class with long tests (the engine's,
  `ZZXXMLA1_CL_MDX_ENGINE`) it reports "No test classes found". sapcli runs all durations:
  `sapcli aunit run class ZZXXMLA1_CL_MDX_ENGINE --output human` (logon as in `sap-sync.sh`).
- A table's source (`define table`) can be edited with `replace_string_in_abap_object` (workspace URI of type
  `TABL/DT`), but `abapfs_activate_object` fails with status 400; `sapcli table activate ZZXXMLA1_TRACE` activates it
  (the name in upper case: in lower case sapcli fails with "Deserializing wrong object"). The table's `.tabl.xml` in
  `src/` is then changed by hand.
- Edit one object with `replace_string_in_abap_object` one call at a time: parallel calls on the same file each report
  success, but they overwrite each other and only some of the changes remain.
- A `\uXXXX` in an edit's text arrives decoded (as the character); write `\` && `u20ac` to keep it literal.
- The editor's checker accepts some things the activation rejects (a table expression after a method call such as
  `meth( )->attr[ 1 ]`, `APPEND ... TO itab[ ... ]-comp`): activate to be sure.

- `replace_string_in_abap_object` applies the new text like JavaScript's `String.replace`: `$$` becomes `$`, and a
  dollar followed by a backtick inserts the text before the match, so write every `$` as `$$`. Backslash escapes in the
  text arrive decoded (newline, form feed, ...): build backslashes in code (`cl_abap_conv_in_ce=>uccp( '005C' )`).
- ABAP: `CONV int8( f )` and `CONV decfloat34( f )` are not exact for 16-17 digit values; split a double's mantissa
  into exactly convertible halves when its exact value matters (`ZZXXMLA1_CL_MDX_FORMAT=>shortest_digits`).
- `abapfs_get_workspace_uri` needs `objectType` (e.g. `CLAS/OC`); the test include has the URI
  `/sap/bc/adt/oo/classes/<name>/includes/testclasses` (read with `abapfs_get_object_by_uri`).
- `abapfs_activate_object` takes the workspace `adt://...` URI, not the ADT path.
- `abapfs_search_objects` types are plain (`DEVC`, `CLAS`), not `DEVC/K`.
- SQL tool: multi-line statements are fine and long single-line ones may fail; no `UP TO n ROWS` (use `maxRows`).
- `replace_string_in_abap_object`: do not send several edits of the same object in one batch. They run in parallel and
  can overwrite each other although every call reports success; check with `abapfs_search_object_source` or send them one
  after the other. The first edit after a pause may fail with "All locks dropped due to expired sessions": send it again.
