#!/usr/bin/env python3
"""Copies the BW tables of the cubes ZFMSALES and ZXMLWIDE, as BW holds them, into the reference database of the
eMondrian container.

Why: the reference schema (reference/schema/FoodmartBW.xml) names the BW tables themselves (/BIC/FZFMSALES,
/BIC/SZFMSTORE, /BIC/PZFMSTORE, ...), so that the same schema runs in eMondrian and in SAP (docs/mvp-scope.md, schema
decision). The reference database therefore needs tables of these names with BW's contents: the fact table and the SID
and attribute tables of the characteristics of the cube, with BW's columns and values (NUMC zero-padded, blank
instead of NULL, SIDs equal to the FoodMart ids). The same for the wide demo ZXMLWIDE (docs/wide-demo.md), whose schema
reference/schema/ZXMLWIDE.xml the schema builder made on SAP: 100 characteristics, 201 tables.

1. Export (skipped with --no-export): the columns of the tables from DD03L and their rows, read with
   `sapcli datapreview osql` (logon data from .env.sap), into data/foodmart-bw/bw/<table>.json (git-ignored); and the
   SQL of the generated characteristic views (ZZXXMLA1V..., ZZXXMLA1_CL_BW_VIEW_GEN) from HANA's SYS.VIEWS, read with
   hdbsql in the SAP container (HANA_CONTAINER, HANA_OS_USER, HANA_KEY; defaults a4h, a4hadm, DEFAULT), into
   data/foodmart-bw/bw/views.json. HSQLDB takes HANA's view SQL as it is, so the reference has exactly SAP's views.
   Only the views over tables copied here are kept (SAP has views of other providers, e.g. the clinic demo's).
2. Build: adds the tables to data/foodmart-bw/hsqldb-foodmart.jar (the FoodMart data with the empty members, see
   scripts/add-empty-members.py): CREATE MEMORY TABLE after the last CREATE of foodmart.script, the rows at its end.
   Then the characteristic views under their database names, after the tables. Lines of an earlier run (they name
   /BIC/ tables) are removed first, so the script can run again.
   Column types: NUMC and CHAR are VARCHAR of their length (HANA: NVARCHAR), INT4 is INTEGER, DEC is DECIMAL.
   Primary keys as in BW (none for the fact table, whose package key is not unique), a unique index on SID of the
   SID tables and an index per SID column of the fact table (HSQLDB joins without them are slow).

Then: scripts/deploy-reference-schema.sh (installs jar and schema in the container).

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
    "ZXMLWIDE": ([f"ZXMLAD{n:02}" for n in range(100)], "/BIC/_ZXML%"),
}
TABLES = [table for cube, (characteristics, _) in CUBES.items()
          for table in [f"/BIC/F{cube}"] + [f"/BIC/{t}{c}" for c in characteristics for t in "SP"]]
CR, NL = "\r", "\n"
VIEW_PATTERN = "ZZXXMLA1V%"  # the database views of ZZXXMLA1_CL_BW_VIEW_GEN
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


def export():
    EXPORT.mkdir(parents=True, exist_ok=True)
    columns = {}
    for _, pattern in CUBES.values():
        for c in sapcli("SELECT tabname, position, fieldname, keyflag, datatype, leng, decimals FROM dd03l "
                        f"WHERE as4local = 'A' AND tabname LIKE '{pattern}' "
                        "ORDER BY tabname ASCENDING, position ASCENDING", 100000):
            columns.setdefault(c["TABNAME"], []).append(c)
    for table in TABLES:
        fields = [dict(name=c["FIELDNAME"], key=c["KEYFLAG"] == "X", type=c["DATATYPE"], length=int(c["LENG"]),
                       decimals=int(c["DECIMALS"])) for c in columns.get(table, [])
                  if c["DATATYPE"] and not c["FIELDNAME"].startswith(".")]
        assert fields, table
        # one statement per table: the data preview rejects longer statements
        rows = sapcli(f"SELECT * FROM {table}", 1000000)
        data = dict(table=table, fields=fields, rows=[[r[f["name"]] for f in fields] for r in rows])
        file = EXPORT / (table.replace("/", "_").strip("_") + ".json")
        file.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
        print(f"exported {table}: {len(rows)} rows")
    export_views()


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
    """The SQL of the generated characteristic views, read from HANA in chunks (hdbsql cuts LOB values short)."""
    views = {}
    for name, length in hdbsql("SELECT VIEW_NAME, LENGTH(DEFINITION) FROM SYS.VIEWS "
                               f"WHERE SCHEMA_NAME = CURRENT_SCHEMA AND VIEW_NAME LIKE '{VIEW_PATTERN}' ORDER BY VIEW_NAME"):
        parts = []
        for start in range(1, int(length) + 1, CHUNK):
            parts += hdbsql(f"SELECT TO_NVARCHAR(SUBSTRING(DEFINITION, {start}, {CHUNK})) FROM SYS.VIEWS "
                            f"WHERE SCHEMA_NAME = CURRENT_SCHEMA AND VIEW_NAME = '{name}'")[0]
        definition = "".join(parts)
        assert len(definition) == int(length), name
        tables = set(re.findall(r'(?:FROM|JOIN)\s+"([^"]+)"', definition))
        if tables and tables <= set(TABLES):  # only views over the copied tables
            views[name] = definition
    (EXPORT / "views.json").write_text(json.dumps(views, indent=1), encoding="utf-8")
    print(f"exported {len(views)} views: {', '.join(views)}")


def sql_type(field):
    if field["type"] in ("NUMC", "CHAR"):
        return f'VARCHAR({field["length"]})'
    if field["type"] == "INT4":
        return "INTEGER"
    if field["type"] == "DEC":
        return f'DECIMAL({field["length"]},{field["decimals"]})'
    raise ValueError(field)


def literal(field, value):
    value = value.strip() if field["type"] in ("INT4", "DEC") else value
    if field["type"] in ("INT4", "DEC"):
        float(value)
        return value
    assert all(ord(ch) < 128 for ch in value), value  # the script is read as ISO-8859-1 with \\u escapes
    return "'" + value.replace("'", "''") + "'"


def statements(data):
    table, fields = data["table"], data["fields"]
    columns = ",".join(f'"{f["name"]}" {sql_type(f)} NOT NULL' for f in fields)
    keys = ",".join(f'"{f["name"]}"' for f in fields if f["key"])
    # the fact table of a HANA-optimised cube has no unique key (DD03L flags only the package dimension)
    primary_key = "" if table.startswith("/BIC/F") else f",PRIMARY KEY({keys})"
    create = [f'CREATE MEMORY TABLE PUBLIC."{table}"({columns}{primary_key})']
    if any(f["name"] == "SID" for f in fields) and not any(f["name"] == "SID" and f["key"] for f in fields):
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


def build():
    creates, inserts = [], []
    for table in TABLES:
        data = json.loads((EXPORT / (table.replace("/", "_").strip("_") + ".json")).read_text(encoding="utf-8"))
        c, i = statements(data)
        creates += c
        inserts += i
    views = json.loads((EXPORT / "views.json").read_text(encoding="utf-8"))
    for name, definition in views.items():
        assert '"/BIC/' in definition, name  # so that a later run removes it with the tables
        creates.append(f'CREATE VIEW PUBLIC."{name}" AS ' + definition.replace(CR, " ").replace(NL, " "))
    with zipfile.ZipFile(JAR) as zin:
        items = [(item, zin.read(item.filename)) for item in zin.infolist()]
    patched = []
    for item, content in items:
        if item.filename == SCRIPT:
            lines = [line for line in content.decode("utf-8").split(NL) if '"/BIC/' not in line]
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
    print(f"wrote {JAR.relative_to(ROOT)}: {len(TABLES)} BW tables, {len(inserts)} rows, {len(views)} views")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--no-export", action="store_true", help="use the rows exported before")
    args = parser.parse_args()
    if not args.no_export:
        export()
    build()


if __name__ == "__main__":
    main()
