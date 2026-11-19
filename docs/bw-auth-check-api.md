# The check of BW's analysis authorisations: API

olap4abap answers whether a user may see a selection of an InfoProvider by BW's analysis authorisations, at a key
date, the way BW's MDX on InfoProviders answers it, without reading any data. There are two ways in:

| | ABAP: `ZZXXMLA1_IF_BW_AUTH_CHECK` | HTTP: `POST /zzxxmla1/bw/check` |
|---|---|---|
| The selection | members per characteristic, no MDX | a statement of BW's MDX |
| The user | any user | the caller or a test user of the scenarios |
| The answer | `ty_answer`: status, reason, message, a refused combination, refused members, holes | JSON: status, reason, message, the selection checked, the statement resolved, optionally the SQL |

Both run the same check (`ZZXXMLA1_CL_BW_AUTH_SQL`): one SQL statement per InfoProvider, compiled once, that
gives every requested member the set of authorisations that admit it; ABAP then decides whether the authorisations
together cover every combination. How it works and why is in `next-steps.md` (Now: analysis authorisations, The
check for other callers; The selection as a product per characteristic). The rules it follows are BW's, as
`mvp-scope.md` (Authorisation decision) records them.

## What is checked

- **The selection is a product.** Every combination of one requested member of each characteristic must be
  authorised, as BW's MDX checks a query: a request for doctors `009`, `012` and diagnoses `I10`, `J45` asks four
  combinations, not two pairs. A question that is not one product (a list of unrelated tuples) is one call per
  product.
- **Each authorisation is a sub-cube:** its characteristics combine with AND; several authorisations combine with
  OR. A combination is authorised when one authorisation admits all its members. Two authorisations that each
  cover half of the request together cover it.
- **Only the authorisations that apply to the InfoProvider count:** those that admit the provider (`0TCAIPROV`),
  display (`0TCAACTVT`) and the key date (`0TCAVALID`), with a line for every authorisation-relevant characteristic
  of the provider.
- **Hierarchy authorisations** are read on the slice of the hierarchy valid at the key date, matched by
  hierarchy name and version, a node by name and InfoObject (never by `HIEID`).
- **Not supported:** variables in authorisations (a user with one is not authorised), authorisation-relevant
  navigation attributes and key figure authorisations (`0TCAKYFNM`). Planned: a user whose profile restricts key
  figures or a navigation attribute of the provider gets `ERROR`, reason `KEY_FIGURES` or `NAVIGATION_ATTRIBUTE`
  (`mvp-scope.md`, Authorisation decision).
- **No data is read** and nothing is written, except that the first check on a characteristic with BW hierarchies
  can create olap4abap's copy tables of them (see the LUW note below).

## ABAP: `ZZXXMLA1_IF_BW_AUTH_CHECK`

### Getting a check

```abap
TRY.
    DATA(auth) = zzxxmla1_cl_bw_auth_check=>for( user     = 'ZZXXMLA1_A21'
                                                  provider = 'ZCLVISITA'    " InfoCube or aDSO, BW's name
                                                  key_date = '20250615' ).  " default 99991231
  CATCH zzxxmla1_cx_bw_auth_check INTO DATA(error).
    " the provider does not exist, or more than 63 authorisations of the user apply to it
ENDTRY.
```

`for` reads the user's profile for the provider once; every `check` on the returned object costs only its own
statement, so keep the object for several questions about the same user, provider and key date.

**It checks no authority of the caller.** Any user can be asked about; who may ask about whom is the calling
program's responsibility.

**Do not call `for` inside your own update LUW.** Reading the profile can create the copy tables of a
characteristic's BW hierarchies (a DDIC activation, which commits) and refill a copy. `check` only reads.

### Other methods

- `characteristics( )`: the provider's authorisation-relevant characteristics. A request must name every one of
  them.
- `applying( )`: the user's authorisations that apply to the provider (`RSAUTH` names).

### The request

`check( request )` takes a flat table of `ty_member`; the members are grouped by characteristic and the product of
the groups is checked.

