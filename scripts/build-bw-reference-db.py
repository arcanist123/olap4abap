#!/usr/bin/env python3
"""Copies the BW tables of the cubes ZFMSALES and ZCLVISIT, as BW holds them, and the copy of the BW hierarchy
ZCLDIAG_ICD into the reference database of the eMondrian container.

Why: the reference schema (reference/schema/FoodmartBW.xml) names the BW tables themselves (/BIC/FZFMSALES,
/BIC/SZFMSTORE, /BIC/PZFMSTORE, ...), so that the same schema runs in eMondrian and in SAP (docs/mvp-scope.md, schema
decision). The reference database therefore needs tables of these names with BW's contents: the fact table and the SID
and attribute tables of the characteristics of the cube, with BW's columns and values (NUMC zero-padded, blank
instead of NULL, SIDs equal to the FoodMart ids).

The clinic InfoCube ZCLVISIT (docs/clinic-demo.md) is the reference scenario for BW hierarchies (docs/next-steps.md,
Reference scenario): its hierarchy ZCLDIAG_ICD, in which every node occurs once and every leaf is a value at the same
depth, is served by the reference as a balanced level hierarchy (Level 01 to Level 04) on a flattened table
(reference/schema/ClinicBW.xml, catalog ZCLVISIT).

1. Export (skipped with --no-export): the SQL of the generated views of the cubes' characteristics
   (ZZXXMLA1_CL_BW_VIEW_GEN, the plain views of table ZZXXMLA1_VIEW, the ones the accepted schemas name) from HANA's
   SYS.VIEWS, read with hdbsql in the SAP container (HANA_CONTAINER, HANA_OS_USER, HANA_KEY; defaults a4h, a4hadm,
   DEFAULT), into data/foodmart-bw/bw/views.json, keyed by the placeholder of the view (ZZXXMLA1_C_<characteristic>),
   the name the reference schemas give it: SAP's number (ZZXXMLA1V...) depends on the views the system has besides
   these (scripts/sap-files.py deploy puts it in the schema on SAP). HSQLDB takes HANA's view SQL as it is, so the
   reference has exactly SAP's views. Then the tables: the fact tables, the SID and attribute tables of the
   characteristics and every other table the views read (the text tables of the clinic), their columns from DD03L
   and their rows read with `sapcli datapreview osql` (logon data from .env.sap), into
   data/foodmart-bw/bw/<table>.json (git-ignored), listed in tables.json. Then per hierarchy of HIERARCHIES the copy
   of ZZXXMLA1_CL_BW_HIERARCHY_COPY at BW's current version (the row of RSRHIEDIR_OLAP without DELETETIMESTMP, as
   the copy finds it; run program ZZXXMLA1_HIERARCHY_COPY first if the copy is older): the rows of its node table
   (ZZXXMLA1H...) for that HIESID and SVER, into hierarchy_<name>.json.
2. Build: adds the tables to data/foodmart-bw/hsqldb-foodmart.jar (the FoodMart data with the empty members, see
   scripts/add-empty-members.py): CREATE MEMORY TABLE after the last CREATE of foodmart.script, the rows at its end.
   Per hierarchy its flattened table (hierarchy_levels), computed from the copy: ZZXXMLA1_HL_<hierarchy>, a row per
   value SID (the fact's SID_<characteristic>, the key) with its member on each level, L01_SID, L01_NAME, L01_POS to
   the level of the values: the node's SID, its NAME (a text node's technical name, a value's key from the SID table,
   '' for the initial value, as the characteristic's members are named), its CAPTION (a text node's technical name
   until the node texts come, a value's medium text in English from the text table, '' without one, as the
   characteristic's members are captioned) and its position among its siblings (BW's order). The virtual
   root is the All member. The build fails unless the tree is balanced, its leaves values at the same depth, every
   node once, no value with children and every value of the characteristic a leaf (docs/next-steps.md, Reference
   scenario: the reference serves BW hierarchies with a level form as level hierarchies, every value assigned and the
   not-assigned node suppressed, so that REST_H is no part of it). The copy's own
   tables are not loaded. Then the characteristic views under their placeholder names, after the tables. Lines of an
   earlier run (they name /BIC/ or ZZXXMLA1 objects) are removed first, so the script can run again.
   Column types: NUMC, CHAR, LANG and DATS are VARCHAR of their length (HANA: NVARCHAR), INT4 is INTEGER, DEC is
   DECIMAL; a negative number comes from the data preview with its sign at the end (37-). Primary keys as in BW
   (none for the fact table, whose package key is not unique, and none for a view), a unique index on SID of the SID
   tables and an index per SID column of the fact table (HSQLDB joins without them are slow).

Then: scripts/deploy-reference-schema.sh (installs jar and schemas in the container).

Usage: python scripts/build-bw-reference-db.py [--no-export]
"""
import argparse
import json
import os
import pathlib
import re
import subprocess
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
JAR = ROOT / "data" / "foodmart-bw" / "hsqldb-foodmart.jar"
EXPORT = ROOT / "data" / "foodmart-bw" / "bw"
SCRIPT = "hsqldb-foodmart/foodmart.script"
# the cubes and their characteristics; DD03L is read per cube with the LIKE pattern of its tables
CUBES = {
    "ZFMSALES": (["ZFMPROD", "ZFMCUST", "ZFMSTORE", "ZFMPROMO", "ZFMDATE"], "/BIC/_ZFM%"),
    "ZCLVISIT": (["ZCLPAT", "ZCLDOC", "ZCLDIAG", "ZCLVTYPE", "ZCLDATE", "ZCLSITE", "ZCLROOM", "ZCLFISCVR",
                  "ZCLFISCYR", "ZCLFISCPR", "ZCLSERV"], "/BIC/_ZCL%"),
}
# the BW hierarchies the reference serves as level hierarchies: hierarchy -> characteristic; only balanced
# hierarchies in which every node occurs once, every value is a leaf and the not-assigned node is suppressed
# (docs/next-steps.md, Reference scenario)
HIERARCHIES = {"ZCLDIAG_ICD": "ZCLDIAG"}
CR, NL = "\r", "\n"
PLACEHOLDER = "ZZXXMLA1_C_"  # + characteristic: the reference schema's name of its view (ZZXXMLA1_CL_BW_VIEW_GEN)
LEVELS = "ZZXXMLA1_HL_"  # + hierarchy: the flattened table of a hierarchy
OBJECT = re.compile(r'"(/BIC/|ZZXXMLA1)')  # a line of an earlier run names one of these
CHUNK = 5000  # characters of a view's SQL per hdbsql query


