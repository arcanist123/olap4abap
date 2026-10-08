# Test strategy

## Idea

Load the FoodMart dataset into BW (InfoObjects plus a HANA-optimised cube) and reuse the Mondrian integration tests
that fit the MVP scope. The tests give known queries with known answers.

## What the Mondrian tests look like

- Location: `mondrian/mondrian/src/it/java/mondrian/**` in the fork (there is no `src/test`). 2,967 `public void test...`
  methods across ~217 classes, e.g. `test/BasicQueryTest` (179), `olap/fun/FunctionTest` (589), `xmla/XmlaBasicTest` (56).
- Each test runs an MDX query against FoodMart and compares the result with expected text embedded in the Java source
  (`Axis #0:` ... `Axis #1:` ... `Row #0: ...`). That text can be compared directly with the ABAP server's output, so the
  tests can be reused without the Java harness. XMLA tests keep expected responses in `*.ref.xml` files.
- FoodMart data: `mondrian/demo/FoodMartCreateData.zip` (about 87k fact rows for 1997, 10k customers, 1.5k products).
  Schema: `eMondrian/src/main/webapp/WEB-INF/schema/Foodmart.xml`.

## Rough scope estimate (keyword heuristic - coarse, not exact)

2,967 total; ~826 excluded by MVP scope (custom inline schemas 349, virtual cube 207, non-SUM measures 172, roles 143,
parent-child `Employees`/HR 104, aggregate tables 82, ragged 49, drillthrough 29; tests may fall in several groups);
~2,141 remaining, of which ~769 need multi-level hierarchy navigation (`.Children`, `Descendants`, `ParallelPeriod`,
`YTD`, ...) and ~1,372 are single-level. Because level-based hierarchies over flat attributes are in the MVP, ~2,100 are
in play. Per file: BasicQueryTest 76 flat / 135 clean, FunctionTest 189 / 533, XmlaBasicTest 44 / 56.

## Plan

1. Done: the FoodMart InfoObjects and cube `ZFMSALES` (flat attributes, 3 SUM key figures, one HANA-optimised cube for
   `sales_fact_1997`) are in BW and are the project's main data source.
2. Done: `ZZXXMLA1_CL_BW_FOODMART_GEN` creates and loads them from code in `src/`; totals match FoodMart's (see
   `environment.md`).
3. Write a FoodMart schema whose tables/columns point at the BW tables (expected results use FoodMart names such as
   `[Customers].[USA].[CA]`).
4. Points to get right: BW keys are upper case by default (allow lower case or use IDs as keys and names as texts);
   member order needs an ordinal column; only the 1997 fact table is needed.
5. Extract MDX + expected output from the in-scope tests into data files and run them against the ABAP endpoint.

## Reference traffic

`reference/` holds exchanges captured from the running eMondrian container (start with
`discover_datasources/request.xml` and `response.xml`). Capture more with the same curl pattern (see
`docs/environment.md`) as the endpoint grows: DISCOVER_PROPERTIES, DBSCHEMA_CATALOGS, MDSCHEMA_CUBES, an MDX Execute,
SOAP faults.

## Excel through the proxy

`python scripts/xmla-proxy.py` puts a logging proxy between Excel and the servers: `http://localhost:8081/` goes to
eMondrian (container `emondrian`, catalog `ZFOODMART`), `http://localhost:8082/` to SAP, `http://localhost:8083/` to
container `emondrian-git` (port 8091, the same build with the FoodMart sample) and `http://localhost:8084/` to container
`emondrian-release` (port 8090, the released eMondrian) (Excel: Data > Get Data > From Analysis Services, that address
as server). All four ports listen whether or not the server behind them runs; a server that is down answers 502 Bad
Gateway until it is started.
`--https` makes the same ports speak https (`https://localhost:8082/`, ...) for clients that want it: with `--cert` and
`--key`, or a self-signed certificate for localhost and this machine's name that the proxy makes with openssl (Git for
Windows has one) under `logs/xmla-proxy/tls/` and reuses. Excel only connects when Windows trusts it; import it once
with `certutil -user -addstore Root logs/xmla-proxy/tls/cert.pem`. The backends keep their own scheme.
Each exchange is printed as one line and saved in full under `logs/xmla-proxy/<start time>/` (git-ignored). A
conversation Excel had with eMondrian can be replayed against SAP from those files to find the gaps before Excel is
pointed at SAP. What Excel (MSOLAP 17) does: it offers binary XML and compression in
`X-Transport-Caps-Negotiation-Flags` and takes plain XML when the server ignores that; it opens a session with an
Execute without statement and `BeginSession`, sends `Session SessionId=...` with every request and ends with
`EndSession`; it sends no `Content`, so every Discover answer needs the rowset's `xsd:schema` (Content SchemaData).

Keep Only Selected Items (right-click a pivot item, Filter): Excel first sends its item path query (`with member
measures.__XlItemPath as Generate(Ascendants(...))`, `__XlSiblingCount`, `__XlChildCount`) and only then the filtered
query, a subselect `FROM (SELECT ({member}) ON COLUMNS FROM [cube])`. It sends that only if the integer child count is
typed `xsd:int`; after an `xsd:integer` it silently does nothing. The reference fork writes every Integer cell as
`xsd:integer` (`XmlaHandler`, "fix for Power BI - does not support xsd:int"), so the filter fails on it; its release
(container `emondrian-release`) writes `xsd:int`, and also reports the provider as SSAS 2008 R2 (`ProviderVersion`
10.50), so Excel filters there with `VisualTotals` sets instead of subselects. olap4abap writes `xsd:int` when the
request's `SspropInitAppName` is `Excel` and `xsd:integer` otherwise (`ZZXXMLA1_CL_XMLA_MDDATASET=>build`).

