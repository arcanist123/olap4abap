#!/usr/bin/env python3
"""Reads and writes the files of the XMLA server on SAP (table ZZXXMLA1_FILE, ZZXXMLA1_CL_FILES): what the files of
its web application are to Mondrian, /WEB-INF/datasources.xml and the schema files its catalogs name in Definition.
A catalog or a schema is added by writing files, without any new ABAP object.

    python scripts/sap-files.py put reference/schema/FoodmartBW.xml /WEB-INF/schema/FoodmartBW.xml
    python scripts/sap-files.py put reference/schema/datasources-sap.xml /WEB-INF/datasources.xml
    python scripts/sap-files.py deploy               # both of the above: the server's files as this repository has them
    python scripts/sap-files.py app                  # the schema builder: every file of web/schema/ to /schema/...
    python scripts/sap-files.py list
    python scripts/sap-files.py get /WEB-INF/datasources.xml
    python scripts/sap-files.py delete /WEB-INF/schema/Old.xml

Each command is one `sapcli abap run` (a temporary classrun class, as the user of .env.sap; the endpoint itself writes
only in the schema generator's accept). The content travels base64 encoded, so any text gets there unchanged (UTF-8, line ends
as LF). A new data sources file or schema is read by the next request; no restart is needed.
In Git Bash, run with MSYS_NO_PATHCONV=1: otherwise it turns /WEB-INF/... into a Windows path before Python sees it.
"""
import argparse
import base64
import os
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
# the files `deploy` writes: local file -> path on the server
DEPLOY = [
    ("reference/schema/FoodmartBW.xml", "/WEB-INF/schema/FoodmartBW.xml"),
    ("reference/schema/datasources-sap.xml", "/WEB-INF/datasources.xml"),
]
# the schema builder's app (ZZXXMLA1_CL_WEB_APP serves it under /zzxxmla1/schema/): local folder -> server folder
APP = ("web/schema", "/schema")
CHUNK = 120  # characters of base64 per source line


def env():
    values = dict(os.environ)
    env_file = pathlib.Path(os.environ.get("SAP_ENV_FILE", ROOT / ".env.sap"))
    if env_file.exists():
        for line in env_file.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                name, value = line.split("=", 1)
                values.setdefault(name.strip(), value.strip())
    for name in ("SAP_ASHOST", "SAP_CLIENT", "SAP_USER", "SAP_PASSWORD"):
        if not values.get(name):
            sys.exit(f"error: set {name} in .env.sap")
    return values


def run_abap(code):
    values = env()
    command = ["sapcli", "--ashost", values["SAP_ASHOST"], "--client", values["SAP_CLIENT"],
               "--user", values["SAP_USER"]]
    if values.get("SAP_PORT"):
        command += ["--port", values["SAP_PORT"]]
    if values.get("SAP_USE_SSL", "false") != "true":
        command.append("--no-ssl")
    if values.get("SAP_SKIP_SSL_VALIDATION", "false") == "true":
        command.append("--skip-ssl-validation")
    with tempfile.NamedTemporaryFile("w", suffix=".abap", delete=False, encoding="utf-8") as source:
        source.write(code)
    try:
        # the password goes through the environment only, as in sap-sync.sh
        result = subprocess.run(command + ["abap", "run", source.name], env=values, capture_output=True, text=True,
                                encoding="utf-8")
    finally:
        os.unlink(source.name)
    if result.returncode != 0:
        sys.exit(f"error: sapcli abap run failed\n{result.stdout}{result.stderr}")
    return result.stdout


def literal(text):
    return "`" + text.replace("`", "``") + "`"


def put(local, path):
    text = pathlib.Path(local).read_text(encoding="utf-8-sig").replace("\r\n", "\n")
    encoded = base64.b64encode(text.encode("utf-8")).decode("ascii")
    lines = [f"  ( {literal(encoded[i:i + CHUNK])} )" for i in range(0, len(encoded), CHUNK)] or ["  ( `` )"]
    code = "\n".join([
        "DATA(encoded) = concat_lines_of( VALUE string_table(",
        *lines,
        ") ).",
        "zzxxmla1_cl_files=>write(",
        f"  path    = {literal(path)}",
        "  content = cl_abap_codepage=>convert_from( source   = cl_http_utility=>decode_x_base64( encoded )",
        "                                            codepage = `UTF-8` ) ).",
        "COMMIT WORK.",
        f"out->write( |{{ {literal(path)} }}: { len(text)} characters written| ).",
    ])
    print(run_abap(code).strip())


def get(path):
    code = "\n".join([
        f"DATA(file) = zzxxmla1_cl_files=>read( {literal(path)} ).",
        "IF file-path IS INITIAL.",
        f"  out->write( |{{ {literal(path)} }} does not exist| ).",
        "ELSE.",
        "  out->write( file-content ).",
        "ENDIF.",
    ])
    print(run_abap(code), end="")


def list_files():
    code = "\n".join([
        "LOOP AT zzxxmla1_cl_files=>list( ) INTO DATA(file).",
        "  DATA(seconds) = CONV timestamp( file-changed_at ).",
        "  out->write( |{ file-path }  { seconds TIMESTAMP = ISO }  { file-changed_by }| ).",
        "ENDLOOP.",
    ])
    print(run_abap(code), end="")


def delete(path):
    code = "\n".join([
        f"zzxxmla1_cl_files=>delete( {literal(path)} ).",
        "COMMIT WORK.",
        f"out->write( |{{ {literal(path)} }} deleted| ).",
    ])
    print(run_abap(code).strip())


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    put_parser = commands.add_parser("put", help="write a local file to a path on the server")
    put_parser.add_argument("local")
    put_parser.add_argument("path")
    commands.add_parser("deploy", help="write the server's files as this repository has them")
    commands.add_parser("app", help="write the schema builder's files (web/schema/) to /schema/ on the server")
    commands.add_parser("list", help="list the server's files")
    get_parser = commands.add_parser("get", help="print a file of the server")
    get_parser.add_argument("path")
    delete_parser = commands.add_parser("delete", help="delete a file of the server")
    delete_parser.add_argument("path")
    args = parser.parse_args()
    if getattr(args, "path", "/").startswith("/") is False:
        sys.exit(f"error: a server path starts with / (got {args.path}; in Git Bash set MSYS_NO_PATHCONV=1)")
    if args.command == "put":
        put(args.local, args.path)
    elif args.command == "deploy":
        # one sapcli call after the other (work processes in PRIV mode, docs/environment.md)
        for local, path in DEPLOY:
            put(ROOT / local, path)
    elif args.command == "app":
        local, folder = APP
        for file in sorted(p for p in (ROOT / local).rglob("*") if p.is_file()):
            put(file, f"{folder}/{file.relative_to(ROOT / local).as_posix()}")
    elif args.command == "list":
        list_files()
    elif args.command == "get":
        get(args.path)
    else:
        delete(args.path)


if __name__ == "__main__":
    main()