| Field | Meaning |
|---|---|
| `characteristic` | the InfoObject, `ZCLDOC` |
| `kind` | `V` a value, `N` a hierarchy node, `A` the aggregate (`c_kind`) |
| `value` | a value's key as BW holds it (NUMC with its zeros); `#` or blank for the not-assigned value; a node's name; `:` or blank for the aggregate |
| `hierarchy`, `version` | for a leaf or node: the BW hierarchy it is asked in (`ZCLDOC_ORG`, `001`; version blank for a hierarchy without versions); blank for a flat value |
| `node_iobjnm` | for a node: its InfoObject, `0HIER_NODE` for a text node, the characteristic itself for a postable node, an external characteristic such as `ZCLSITE` |

The four kinds of member:

```abap
( characteristic = 'ZCLDOC'  kind = 'V' value = '009' )                                    " a flat value
( characteristic = 'ZCLDOC'  kind = 'V' value = '009' hierarchy = 'ZCLDOC_ORG' version = '001' )  " a leaf
( characteristic = 'ZCLDOC'  kind = 'N' value = 'GP'  hierarchy = 'ZCLDOC_ORG' version = '001'
  node_iobjnm = '0HIER_NODE' )                                                            " a node
( characteristic = 'ZCLDIAG' kind = 'A' )                                                 " the aggregate
```

Rules:

- **Name every authorisation-relevant characteristic.** Where you want totals over a characteristic, ask its
  aggregate (`kind = 'A'`, BW's `:`); nothing is aggregated silently. A missing one is an `ERROR` with reason
  `MISSING`.
- A flat value is checked against the authorisations' flat values; a leaf or node against their hierarchy lines.
  The same key as a flat value and as a leaf can get different answers (BW's rule).
- Members are named, never an occurrence: a node under two parents or a duplicate leaf is one member.
- A characteristic that is not authorisation relevant may be in the request; it is not checked.
- A characteristic the provider does not have raises `ZZXXMLA1_CX_BW_AUTH_CHECK`.

### The answer

`check` returns `ty_answer`:

| Field | Meaning |
|---|---|
| `status` | `ALLOWED`, `NO AUTH`, `UNKNOWN` or `ERROR` (`c_status`) |
| `reason` | BW's reason of a refusal: `PROVIDER`, `VARIABLE`, `VALIDITY`, `NO VALUES`, `VALUE`, `HIERARCHY`, `NODE`, `COMBINATION`; or an error's (below) |
| `message` | BW's message for the reason, or the error's text |
| `combination` | one refused combination, a member per characteristic |
| `refused` | the members no applying authorisation admits at all, each with its own status, reason and message, in the order BW meets them walking the product (the last characteristic fastest) |
| `holes` | the parts of the product of the admitted members that no authorisation covers, each a sub-product (a table of members, grouped by characteristic); at most `c_max_holes` (100) |
| `more_holes` | there are more holes than listed |

How the status is chosen:

- `ALLOWED`: every combination is authorised (also for a user whose authorisations do not restrict the provider,
  such as `0BI_ALL`).
- A member no authorisation admits decides it: `UNKNOWN` for a value no authorisation names, `NO AUTH` otherwise.
  The first refused member counts, a value or node before an aggregate (BW checks the aggregates last).
- Otherwise a hole decides it: `NO AUTH` with reason `COMBINATION`; `combination` is a member of each class of the
  first hole.
- `ERROR` where the request cannot be checked (`c_error`):
  - `REQUEST`: a member is not well formed (a kind other than `V`, `N`, `A`; a node without its name, hierarchy or
    InfoObject);
  - `MISSING`: an authorisation-relevant characteristic is not asked;
  - `NO SLICE`: a hierarchy has no slice valid at the key date;
  - `NO MEMBER`: a node, leaf or value the provider does not have at the key date.

### Example

User `ZZXXMLA1_A21` (scenario CROSS) may see doctor `009` with diagnosis `I10` and doctor `012` with `J45`, by two
authorisations. Asking both doctors with both diagnoses is refused, because two of the four combinations are in
neither:

```abap
DATA(answer) = auth->check( VALUE #(
  ( characteristic = 'ZCLDOC'  kind = 'V' value = '009' )
  ( characteristic = 'ZCLDOC'  kind = 'V' value = '012' )
  ( characteristic = 'ZCLDIAG' kind = 'V' value = 'I10' )
  ( characteristic = 'ZCLDIAG' kind = 'V' value = 'J45' ) ) ).
" answer-status = 'NO AUTH', answer-reason = 'COMBINATION'
" answer-holes: {009} x {J45} and {012} x {I10}
```

Each member alone is admitted, so `refused` is empty; the holes say which parts to drop.

### Limits

- At most 63 applying authorisations per user and provider (`c_max_auths`, a bit each in a `BIGINT`): more raise
  `ZZXXMLA1_CX_BW_AUTH_CHECK` in `for`.
- The size of the request does not limit the check: members with the same set of admitting authorisations are one
  class, and the cover is searched over the classes, never over the product.

## HTTP: `POST /zzxxmla1/bw/check`

For a statement in BW's MDX (`ZZXXMLA1_CL_BW_MDX_API`): the endpoint resolves it in BW's names, evaluates its
slicer, axes and subselects without cells, and checks the members they show (the product per characteristic, as
above) plus every member the statement names on its own (the node of a `Children`).

```
POST /zzxxmla1/bw/check?user=ZZXXMLA1_A21&keyDate=2025-06-15&sap-client=001
Content-Type: text/plain; charset=utf-8

SELECT {[Measures].[ZCLVISNO]} ON COLUMNS,
  {([ZCLDOC].[009], [ZCLDIAG].[I10]), ([ZCLDOC].[012], [ZCLDIAG].[J45])} ON ROWS
FROM [$ZCLVISITA]
```

Parameters:

- `user`: the user checked; the caller (default) or a test user of the scenarios (`ZZXXMLA1_CL_BW_AUTH_GEN`),
  else 403. Checking other users waits for an authorisation object of olap4abap's (`next-steps.md`, The check for
  other callers, point 1, not decided).
- `keyDate`: `YYYY-MM-DD`, default 9999-12-31; the BW hierarchies are the slices valid then.
- `sql=true`: the answer lists the SQL statements the check ran.

The body is the statement, plain or as an XMLA `Execute`. The answer:

```json
{"user": "ZZXXMLA1_A21", "keyDate": "2025-06-15",
 "status": "NO AUTH", "reason": "COMBINATION", "message": "<BW's message>",
 "statement": "<the statement sent>", "resolved": "<the statement in olap4abap's names>",
 "selection": {"factors": [{"name": "Axis1", "count": 2, "tuples": [["ZCLDOC '009'", "ZCLDIAG 'I10'"], ...]}],
               "named": [...]},
 "sql": [{"sql": "...", "rows": 1, "microseconds": 0, "error": "", "phase": "Authorisation"}]}
```

`status` is `OK`, `EMPTY` (allowed, but an axis has no tuple), `NO AUTH`, `UNKNOWN` or `ERROR` (the message says
why: a syntax error, an unknown member, a fault of the check). The members of a BW hierarchy are those the user
may see, as BW shows them; asking a hierarchy's members as a whole where the user sees only part of it is refused
as BW refuses it.

`POST /zzxxmla1/bw/checks` takes a JSON array of statements for one user and key date and answers
`{"user", "keyDate", "results": [...]}`, a result per statement as above; the profile is read once per provider. A
single check is traced like an XMLA call (method `CHECK` on the trace page, "Open in MDX Console"); a batch is not.
The MDX console's mode "BW's MDX" sends to `bw/check`.

## How it is tested

Against BW's own answers, recorded per test user and key date in `reference/auth/` by the probe (BW's "Execute as
Other User"; `clinic-demo.md`, Authorization scenarios):

- `python scripts/bw_auth_compare.py`: every recorded statement through `bw/checks`;
- `python scripts/auth_check_test.py --engine api`: the recorded queries whose selection is a product, through the
  ABAP API (`GET /zzxxmla1/schema/api/auth/check?...&engine=api`); `--engine sql` the same check without the API.

Unit tests: `ZZXXMLA1_CL_BW_AUTH_CHECK` (the cover on made-up masks, the errors) and `ZZXXMLA1_CL_BW_AUTH_SQL`.