Sessions keep no state on SAP (decision and when to revisit it: `docs/mvp-scope.md`, session decision); Mondrian
faults for a session id it does not know, SAP does not (cases `session_*`).

## XMLA test cases

Every captured exchange in `reference/<case>/` (`request.xml`, `response.xml`, optional `ignore.txt`) is a test case.
`python scripts/xmla_test.py` posts each request to the SAP endpoint (default
`http://localhost:50000/zzxxmla1?sap-client=001`) and compares the response with the captured one as canonical XML
(formatting ignored; names, namespaces, order and values compared). `ignore.txt` lists elements whose text may
differ, e.g. the data source URL. `--url http://localhost:8080/emondrian/xmla` runs the same cases against eMondrian
itself, which validates the case before the ABAP side is built. Both answers go through
`scripts/reference_texts.py` first: where eMondrian names itself (the `Mondrian Error:` prefix, faultactor `Mondrian`,
`mondrian.olap.fun.MondrianEvaluationException`, Java class names, provider name) olap4abap writes its own name
(`olap4abap Error:`, ...), and the mapping makes the two equal; `compare-applicable.py` does the same. To add a case: capture request and response from
eMondrian (curl pattern in `environment.md`), put them in a new directory, run the script, see it fail on SAP, implement.

Cases so far, all passing on eMondrian and SAP: `discover_datasources`, `discover_properties`, `dbschema_catalogs`, `mdschema_cubes`, `discover_schema_rowsets`, `mdschema_measures`, `mdschema_dimensions`, `mdschema_hierarchies`, `mdschema_levels`, `mdschema_members*` (25 cases, see below), and the empty rowsets `mdschema_sets`, `mdschema_kpis`, `mdschema_actions`, `mdschema_properties`.
The last two read the model tables (catalog = InfoArea of the cube); the reference schema `reference/schema/FoodmartBW.xml`
is written so that eMondrian names things as our model does (catalog `ZFOODMART`, cube `ZFMSALES`). Unsupported request
types and invalid XML get a SOAP fault with HTTP 500 (checked by hand).

## Schema generator API