def sapcli(statement, rows):
    env = dict(os.environ)
    env_file = ROOT / ".env.sap"
    for line in env_file.read_text(encoding="utf-8").splitlines():
        if "=" in line and not line.lstrip().startswith("#"):
            key, value = line.split("=", 1)
            env[key.strip()] = value.strip()
    command = ["sapcli", "--ashost", env["SAP_ASHOST"], "--client", env["SAP_CLIENT"], "--user", env["SAP_USER"]]
    if env.get("SAP_PORT"):
        command += ["--port", env["SAP_PORT"]]
    if env.get("SAP_USE_SSL", "false") != "true":
        command += ["--no-ssl"]
    command += ["datapreview", "osql", "--output", "json", "--rows", str(rows), statement]
    result = subprocess.run(command, env=env, capture_output=True, check=True)
    return json.loads(result.stdout.decode("utf-8"))


def table_file(table):
    return EXPORT / (table.replace("/", "_").strip("_") + ".json")


def ddic_fields(rows):
    return [dict(name=c["FIELDNAME"], key=c["KEYFLAG"] == "X", type=c["DATATYPE"], length=int(c["LENG"]),
                 decimals=int(c["DECIMALS"])) for c in rows if c["DATATYPE"] and not c["FIELDNAME"].startswith(".")]


