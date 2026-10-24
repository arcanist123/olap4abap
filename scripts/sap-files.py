#!/usr/bin/env python3
"""Reads and writes the files of the XMLA server on SAP (table ZZXXMLA1_FILE, ZZXXMLA1_CL_FILES): what the files of
its web application are to Mondrian, /WEB-INF/datasources.xml and the schema files its catalogs name in Definition.
A catalog or a schema is added by writing files, without any new ABAP object.

    python scripts/sap-files.py put my/Schema.xml /WEB-INF/schema/Schema.xml
    python scripts/sap-files.py put reference/schema/datasources-sap.xml /WEB-INF/datasources.xml
    python scripts/sap-files.py deploy               # the test schemas (DEPLOY) and their catalogs (below)
    python scripts/sap-files.py list
    python scripts/sap-files.py get /WEB-INF/datasources.xml
    python scripts/sap-files.py delete /WEB-INF/schema/Old.xml

Each command is one `sapcli abap run` (a temporary classrun class, as the user of .env.sap; the endpoint itself writes
only in the schema generator's accept). The content travels base64 encoded, so any text gets there unchanged (UTF-8, line ends
as LF). A new data sources file or schema is read by the next request; no restart is needed.
`deploy` writes the schema files of this repository and merges the repository's catalogs into the server's data
sources file: a catalog of the same name is replaced, the others (the setup's demos, the schema builder's accepted
catalogs) stay; without a data sources file on the server the repository's is written. The schemas name their
dimension tables by placeholder (ZZXXMLA1_C_<characteristic>), as the schema builder's proposals do: a view's number
depends on the views the system has already (other cubes, the demos), so `deploy` puts in the database view of each
characteristic's view (ZZXXMLA1_CL_BW_VIEW_GEN->existing_view), generating the view if there is none.
In Git Bash, run with MSYS_NO_PATHCONV=1: otherwise it turns /WEB-INF/... into a Windows path before Python sees it.
"""
import argparse
import base64
import os
import pathlib
import re
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
# the files `deploy` writes: local file -> path on the server
DEPLOY = [
    ("reference/schema/FoodmartBW.xml", "/WEB-INF/schema/FoodmartBW.xml"),
    ("reference/schema/FoodmartBWDrill.xml", "/WEB-INF/schema/FoodmartBWDrill.xml"),
    ("reference/schema/FoodmartBWCaption.xml", "/WEB-INF/schema/FoodmartBWCaption.xml"),
]
# the clinic's test catalog ZCLHIER is the clinic generator's (ZZXXMLA1_CL_BW_CLINIC_GEN), not deployed from here
# the data sources file `deploy` merges its catalogs from
DATASOURCES = ("reference/schema/datasources-sap.xml", "/WEB-INF/datasources.xml")
MISSING = "<<file does not exist>>"
# a table of a schema named by the characteristic of its view (ZZXXMLA1_CL_BW_VIEW_GEN=>placeholder)
PLACEHOLDER = re.compile(r'"ZZXXMLA1_C_([^"]+)"')
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
    put_text(pathlib.Path(local).read_text(encoding="utf-8-sig"), path)


def put_text(text, path):
    text = text.replace("\r\n", "\n")
    encoded = base64.b64encode(text.encode("utf-8")).decode("ascii")
    # a statement per chunk: one VALUE of all of them exceeds the length of a statement for a large schema
    lines = [f"APPEND {literal(encoded[i:i + CHUNK])} TO chunks." for i in range(0, len(encoded), CHUNK)]
    code = "\n".join([
        "DATA chunks TYPE string_table.",
        *lines,
        "DATA(encoded) = concat_lines_of( chunks ).",
        "zzxxmla1_cl_files=>write(",
        f"  path    = {literal(path)}",
        "  content = cl_abap_codepage=>convert_from( source   = cl_http_utility=>decode_x_base64( encoded )",
        "                                            codepage = `UTF-8` ) ).",
        "COMMIT WORK.",
        f"out->write( |{{ {literal(path)} }}: { len(text)} characters written| ).",
    ])
    print(run_abap(code).strip())


def read(path):
    """The content of a file of the server, None if it does not exist."""
    code = "\n".join([
        f"DATA(file) = zzxxmla1_cl_files=>read( {literal(path)} ).",
        "IF file-path IS INITIAL.",
        f"  out->write( {literal(MISSING)} ).",
        "ELSE.",
        "  out->write( file-content ).",
        "ENDIF.",
    ])
    text = run_abap(code)
    return None if text.strip() == MISSING else text


def get(path):
    text = read(path)
    if text is None:
        print(f"{path} does not exist")
    else:
        print(text, end="")