`python scripts/schema_api_test.py` calls `/zzxxmla1/schema/api` over HTTP as the UI will: providers, the proposals of
`ZFMSALES` and `ZFMSALESA`, the errors (unknown provider or resource, wrong method, unreadable schema, bad catalog
name, a catalog name another schema file has); the aDSO proposal has no time dimension, only dimensions on views.
It changes nothing on the server. The unit tests of `ZZXXMLA1_CL_SCHEMA_API` cover the same plus adding a catalog to
the data sources file and replacing DDL names by views; one checks that `accept` loads all catalogs together (the
`ZFMSALES` proposal clashes with `ZFOODMART`'s cube). A successful `accept` changes the server's files, so it is
checked by hand: accept a proposal with the cube renamed under a test catalog, query it through XMLA, then restore
with `python scripts/sap-files.py put reference/schema/datasources-sap.xml /WEB-INF/datasources.xml` and
`delete /WEB-INF/schema/<catalog>.xml` (done 2026-10-06: `ZFMSALES` with the cube renamed, Unit Sales 266,773;
`ZFMSALESA` as proposed, which generated the views of `0CALWEEK`, `0CALMONTH`, `0CALQUARTER`, `0CALYEAR`: quarters
66,291 / 62,610 / 65,848 / 72,024, 53 weeks, stores as FoodMart).

## Schema builder (UI)

`python scripts/schema_ui_test.py` drives `/zzxxmla1/schema/` in headless Chromium (Playwright: `pip install
playwright` and `playwright install chromium-headless-shell`): the start page, the `ZFMSALES` proposal refused for its
cube name and loading once renamed, a user hierarchy with a member property, the unnamed-hierarchy clash and undo, the
accept dialog (cancelled), the XML, and a time dimension on the aDSO with its suggested level type. Every edit goes
through the server's `check`; nothing is written. `--shots <folder>` keeps a screenshot per step.

## MDX console (UI)

`python scripts/console_ui_test.py` drives `/zzxxmla1/schema/console.html` the same way, on catalog `ZFOODMART`: the
cube browser inserting a unique name, a grid of two axes (Product and Store crossjoined on the rows, the slicer shown)
and the same answer as a table, a flat table of three axes, a statement without axes and an evaluation error.

## Mondrian's own tests against our schema

The eMondrian container serves only our reference catalog `ZFOODMART` (`scripts/deploy-reference-schema.sh`, installs
`reference/schema/datasources.xml`), so its answers can be compared one-to-one with the ABAP server.
`python scripts/extract-mdx-tests.py` pulls the MDX statements on `[Sales]` out of the Java tests, renames the cube to
`[ZFMSALES]`, runs them in the container and keeps those Mondrian accepts in `tests/mdx/applicable.json`.
Result on 2026-10-03: 973 statements, 853 different, **59 run** on our schema; the rest used hierarchies our model did
not have (`[Time].[1997]`, `[Store].[USA]`, `[Customers]`, ...). With FoodMart's hierarchies in the schema **382 run**
(2026-10-04). They are the MDX tests for the ABAP engine; the
expected answer is what the container returns. Mondrian's expected results in the Java source are for the original
FoodMart schema and do not apply.
The count can drop by one between runs: the statements run in parallel, and `ParameterTest.java:272` fails when
`ParameterTest.java:217` has defined the parameter `sProduct` before it with another type (Mondrian keeps parameters
per schema); run alone it passes. Compare the list with git before accepting a change.

Static versus model-driven answers: `discover_datasources` (one data source), `discover_properties` (property definitions in
`ZZXXMLA1_CL_XMLA_PROPDEF`, only the default `Catalog` comes from the model) and `discover_schema_rowsets` (rowset list in
`ZZXXMLA1_CL_XMLA_ROWSETS`) are static knowledge of the engine, ported from Mondrian. `dbschema_catalogs`,
`mdschema_cubes` and `mdschema_measures`, `mdschema_dimensions`, `mdschema_hierarchies`, `mdschema_levels` read the model tables (dimensions and hierarchies also count the members of each characteristic in BW; measures also the order of dimensions, hierarchies and levels for LEVELS_LIST). `discover_schema_rowsets` lists all 29 rowsets as Mondrian does, including ones
not implemented yet (they answer with a SOAP fault).

## Rowsets: state

All 29 rowsets of `DISCOVER_SCHEMA_ROWSETS` are answered. Source of the rows:

| Source | Rowsets |
|---|---|
| Model tables (and BW master data for counts and members) | `DBSCHEMA_CATALOGS`, `_SCHEMATA`, `_TABLES`, `_TABLES_INFO`, `_COLUMNS`; `MDSCHEMA_CUBES`, `_DIMENSIONS`, `_HIERARCHIES`, `_LEVELS`, `_MEASURES`, `_MEMBERS`, `_MEASUREGROUPS`, `_MEASUREGROUP_DIMENSIONS` |
| Static, ported from Mondrian | `DISCOVER_DATASOURCES`, `_PROPERTIES`, `_SCHEMA_ROWSETS`, `_ENUMERATORS`, `_KEYWORDS`, `_LITERALS`, `DBSCHEMA_PROVIDER_TYPES`, `MDSCHEMA_FUNCTIONS` (442 functions of Mondrian, also those the MDX engine does not have yet) |
| Empty (correct structure, no rows) | `MDSCHEMA_SETS`, `_KPIS`, `_ACTIONS`, `_PROPERTIES` (the model has none); `DISCOVER_XML_METADATA` (eMondrian also has none) |
| Empty, cannot match | `DISCOVER_SESSIONS` (Mondrian lists its own live sessions), `DBSCHEMA_SOURCE_TABLES` (Mondrian lists the tables of its JDBC database); no cases |
| Fault as in eMondrian | `DISCOVER_CSDL_METADATA` (licence error of a module that eMondrian does not ship) |

Static data is in `ZZXXMLA1_CL_XMLA_PROPDEF` (properties), `_ROWSETS` (the rowset list) and `_STATIC` (the other lists; generated once from the
captured eMondrian answers). Details of what Mondrian does with restrictions (checked in the container): `MDSCHEMA_FUNCTIONS` applies only
FUNCTION_NAME (exact, case sensitive); enumerators, keywords and literals ignore restrictions; a DATA_TYPE restriction on the provider types
gives no rows and BEST_MATCH is ignored; `DBSCHEMA_COLUMNS` with a COLUMN_NAME restriction returns 2,975 rows (not matched, no case);
the answers of `DBSCHEMA_COLUMNS` (2,976 rows) and `MDSCHEMA_MEMBERS` (27,813) are kept as row counts and were compared row by row with eMondrian.
Cardinality of `DBSCHEMA_TABLES_INFO` is a constant 1000000 in Mondrian and here.

## Execute (MDX) cases

`reference/execute_*` (68 cases) are Execute requests captured from eMondrian with
`python scripts/capture-execute.py <name> <mdx | @index of tests/mdx/applicable.json>` (properties Format
Multidimensional, AxisFormat TupleFormat, Content SchemaData). `ignore.txt` skips the two update timestamps. They cover the
first two groups of the 59 applicable statements: no axes (`select from`, `where [Measures].[X]`), empty sets on one or two
axes (with comments, a commented-out statement), one measure, `[Measures].Members`, `[Measures].[Measures].Members`,
`{[Measures]}` (default member). Behaviour seen in the container that the engine copies:
- `[Measures].Members` includes the hidden `Fact Count` measure Mondrian adds to every cube (count of fact rows, 86,837);
- cells are `xsd:double`; the default format of a measure is `#,###.###` (Java DecimalFormat, half-even rounding);
- a query without axes has one cell, an empty axis has none (`<CellData/>`); a `where` clause appears as `SlicerAxis`;
- group 3, dimension members: `[Store].Children`, `.Members`, `{[Store], [Store].children}`, NON EMPTY, `[Product].Members`
  (1,562 members), `CrossJoin`, `NonEmptyCrossJoin`, `Hierarchize(DrillDownLevelTop(...))`. Empty cells are written
  `<Cell><FmtValue/></Cell>` (no Value); `DisplayInfo` is the number of children plus 0x10000 when the next tuple's member is
  a child and 0x20000 when the parent equals the previous member's parent (the slicer only has the child count); when a
  hierarchy is on two axes the first axis wins (Mondrian sets the last axis first). `NonEmptyCrossJoin(Product.children, Store)`
  gives 86,154 tuples in the container (65 MB) and was not kept; `Aggregate({})` is `execute_calc_56`;
- coverage of `tests/mdx/applicable.json`: of the 59 statements of the first schema 58 have a case and pass
  (`execute_nativizeset`, `execute_drilldownleveltop_empty_arg`, `execute_select_from_upper`, `execute_product_members`
  and `execute_unit_sales_by_product_children` among them). The one left out is
  `NonEmptyCrossJoin([Product].[All Products].Children, {[Store].[All Stores]})`: eMondrian's native evaluation returns
  each tuple once per fact row (see below), the engine once. Of the 382 statements of the schema with hierarchies, 381
  give eMondrian's axes and cells (compared statement by statement on 2026-10-05); #64 differs in the last digits of a
  large `Aggregate` (eMondrian's database adds in another order: 565238.1300000012). The crossjoins of all customers and
  products (#85, #142, #153, #241: 16 million tuples before the empty ones are removed; #148, #149, #150: 6.6 million)
  are native now, as in eMondrian: only the combinations with facts are read. Before the result limit they ended in
  memory dumps (`TSV_*_NO_ROLL_MEMORY`), and several at once used up the roll memory of the whole instance
  (`SYSTEM_NO_ROLL` in other sessions, ADT 503 and `ICMENOSESSION`); the limit stays as the guard of crossjoins that are
  not native. The native order (`NON EMPTY Crossjoin(Descendants([Customers].[USA], [Customers].[City]),
  {[Product].[All Products], [Product].[Drink].[Dairy]})`, #144: all of the first product before the second) is
  eMondrian's multi-variant expansion. `compare-applicable.py` prints every statement's time on SAP and eMondrian as it
  completes and the slowest at the end.

Parse errors: `execute_error_syntax`, `execute_error_lexical` and `execute_error_invalid_axis` are the three fault
shapes of Mondrian's parser: `Server.00HSBB01` "Mondrian Error:Syntax error at line L, column C, token 'T'" (and
"Invalid axis specification ..."), and `Server.00UE001` "Internal Error" with JavaCC's "Lexical error at line L, column
C.  Encountered: ..." (no "Mondrian Error:" prefix). The parser's unit tests (`ZZXXMLA1_CL_MDX_PARSER`, test include) hold
the cases of Mondrian's `ParserTest` with its expected unparse texts and many error texts captured from eMondrian. Where
`ParserTest` checks the old JavaCUP parser, or still writes `FROM cube` (`CUBE` is a keyword in eMondrian's grammar),
the tests follow what eMondrian answers.

Parser: a port of Mondrian's `MdxParser.jj`. `ZZXXMLA1_CL_MDX_TOKEN_MANAGER` is the JavaCC token manager: longest
match, keywords before identifiers, line and column counted as `SimpleCharStream` does (tab stops of 8, `\r\n`, a closing
newline added), tokens read only when the parser asks for them. `ZZXXMLA1_CL_MDX_PARSER` has one method per production
of the grammar, with the same lookahead decisions (`LOOKAHEAD(dmvSelectStatement())`, `IS NULL`, `NOT MATCHES`, ...). It
returns Mondrian's parse tree, unresolved: the statement (Formula, QueryAxis, Subcube, DRILLTHROUGH, EXPLAIN, DMV,
CREATE, ...) and `ZZXXMLA1_CL_MDX_NODE` as `Id` / `UnresolvedFunCall` (with `Syntax`) / `Literal`. As in
`createCall`, `x.Name` is a property call when `Name` is one of the 29 property words of Mondrian's `BuiltinFunTable`
(Members, Children, CurrentMember, ...), and otherwise a further segment of the identifier.

Validator: a port of Mondrian's `Query.resolve` and `ValidatorImpl`. It turns the parse tree into resolved expressions,
as Mondrian does before it compiles a query:
- `ZZXXMLA1_CL_MDX_SCHEMA_READER` is `SchemaReader` over the model, with the `lookupChild` rules of cube, dimension,
  hierarchy, level and member (`SsasCompatibleNaming=false`). For example `[Store].[Store]` is the hierarchy,
  `[Customers].[City]` and `[Customers.City].[City]` are levels, `[Unit Sales]` is the measure, `[Store].[USA]` is a
  child of the All member, `[Store].[Store City].[Seattle]` the first member of the level with that name
  (`RolapLevel.lookupChild`, on any level), and `[Store.Store Id].[Store Id].&[1]` is a key (the keys of the level and
  of the levels above it up to one with unique members). A dimension stands for its hierarchy named like it
  (`DimensionType.getHierarchy`), so `[Store].Members` and `[Store].Children` on two axes are the same hierarchy twice.
- `ZZXXMLA1_CL_MDX_FUNTABLE` is `BuiltinFunTable`, generated from eMondrian's jar by `scripts/generate-funtable.py`:
  331 resolvers with their signatures, plus the property and reserved words.
- `ZZXXMLA1_CL_MDX_TYPE` is `mondrian.olap.type`.
- `ZZXXMLA1_CL_MDX_VALIDATOR` resolves identifiers (`Util.lookup`; a lone reserved word becomes a symbol). It picks each
  call's function definition by the cheapest conversions (`TypeUtil.canConvert`), and applies the member/tuple-to-set
  conversion by wrapping the argument in braces. It gives every node its type (`castType`, plus the result types of
  `SetFunDef`, `TupleFunDef`, `ParenthesesFunDef` and `CrossJoinFunDef`). It checks the axes as `Query.resolve` does.
- All resolvers that resolve by their signatures work. Of the resolvers with logic of their own, `{}`, `()`,
  `CrossJoin`, `*`, `Order` and `Cast` are ported. A call of the others (`CASE`, `CoalesceEmpty`, ...) is a fault "... is not implemented
  yet", and so are `WITH` and subselects.

The unit tests of the schema reader and the validator use identifiers and error texts captured from eMondrian. The
reference cases `execute_error_no_function`, `execute_error_object_not_found`, `execute_error_independent_axes` and
`execute_crossjoin_star` check them over XMLA.

Engine: `ZZXXMLA1_CL_MDX_PARSER` and `ZZXXMLA1_CL_MDX_VALIDATOR` (above), then `ZZXXMLA1_CL_MDX_ENGINE` (Mondrian's
`RolapResult`). The engine evaluates the resolved tree: each argument as the category its signature declares, with
Mondrian's implicit conversions (a member where a value is wanted is the cell of the context with that member,
`MemberValueCalc`). The evaluation context is `ZZXXMLA1_CL_MDX_EVALUATOR`, a port of `RolapEvaluator`: the current member
of every hierarchy (at first the default members), a command stack for `savepoint` / `restore`, `push`, the non-empty
and eval-axes flags, and `evaluateCurrent` (the cell of the context, read from the facts). As in `RolapResult`, the
slicer is evaluated in the default context and its members become the context (`setSlicerContext`); each axis is
evaluated in that context with its NON EMPTY flag (`executeAxis`); the cells are computed by setting one tuple of each
axis, the last axis first, then the slicer, and evaluating the current cell (`executeStripe`). NON EMPTY then removes the
positions whose cells are all empty (`NonEmptyResult`). `CurrentMember` reads the context; `NonEmptyCrossJoin` keeps the
tuples whose cell in the context is not empty; `DrilldownLevelTop` ranks the children by the value in the context (empty
last, as `FunUtil.compareValues`). Its unit tests (savepoints, push, slicer, cells and Fact Count emptiness) use
FoodMart numbers. The reference cases `execute_drilldownleveltop_slicer` (ranking in the slicer's context) and
`execute_currentmember_slicer` check the context over XMLA. eMondrian's native `NonEmptyCrossJoin` under a slicer
returns a tuple once per fact row (e.g. `NonEmptyCrossJoin([Store].Children, {[Measures].[Store Cost]})` with
`where [Product].[3]`: `[Store].[13]` 8 times); the engine returns each tuple once, so no such case is kept.

Calculated members (`WITH MEMBER`), as `Query.resolve` and `RolapEvaluator` do them: the validator first creates every
member of the formulas (`Formula.createElement`: below the parent member on the next level, else on the first level of
the hierarchy; unique name as `RolapMemberBase.setUniqueName`) and adds it to the schema reader, which then finds it by
name (`QuerySchemaReader`, `Util.matches`). Then it resolves each formula (a value, not a set) and its properties, takes
`SOLVE_ORDER` from a constant, and finds the format expression (`getFormatExp`: the `FORMAT_STRING` property, else for
a measure the format of the first member in the formula that has one; a numeric literal has `NumericType`, so `'23'`
alone has none). `[Measures].Members` leaves calculated members out, `AllMembers` adds them after each level's members.
In the evaluator a calculated member in the context is a calculation: `evaluateCurrent` takes the one that expands first
(`SolveOrderMode=SCOPED` as eMondrian is configured: higher solve order, then lower hierarchy ordinal; one without
`Aggregate` before one with), sets its hierarchy to the default member (`setContextIn`) and evaluates the formula through
`ZZXXMLA1_IF_MDX_CALC` (Mondrian's `Calc`, implemented by the engine). A cell's format string is `getFormatString`: of the
non-All members the one with the highest solve order that has a format (a stored measure -1 with its format string, a
calculated member with its format expression evaluated in the context), else `Standard` (`#,##0`). Values are typed
(null, double, integer, string, boolean, error); numbers are Java doubles (`TYPE f`), written as `Double.toString` (JDK
19+ shortest form, e.g. `0.3333333333333333`, `5.6523813E14`) without a trailing `.0`, `INF` for infinity
(`XmlaUtil.normalizeNumericString`); strings are `xsd:string`. The operators `+ - * /` and unary `-` follow
`BuiltinFunTable` (null is the identity of `+` and `-`; `*` and `/` with a null numerator are null; a null or zero
denominator gives Infinity / NaN). `reference/execute_calc_<n>` are the `WITH` statements of `tests/mdx/applicable.json`
(index n) that this covers, plus `execute_calc_ratio` (fractional doubles). Scalar functions: comparisons `= <> < <= >
>=` (numbers and strings; false if one side is null, `BooleanNull`), `AND OR XOR NOT` (short-circuit except while the
axes are evaluated), `IIf`, `||`, `Len` (an Integer, written `xsd:integer` as eMondrian does), `String`, `Mid` (Vba),
`<Member>.Name`, and `Parameter` (no value is ever set, so its default). Format strings are a port of Mondrian's
`mondrian.util.Format` (`ZZXXMLA1_CL_MDX_FORMAT=>format_number` / `format_text`): the token table and
`parseFormatString`, sections (positive;negative;zero;null, with MONDRIAN-687's `|-` placement), numbers rounded half up
on their shortest decimal digits (`MondrianFloatingDecimal`), literals (any character that is no token, quoted text,
backslash escapes), `%` and thousands scaling, `<` `>` (a number is first formatted as Java's `NumberFormat` does),
predefined names (`Standard`, `Currency`, ...); the empty format string is `NumberFormat` (`#,##0.###`, half even). Not
ported: exponents (`0.00e+00`) and the text of dates. Its unit tests carry the single-line number cases of Mondrian's
`FormatTest`.

`Order`, `Cast`, `Aggregate` and evaluation errors (`execute_calc_5`, `_56`, `_57`; unit tests of the engine and the
validator):
- `Order(set, key [, ASC|DESC|BASC|BDESC] ...)`: the validator ports `OrderFunDef$ResolverImpl` (a set, then for each key
  a value and an optional symbol; any other reserved word is the fault "Allowed values are: {ASC, DESC, BASC, BDESC}",
  without the "Mondrian Error:" prefix). The engine sorts as `Sorter` does, with a stable merge sort (Java's sorts of
  objects are stable) and the keys as a comparator chain, the context not empty-filtered. Members: B-flags by value
  only (`BreakMemberComparator`), otherwise hierarchically (`HierarchicalMemberComparator`: an ancestor before its
  descendants also when descending, siblings by value, equal values in hierarchy order: calculated last, then ordinal,
  then key). Tuples: `BreakTupleComparator` (reversed if descending) or `HierarchicalTupleComparator` (member by
  member, the equal ones before set as the context, the whole result negated if descending), both only over the members
  whose hierarchy the key depends on (`TupleExpMemoComparator.dependentMembers`): tuples equal in those compare as 0
  and keep their order. `depends_on` ports `Calc.dependsOn`: literals and members are constant, a hierarchy depends on
  itself, a member or tuple evaluated as a value (`MemberValueCalc`) on every hierarchy it does not set, a call on its
  arguments. As `OrderFunDef.compileCall` does, a single key that is a member or tuple has its constant members (not
  used by the set) set as the context first and becomes the cell of the context (`ContextCalc` + `ValueCalc`, which
  depends on every hierarchy), or its one non-constant member; e.g. `Order({All Stores} x {P1, P2}, ([Unit Sales],
  [Product].[1]), DESC)` sorts the products by their own sales.
- `Cast(x AS STRING|NUMERIC|BOOLEAN|INTEGER)`: unknown type "Unknown type 'foo'; values are NUMERIC, STRING, BOOLEAN".
  `String.valueOf` (a numeric literal is its `BigDecimal` text, `1.50`), `Integer.parseInt` / `intValue` (truncates),
  `Double.valueOf`, `Boolean.valueOf` / greater than 0. A string that is no number fails the whole query as eMondrian
  does: `Server.00HSBD02` "XMLA MDX execute failed For input string: "1.5"" (a `NumberFormatException`, no evaluation
  error).
- `Aggregate(set [, numeric])`: the values of the set's tuples, not null, rolled up with the aggregator of the stored
  measure of the context (`AGGREGATION_TYPE`; only stored measures have one, so a calculated measure there is the error
  "Could not find an aggregator in the current evaluation context"): sum, count rolled up as sum (Fact Count over two
  products is 82), min, max; none is null (`Aggregate({})` is an empty cell). Distinct count and avg are not ported.
- Evaluation errors: `ZZXXMLA1_CX_MDX_EVALUATION` is `MondrianEvaluationException`. `compute_cell` catches it as
  `RolapResult.executeStripe` does: the cell's value is `xsd:string` "mondrian.olap.fun.MondrianEvaluationException: "
  plus the message, `FmtValue` "#ERR: " plus the same; the other cells and the query go on (an error in the format
  expression is ignored). Raised so far: a string or boolean where a number is wanted (`GenericCalc.evaluateDouble`:
  "Expected value of type NUMERIC; got value '123' (STRING)"), no aggregator, and the evaluator's infinite loop
  (without Mondrian's context stack), `Levels` out of range ("Index '2' out of bounds") or by an unknown name ("Level
  'store' not found in hierarchy '[Store]'"). Outside a cell (an axis, the slicer) the query fails as in eMondrian:
  `Server.00HSBD02` "XMLA MDX execute failed " plus the message, the description the message alone.
- `<Hierarchy>.Levels(<Numeric>)` (the (All) level is 0) and `<Hierarchy>.Levels(<String>)` (the level's name,
  case-sensitive); `NativizeSet(set)` is the set (below `NativizeMinThreshold`, 100,000 tuples, Mondrian does not
  nativize; native evaluation gives the same tuples).

Not yet: calculated sets (`WITH SET`), `CASE`, `CoalesceEmpty` and the other resolvers of their own; a dimension in
braces (`{[Store].[USA], [Store]}`) fails in the validator where eMondrian takes its default member.

Doubles: ABAP's `f` arithmetic is IEEE (bit for bit as Java), but `CONV int8( f )` and `CONV decfloat34( f )` are not
exact for 16-17 digit values (they round through about 17 decimal digits). `Double.toString` therefore takes the
double's exact value from its 53-bit mantissa, split into two exactly convertible halves, times a power of two. With the
17-digit conversion, `153.23 - 62.3546` (Store Sales - Store Cost of product 90) was written `90.87539999999999`
instead of Java's `90.87539999999998`: the same double, but Java writes the decimal nearest to its exact value.

Other parts: `ZZXXMLA1_CL_MDX_FORMAT` (number formats), `ZZXXMLA1_CL_XMLA_MDDATASET` (answer XML) and
`ZZXXMLA1_CL_XMLA_MDSCHEMA` (constant schema block, generated by `scripts/generate-mddataset-schema.py`),
`ZZXXMLA1_CL_MDX_FACTS` (cell values: the facts are grouped once per combination of hierarchies and levels by the
level columns down to the member's level, joined fact -> dimension view, and then looked up by the member's path of
keys; the slicer is part of a cell's filters), `ZZXXMLA1_CL_MODEL` (hierarchies, measures and members of the model,
shared with the rowsets; the members of a hierarchy are read as a tree in hierarchy order, a parent before its
children, children by key).

Hierarchies without All member (`RolapResult.loadSpecialMembers`, `evalExecute`): for a hierarchy without All member
Mondrian evaluates the slicer and every axis once per root member and merges the results (each tuple once;
hierarchized if a later evaluation adds tuples, unless the axis is an `Order`). Members of the hierarchy on the slicer,
or the top members of those on the axes, replace the roots; a calculated member starting an axis removes the dimension
its formula names last. A `TimeDimension` is skipped, and the schema's Time is one (its levels have time level types),
so its hierarchy without All member is evaluated with its default member `[Time].[1997]` only, as in FoodMart:
`DrillDownLevelTop({[Product].[All Products]}, 3)` gives the top three families of 1997
(`execute_drilldownleveltop_slicer`), and `Order(..., DESC)` sorts by the values of 1997. While Time was a plain
dimension, the empty year 0 was evaluated first, and these answers differed from FoodMart's. The engine ports both
paths; no hierarchy of the schema uses the merge now.

Compound slicer (a WHERE of several tuples, `RolapResult`, Execute Slicer): the members that are the same in all
tuples are the context, every other hierarchy of the tuples gets a placeholder (`CompoundSlicerRolapMember`), a
calculated member of the cube with solve order -99999 whose value is the cell rolled up over the tuples. In SCOPED
mode it gives way to a calculated member of the query without `Aggregate`, but expands before one with `Aggregate`
(whose measure then has no aggregator: "Could not find an aggregator in the current evaluation context"). The slicer
axis keeps the tuples, with the DisplayInfo flags of an axis; `CurrentMember` of a hierarchy with several slicer
members is an error (`CurrentMemberWithCompoundSlicerAlert` ERROR). Cases `execute_compound_slicer_members`,
`execute_compound_slicer_tuples`, `execute_compound_slicer_range`; they were captured from eMondrian with
`scripts/patches/compound-slicer.patch`, without it eMondrian returns empty axes (`docs/environment.md`).

Aggregates and set algebra (`UnionFunDef`, `ExceptFunDef`, `IntersectFunDef`, `HeadTailFunDef`, `DistinctFunDef`,
`SetItemFunDef`, `TupleItemFunDef`, `SetToStrFunDef`, `CountFunDef`, `SumFunDef`, `AvgFunDef`, `MinMaxFunDef`,
`RankFunDef`): tuples are equal when their members' unique names are; the aggregates evaluate the set and the values
with non-empty off and leave nulls out (`FunUtil.evaluateSet`), in Java's double arithmetic. Compile-time errors of a
call (`Expressions must have the same hierarchy`, `Allowed values are: {...}`) are faults of the query. Cases
`execute_union_hierarchize`, `execute_union_calculated_member` (`Hierarchize` with a calculated member),
`execute_sum_except_topcount`, `execute_avg_max_order`, `execute_distinct_topcount`, `execute_count_rank_settostr`.

Named sets (`WITH SET`, `SetBase`, `NamedSetExpr`) and aliases (`AS`, `Query.ScopedNamedSet`): a named set is evaluated
once per query in the context of the slicer, an alias each time its AS is; `Current` and `CurrentOrdinal` follow the
iteration of `Generate`, `Filter` and `Order`. eMondrian's `NonEmptyCrossJoin` of named sets is evaluated natively and
comes in hierarchy order (#155, #169), the engine keeps the order of the arguments, as for #144. Cases
`execute_named_set_order_currentordinal`, `execute_named_set_filter_currentordinal`, `execute_alias_descendants`,
`execute_named_sets_crossjoin`, `execute_named_sets_aggregate_union`, `execute_named_set_slicer_context`,
`execute_generate_string`, `execute_generate_named_sets`.

Member functions (`BuiltinFunTable`, `LeadLagFunDef`, `AncestorFunDef`, `AncestorsFunDef`, `ParallelPeriodFunDef`,
`PeriodsToDateFunDef`, `MemberOrderKeyFunDef`) and the null member (`RolapHierarchy.getNullMember`): where there is no
member to give, the null member `[Hierarchy].[#null]` (name `#null`, on a level like the All level), whose cells are
null and which `{}` leaves out. Cases `execute_orderkey_bdesc`, `execute_orderkey_parent`,
`execute_parallelperiod_uniquename`, `execute_periodstodate_sum`, `execute_rank_siblings_parent`, `execute_lastsibling`
(an empty NON EMPTY axis still has the `HierarchyInfo` of its set type), `execute_lag_null_member`,
`execute_ancestors_distance`.

Operators and existence: `IN`, `MATCHES` (`InUdf`, `MatchesUdf`, Java regular expressions), `IS`, `IS EMPTY`,
`IS NULL`, `Existing` and `Exists` (`FunUtil.existsInTuple`, with the compound slicer placeholder). Cases
`execute_in_ancestor`, `execute_not_in_udf`, `execute_is_member`, `execute_is_empty_tail`, `execute_matches_caption`,
`execute_existing_exists_count`, `execute_existing_compound_slicer`, `execute_existing_generate_topcount`.

The remaining functions: `VisualTotals` (`execute_visualtotals_pattern`, `execute_visualtotals_all_member`,
`execute_visualtotals_drilldownlevel`), `CurrentDateMember` with a fixed date (`execute_currentdatemember_exact`,
`execute_currentdatemember_after`; the statements with today's date are compared by `compare-applicable.py` only),
`Parameter` (`execute_parameter_set`, `execute_parameter_member`), `CalculatedChild` and `AddCalculatedMembers`
(`execute_calculatedchild`, `execute_addcalculatedmembers_item`), `execute_coalesceempty`, `execute_case_cint_recursive`,
`execute_mod_currentordinal`, `execute_format_generate`, `execute_properties_generate`. The result limit has a unit test
only: eMondrian runs without one.

The native crossjoin: `execute_native_crossjoin_order` (#155: hierarchy order, not the order of the set),
`execute_native_crossjoin_multi_variant` (#144: an operand split by level), `execute_native_crossjoin_slicer` (#241:
customers × product names under a slicer, 67 of 16 million combinations; also the format of a value below 1).

Drillthrough (`execute_drillthrough_*`, captured with `-p Format=Tabular` as Excel sends it): Excel's statement shape
(`execute_drillthrough_excel`, `DRILLTHROUGH MAXROWS 1000 SELECT FROM [cube] WHERE (((measure, ...), ...))`), a slicer,
axes, the first cell after `NON EMPTY`, a compound slicer, a subselect, `RETURN` (a level gives its key column before
its name column), `FIRSTROWSET` (skips that many of the `MAXROWS` rows), no `MAXROWS`, an empty cell (the schema without
rows), a trivial calculated member (replaced by its member), a calculated measure (the cube's first measure is read),
attribute hierarchies, the Weekly hierarchy, two members that constrain the same column differently (the column is then
not constrained at all, as `CellRequest.addConstrainedColumn` leaves an unsatisfiable drill-through request) and the
format fault of a request that is not Tabular. What the captures show of eMondrian: the columns are the star's, in the
order its levels register them (per dimension the user hierarchies' levels, then the attribute hierarchies'), each
named by the first level that uses its column (`Product Id`, but `Name (Key)` for the customer key), duplicates with
`_0`, `_1`; the rows are ordered by all columns but the measure; no total-count row (`EnableTotalCount` is off). A
non-trivial calculated member fails in eMondrian with a Java NullPointerException text
(`execute_drillthrough_calc_member`, faultstring and description ignored); ours says
`Cannot do DrillThrough operation on the cell` with the same fault code. Not ported: the schema's `DrillThroughAction`s
(FoodmartBW.xml has none), virtual cubes, `Format` property values other than the exact `Tabular`.

## Error cases (faults)

Clients depend on the exact faults, so they are test cases too. `python scripts/capture-error-cases.py` takes the bad
requests of Mondrian's `XmlaErrorTest` (junk, bad XML, bad SOAP envelope, bad header, bad body: 24 cases `error_*`), replays
them against eMondrian and stores request, answer and HTTP status; four more cases were made by hand
(`error_unknown_request_type`, `error_unknown_restriction`, `error_unknown_database_discover`, `error_csdl_metadata`).
`scripts/xmla_test.py` compares status and body. What the cases show about Mondrian:

- Every fault is sent with **HTTP status 200** and a SOAP fault body: `faultcode` = `SOAP-ENV:<Client|Server|MustUnderstand>.<code>`,
  `faultstring` = fixed text of the code + blank + description, `faultactor` Mondrian, `detail/Error` with `ErrorCode`
  (3238658121; 3238789130 for the unparse stage) and `Description` = "The Mondrian XML: " + description.
- Checks and codes, in order: XML not parseable / not a SOAP envelope / more than one Header / not one Body: `Client.00USMC02`
  "DOM parse errors occur"; unknown mustUnderstand header: `MustUnderstand.00HSHA01`; not exactly one Discover or Execute:
  `Client.00HSBA01`; wrong number of RequestType `00HSBB04`, Restrictions `00HSBB05`, Properties `00HSBB06`, Command (or its
  children) `00HSBB07`, RestrictionList `00HSBB08`, PropertyList `00HSBB09`; request type not a rowset: `Server.00HSBB01`
  "No enum constant mondrian.xmla.RowsetDefinition.X"; restriction that is no column of the rowset: `Server.00HSBB01`
  "Rowset 'X' does not contain column 'Y'"; unknown DataSourceInfo / Catalog property: `Server.00HSBE02` "Unknown database / catalog".
- The parser message of the XML library (junk, mismatched tags) differs by library; those two cases ignore faultstring and
  Description (`ignore.txt`). `DISCOVER_CSDL_METADATA` fails in eMondrian with a licence error of a module it does not ship
  (`00UE001.Internal Error`); the same text is returned.
- The data source of both systems is named `ABAP BW` (their datasources.xml, `reference/schema/datasources.xml` and
  `datasources-sap.xml`); requests with another DataSourceInfo are faults.
- Not covered: the authorization cases (`testAuth*`), session headers (BeginSession etc. are accepted and ignored), faults of Execute.

## MDSCHEMA_MEMBERS

`reference/members_*` (25 cases) cover hierarchies of different kinds (with the empty member, numeric, boolean text, key
hierarchy, measures, Date), the restrictions LEVEL_UNIQUE_NAME, LEVEL_NUMBER, DIMENSION_UNIQUE_NAME, MEMBER_NAME,
MEMBER_UNIQUE_NAME, each tree operation and combinations, and unknown members. `members_all` is the unrestricted answer
(27,813 rows, 24 MB): it is too big to keep, so only the number of rows is stored (`rows.txt`); a one-off comparison of
all 27,813 rows with eMondrian (every column, in order) found no difference. New cases are captured with
`python scripts/capture-case.py <name> <REQUEST_TYPE> -r NAME=VALUE ... [--count-only]`.

What Mondrian does, as implemented: a hierarchy is listed level by level (`populateHierarchy`), each level in hierarchy
order, and the rows are then sorted stably by dimension, hierarchy, level unique name and level number (the rowset's
sort columns), so `[Store].[Store City]` comes before `[Store].[Store Country]`; member name = value of the level's
name column (numbers without leading zeros), unique name the hierarchy's and the names of the ancestors' and the
member's (`[Store].[USA].[CA]`); MEMBER_ORDINAL is always 0; types 2 (All), 1 (regular), 3 (measure); PARENT_LEVEL is
the depth minus one. A tree operation (TREE_OP: 1 children, 2 siblings, 4 parent, 8 self, 16 descendants, 32
ancestors, added) is relative to MEMBER_UNIQUE_NAME (`populateMember`: self, siblings, descendants or children,
ancestors or parent); TREE_OP without a member is ignored. A MEMBER_TYPE restriction gives no rows (as Mondrian does),
MEMBER_CAPTION is ignored. The members of a hierarchy are read from its dimension view (`SELECT DISTINCT` of the level
columns, ordered by the keys), only for the hierarchies the request selects.