DD03L = "SELECT tabname, position, fieldname, keyflag, datatype, leng, decimals FROM dd03l WHERE as4local = 'A' AND "


def export():
    EXPORT.mkdir(parents=True, exist_ok=True)
    read_by_views = export_views()
    tables = sorted({table for cube, (characteristics, _) in CUBES.items()
                     for table in [f"/BIC/F{cube}"] + [f"/BIC/{t}{c}" for c in characteristics for t in "SP"]}
                    | read_by_views)
    columns = {}
    for _, pattern in CUBES.values():
        for c in sapcli(DD03L + f"tabname LIKE '{pattern}' ORDER BY tabname ASCENDING, position ASCENDING", 100000):
            columns.setdefault(c["TABNAME"], []).append(c)
    for table in tables:
        fields = ddic_fields(columns.get(table, []))
        assert fields, f"{table}: no columns in DD03L (not covered by the LIKE patterns of CUBES?)"
        # one statement per table: the data preview rejects longer statements
        rows = sapcli(f"SELECT * FROM {table}", 1000000)
        data = dict(table=table, fields=fields, rows=[[r[f["name"]] for f in fields] for r in rows])
        table_file(table).write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
        print(f"exported {table}: {len(rows)} rows")
    (EXPORT / "tables.json").write_text(json.dumps(tables, indent=1), encoding="utf-8")
    for hierarchy, characteristic in HIERARCHIES.items():
        export_hierarchy(hierarchy, characteristic)


def export_hierarchy(hierarchy, characteristic):
    """The copy of the hierarchy at BW's current version: the directory row and the rows of the node table for its
    HIESID and SVER."""
    registry = sapcli(f"SELECT node_table FROM zzxxmla1_hietab WHERE iobjnm = '{characteristic}'", 10)
    assert len(registry) == 1, f"{characteristic} has no copy tables: run program ZZXXMLA1_HIERARCHY_COPY"
    copies = sapcli("SELECT hieid, hiesid, sver, timestmp, root_sid, norestnodes FROM zzxxmla1_hiedir "
                    f"WHERE iobjnm = '{characteristic}' AND hienm = '{hierarchy}'", 1000)
    assert copies, f"{hierarchy} has no copy: run program ZZXXMLA1_HIERARCHY_COPY"
    # BW's current version, as ZZXXMLA1_CL_BW_HIERARCHY_COPY finds it
    current = sapcli("SELECT hiesid, sver, timestmp FROM rsrhiedir_olap "
                     f"WHERE hieid = '{copies[0]['HIEID']}' AND objvers = 'A' AND deletetimestmp = 0", 10)
    assert len(current) == 1, f"{hierarchy}: {len(current)} current rows in RSRHIEDIR_OLAP"
    key = (number(current[0]["HIESID"]), current[0]["SVER"], number(current[0]["TIMESTMP"]))
    copy = [c for c in copies if (number(c["HIESID"]), c["SVER"], number(c["TIMESTMP"])) == key]
    assert copy, f"{hierarchy}: no copy of BW's current version {key}: run program ZZXXMLA1_HIERARCHY_COPY"
    copy = copy[0]
    assert copy["NORESTNODES"].strip(), f"{hierarchy} shows the not-assigned node: not a reference case"
    hiesid, sver = key[0], key[1]
    data = dict(hierarchy=hierarchy, characteristic=characteristic, hiesid=hiesid, sver=sver, timestmp=key[2],
                root_sid=number(copy["ROOT_SID"]))
    for part, table in (("nodes", registry[0]["NODE_TABLE"]),):
        fields = ddic_fields(sapcli(DD03L + f"tabname = '{table}' ORDER BY position ASCENDING", 1000))
        assert fields, table
        rows = sapcli(f"SELECT * FROM {table} WHERE hiesid = {hiesid} AND sver = '{sver}'", 1000000)
        data[part] = dict(table=table, fields=fields, rows=[[r[f["name"]] for f in fields] for r in rows])
        print(f"exported {table} of {hierarchy} (HIESID {hiesid}, SVER {sver}): {len(rows)} rows")
    (EXPORT / f"hierarchy_{hierarchy}.json").write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")