DATA_SOURCE = re.compile(r"<DataSource>.*?</DataSource>", re.S)
CATALOG = re.compile(r'[ \t]*<Catalog\s+name="([^"]*)"(?:[^>]*/>|.*?</Catalog>)', re.S)


def reindent(block, indent):
    lines = block.strip("\n").split("\n")
    own = len(lines[0]) - len(lines[0].lstrip())
    return "\n".join(indent + line[own:] if not line[:own].strip() else line for line in lines)


def merge_catalogs(server, local):
    """The server's data sources file with the local one's catalogs: a catalog of the same name in the data source of
    the same name is replaced, a new one appended to that data source's catalogs, a data source the server lacks
    appended; everything else in the server's file stays as it is."""
    for local_source in DATA_SOURCE.findall(local):
        name = re.search(r"<DataSourceName>\s*(.*?)\s*</DataSourceName>", local_source, re.S).group(1)
        source = next((m for m in DATA_SOURCE.finditer(server)
                       if re.search(rf"<DataSourceName>\s*{re.escape(name)}\s*</DataSourceName>", m.group(0))), None)
        if source is None:
            end = server.rindex("</DataSources>")
            server = server[:end] + reindent(local_source, "  ") + "\n" + server[end:]
            continue
        text = source.group(0)
        text = re.sub(r"([ \t]*)<Catalogs\s*/>", r"\1<Catalogs>\n\1</Catalogs>", text)
        if "</Catalogs>" not in text:
            indent = re.search(r"\n([ \t]*)</DataSource>", text).group(1) + "  "
            end = text.rindex("</DataSource>")
            text = text[:end].rstrip(" \t") + f"{indent}<Catalogs>\n{indent}</Catalogs>\n" + text[end:]
        indent = re.search(r"([ \t]*)</Catalogs>", text).group(1) + "  "
        for catalog in CATALOG.finditer(local_source):
            block = reindent(catalog.group(0), indent)
            same = next((m for m in CATALOG.finditer(text) if m.group(1) == catalog.group(1)), None)
            if same:
                text = text[:same.start()] + block + text[same.end():]
            else:
                end = re.search(r"[ \t]*</Catalogs>", text).start()
                text = text[:end] + block + "\n" + text[end:]
        server = server[:source.start()] + text + server[source.end():]
    return server


def views_of(characteristics):
    """The database view of each characteristic's plain view, generated where there is none (one sapcli call)."""
    lines = ["DATA(generator) = NEW zzxxmla1_cl_bw_view_gen( ).",
             "DATA name TYPE viewname.",
             "DATA error TYPE REF TO cx_dd_ddl_exception."]
    for characteristic in characteristics:
        assert re.fullmatch(r"[A-Z0-9_/]+", characteristic), characteristic
        lines += [
            f"name = generator->existing_view( '{characteristic}' ).",
            "IF name IS INITIAL.",
            "  TRY.",
            f"      name = generator->generate( '{characteristic}' )-view_name.",
            "    CATCH cx_dd_ddl_exception INTO error.",
            f"      out->write( |{characteristic}: {{ error->get_text( ) }}| ).",
            "      RETURN.",
            "  ENDTRY.",
            "ENDIF.",
            f"out->write( |{characteristic}={{ name }}| ).",
        ]
    lines.append("COMMIT WORK.")
    output = run_abap("\n".join(lines))
    views = dict(re.findall(r"^(\S+)=(\S+)\s*$", output, re.M))
    missing = [c for c in characteristics if c not in views]
    if missing:
        sys.exit(f"error: no view of {', '.join(missing)}\n{output}")
    return views


def deploy():
    # one sapcli call after the other (work processes in PRIV mode, docs/environment.md)
    texts = [((ROOT / local).read_text(encoding="utf-8-sig"), path) for local, path in DEPLOY]
    characteristics = list(dict.fromkeys(c for text, _ in texts for c in PLACEHOLDER.findall(text)))
    views = views_of(characteristics) if characteristics else {}
    for characteristic, view in views.items():
        print(f"{characteristic}: {view}")
    for text, path in texts:
        put_text(PLACEHOLDER.sub(lambda m: f'"{views[m.group(1)]}"', text), path)
    local, path = DATASOURCES
    local_text = (ROOT / local).read_text(encoding="utf-8-sig").replace("\r\n", "\n")
    server = read(path)
    if server is None:
        put_text(local_text, path)
        return
    server = server.replace("\r\n", "\n")
    merged = merge_catalogs(server, local_text)
    if merged == server:
        print(f"{path}: the catalogs are there already")
    else:
        put_text(merged, path)


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
    commands.add_parser("deploy", help="write the repository's schemas and merge its catalogs into the server's")
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
        deploy()
    elif args.command == "list":
        list_files()
    elif args.command == "get":
        get(args.path)
    else:
        delete(args.path)


if __name__ == "__main__":
    main()