def number(value):
    """A number as the data preview writes it: blanks around it, a negative one with its sign at the end (37-)."""
    value = value.strip()
    return "-" + value[:-1] if value.endswith("-") else value


def hdbsql(statement):
    """Rows of a HANA query, run with hdbsql as the ABAP system's database user; values separated by |."""
    container = os.environ.get("HANA_CONTAINER", "a4h")
    os_user = os.environ.get("HANA_OS_USER", "a4hadm")
    key = os.environ.get("HANA_KEY", "DEFAULT")
    command = f'hdbsql -U {key} -x -a -j -F "|" "{statement}"'
    result = subprocess.run(["docker", "exec", container, "su", "-", os_user, "-c", command],
                            capture_output=True, check=True)
    rows = []
    for line in result.stdout.decode("utf-8").splitlines():
        if line.strip():
            rows.append([unquote(v) for v in line.strip().strip("|").split("|")])
    return rows


def unquote(value):
    """A value as hdbsql writes it: strings in double quotes, inner quotes and backslashes escaped."""
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] == '"':
        value = value[1:-1].replace('\\"', '"').replace("\\\\", "\\")
    return value


def export_views():
    """The SQL of the plain views of the cubes' characteristics, read from HANA in chunks (hdbsql cuts LOB values
    short), keyed by their placeholders; returns the tables they read."""
    registered = {row["OBJECT_NAME"].strip(): row["VIEW_NAME"].strip()
                  for row in sapcli("SELECT object_name, view_name, selection FROM zzxxmla1_view WHERE kind = 'C'", 10000)
                  if not row["SELECTION"].strip()}
    views, read = {}, set()
    for characteristic in [c for characteristics, _ in CUBES.values() for c in characteristics]:
        name = registered.get(characteristic)
        assert name, f"no view of {characteristic} (run ZZXXMLA1_CL_BW_VIEW_GEN or scripts/sap-files.py deploy)"
        length = hdbsql("SELECT LENGTH(DEFINITION) FROM SYS.VIEWS "
                        f"WHERE SCHEMA_NAME = CURRENT_SCHEMA AND VIEW_NAME = '{name}'")[0][0]
        parts = []
        for start in range(1, int(length) + 1, CHUNK):
            parts += hdbsql(f"SELECT TO_NVARCHAR(SUBSTRING(DEFINITION, {start}, {CHUNK})) FROM SYS.VIEWS "
                            f"WHERE SCHEMA_NAME = CURRENT_SCHEMA AND VIEW_NAME = '{name}'")[0]
        definition = "".join(parts)
        assert len(definition) == int(length), name
        tables = set(re.findall(r'(?:FROM|JOIN)\s+"([^"]+)"', definition))
        assert tables and all(t.startswith("/BIC/") for t in tables), (name, tables)  # a view over BW tables only
        read |= tables
        views[PLACEHOLDER + characteristic] = definition
        print(f"exported {name} as {PLACEHOLDER + characteristic}")
    (EXPORT / "views.json").write_text(json.dumps(views, indent=1), encoding="utf-8")
    return read


def sql_type(field):
    if field["type"] in ("NUMC", "CHAR", "LANG", "DATS"):
        return f'VARCHAR({field["length"]})'
    if field["type"] == "INT4":
        return "INTEGER"
    if field["type"] == "DEC":
        return f'DECIMAL({field["length"]},{field["decimals"]})'
    raise ValueError(field)


def literal(field, value):
    if field["type"] in ("INT4", "DEC"):
        value = number(value)
        float(value)
        return value
    assert all(ord(ch) < 128 for ch in value), value  # the script is read as ISO-8859-1 with \\u escapes
    return "'" + value.replace("'", "''") + "'"


def statements(data):
    table, fields = data["table"], data["fields"]
    columns = ",".join(f'"{f["name"]}" {sql_type(f)} NOT NULL' for f in fields)
    keys = ",".join(f'"{f["name"]}"' for f in fields if f["key"])
    # the fact table of a HANA-optimised cube has no unique key (DD03L flags only the package dimension)
    primary_key = "" if table.startswith("/BIC/F") or not keys else f",PRIMARY KEY({keys})"
    create = [f'CREATE MEMORY TABLE PUBLIC."{table}"({columns}{primary_key})']
    if table.startswith("/BIC/S") and not any(f["name"] == "SID" and f["key"] for f in fields):
        index = "I_" + table.replace("/", "_").strip("_") + "_SID"
        create.append(f'CREATE UNIQUE INDEX {index} ON PUBLIC."{table}"("SID")')
    if table.startswith("/BIC/F"):
        for f in fields:
            if f["name"].startswith("SID_"):
                create.append(f'CREATE INDEX I_{table.replace("/", "_").strip("_")}_{f["name"]} '
                              f'ON PUBLIC."{table}"("{f["name"]}")')
    inserts = [f'INSERT INTO "{table}" VALUES(' + ",".join(literal(f, v) for f, v in zip(fields, row)) + ")"
               for row in data["rows"]]
    return create, inserts


def hierarchy_levels(data):
    """The flattened table of a hierarchy: a row per value SID with its member on each level (SID, name, caption and
    position among its siblings). Fails unless the tree is balanced with every value of the characteristic a leaf, so that it
    is a level hierarchy."""
    h, c = data["hierarchy"], data["characteristic"]
    root = int(data["root_sid"])
    fields = [f["name"] for f in data["nodes"]["fields"]]
    sid_table = json.loads(table_file(f"/BIC/S{c}").read_text(encoding="utf-8"))
    sid_fields = [f["name"] for f in sid_table["fields"]]
    # a leaf is named as the characteristic's member: by its key, the initial value '' (docs/next-steps.md, Now:
    # texts and captions)
    keys = {int(number(row[sid_fields.index("SID")])): row[sid_fields.index(f"/BIC/{c}")]
            for row in sid_table["rows"]}
    # and captioned by its medium text, '' without one (the view's TXTMD)
    text_table = json.loads(table_file(f"/BIC/T{c}").read_text(encoding="utf-8"))
    text_fields = [f["name"] for f in text_table["fields"]]
    texts = {row[text_fields.index(f"/BIC/{c}")]: row[text_fields.index("TXTMD")] for row in text_table["rows"]
             if row[text_fields.index("LANGU")] == "E"}
    nodes, children = {}, {}
    for row in data["nodes"]["rows"]:
        node = {f: row[i] for i, f in enumerate(fields)}
        sid, parent = int(number(node["SID"])), int(number(node["PARENT_SID"]))
        if parent == 0:  # the virtual root, the All member
            assert sid == root, (h, sid)
            continue
        assert sid not in nodes, f"{h}: {sid} occurs twice, not a level hierarchy"
        text_node = bool(node["NODE_IOBJ"].strip())
        name = node["NODE_NAME"] if text_node else keys[sid]
        caption = node["NODE_NAME"] if text_node else texts.get(keys[sid], "")
        nodes[sid] = dict(parent=parent, depth=int(number(node["DEPTH"])), pos=int(number(node["POS"])), name=name,
                          caption=caption)
        children.setdefault(parent, []).append(sid)
    rank = {}
    for siblings in children.values():
        for n, sid in enumerate(sorted(siblings, key=lambda s: nodes[s]["pos"]), 1):  # BW's order
            rank[sid] = n
    for sid, node in nodes.items():
        expected = 1 if node["parent"] == root else nodes[node["parent"]]["depth"] + 1
        assert node["depth"] == expected, f"{h}: {node['name']} at depth {node['depth']}, expected {expected}"
    leaves = [sid for sid in nodes if sid not in children]
    depth = max(nodes[sid]["depth"] for sid in leaves)
    for sid in leaves:
        assert nodes[sid]["depth"] == depth, f"{h}: leaf {nodes[sid]['name']} at depth {nodes[sid]['depth']}, " \
                                             f"not {depth}: not a level hierarchy"
        assert sid >= 0, f"{h}: text node {nodes[sid]['name']} is a leaf"
    assert all(sid < 0 for sid in children if sid != root), f"{h}: a value with children (postable node)"
    rows = []
    for sid in sorted(leaves, key=lambda s: nodes[s]["pos"]):
        path = [sid]
        while nodes[path[0]]["parent"] != root:
            path.insert(0, nodes[path[0]]["parent"])
        rows.append([sid] + [v for s in path for v in (s, nodes[s]["name"], nodes[s]["caption"], rank[s])])
    assert sorted(row[0] for row in rows) == sorted(keys), f"{h}: values of {c} not leaves or twice"
    name_length = max(len(row[i]) for row in rows for i in range(2, len(row), 4))
    caption_length = max(len(row[i]) for row in rows for i in range(3, len(row), 4))
    level_fields = [dict(name="SID", key=True, type="INT4", length=10, decimals=0)]
    for level in range(1, depth + 1):
        level_fields += [dict(name=f"L{level:02}_SID", key=False, type="INT4", length=10, decimals=0),
                         dict(name=f"L{level:02}_NAME", key=False, type="CHAR", length=name_length, decimals=0),
                         dict(name=f"L{level:02}_CAPTION", key=False, type="CHAR", length=caption_length, decimals=0),
                         dict(name=f"L{level:02}_POS", key=False, type="INT4", length=10, decimals=0)]
    return dict(table=LEVELS + h, fields=level_fields, rows=[[str(v) for v in row] for row in rows])


def build():
    creates, inserts = [], []
    tables = json.loads((EXPORT / "tables.json").read_text(encoding="utf-8"))
    for table in tables:
        c, i = statements(json.loads(table_file(table).read_text(encoding="utf-8")))
        creates += c
        inserts += i
    hierarchies = [json.loads((EXPORT / f"hierarchy_{h}.json").read_text(encoding="utf-8")) for h in HIERARCHIES]
    for data in hierarchies:
        levels = hierarchy_levels(data)
        c, i = statements(levels)
        creates += c
        inserts += i
        print(f"{levels['table']}: {len(levels['rows'])} rows, {(len(levels['fields']) - 1) // 4} levels")
    views = json.loads((EXPORT / "views.json").read_text(encoding="utf-8"))
    assert all(name.startswith(PLACEHOLDER) for name in views), "views.json of an earlier run: export again"
    for name, definition in views.items():
        creates.append(f'CREATE VIEW PUBLIC."{name}" AS ' + definition.replace(CR, " ").replace(NL, " "))
    assert all(OBJECT.search(c) for c in creates)  # so that a later run removes them
    with zipfile.ZipFile(JAR) as zin:
        items = [(item, zin.read(item.filename)) for item in zin.infolist()]
    patched = []
    for item, content in items:
        if item.filename == SCRIPT:
            lines = [line for line in content.decode("utf-8").split(NL) if not OBJECT.search(line)]
            end = CR if lines[0].endswith(CR) else ""
            last_create = max(n for n, line in enumerate(lines) if line.startswith("CREATE "))
            lines[last_create + 1:last_create + 1] = [c + end for c in creates]
            last_line = len(lines) - 1 if lines[-1] == "" else len(lines)
            lines[last_line:last_line] = [i + end for i in inserts]
            content = NL.join(lines).encode("utf-8")
        patched.append((item, content))
    with zipfile.ZipFile(JAR, "w", zipfile.ZIP_DEFLATED) as zout:
        for item, content in patched:
            zout.writestr(item, content)
    print(f"wrote {JAR.relative_to(ROOT)}: {len(tables)} BW tables, {len(hierarchies)} hierarchies, "
          f"{len(inserts)} rows, {len(views)} views")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--no-export", action="store_true", help="use the rows exported before")
    args = parser.parse_args()
    if not args.no_export:
        export()
    build()


if __name__ == "__main__":
    main()
