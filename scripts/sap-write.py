"""Writes ABAP classes and interfaces from src/ into SAP and activates them, like scripts/sap-write.sh, but in one HTTP
session per object that is closed afterwards.

    "$LOCALAPPDATA/pipx/pipx/venvs/sapcli/Scripts/python.exe" scripts/sap-write.py zzxxmla1_cl_sql [zzxxmla1_cl_schema ...]
    ... scripts/sap-write.py --together zzxxmla1_cl_mdx_engine zzxxmla1_cl_mdx_slicer_calc


Runs in sapcli's Python (it uses its library). Every `sapcli class write` is a process of its own whose ADT session
(stateful, for the lock) stays open on the server until it times out: a class of four includes leaves four sessions in
SM04, and on large classes they pin dialog work processes (docs/environment.md, work processes in PRIV mode). Here
one connection writes the includes and activates, then ends the stateful context and logs off. Objects are written one
after the other; the first one that fails stops the run (no retries). With --together all objects are written in one
session and activated in one activation: for objects that need each other (global friends, a new class and its user).
Logon data from .env.sap, as scripts/sap-sync.sh.

Classes have no local includes (CLAUDE.md): only the main source and the test classes are written, and a local
definitions or implementations include that still holds code in SAP is emptied.
"""
import pathlib
import sys

import sap.adt
import sap.adt.objects
import sap.adt.wb

ROOT = pathlib.Path(__file__).resolve().parent.parent
# include type -> sapcli attribute of the class
CLASS_INCLUDES = [(None, None), ("testclasses", "test_classes")]
# the local includes, which must hold no code
LOCAL_INCLUDES = ["definitions", "implementations"]


def env():
    values = {}
    for line in (ROOT / ".env.sap").read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            key, value = line.split("=", 1)
            values[key.strip()] = value.strip().strip('"').strip("'")
    return values


def connect():
    e = env()
    return sap.adt.Connection(e["SAP_ASHOST"], e["SAP_CLIENT"], e["SAP_USER"], e["SAP_PASSWORD"],
                              port=e.get("SAP_PORT") or None, ssl=e.get("SAP_USE_SSL", "false") == "true",
                              verify=e.get("SAP_SKIP_SSL_VALIDATION", "false") != "true")


def close(connection):
    """Ends the stateful ADT context of the session (a stateless request on it), then the login itself."""
    try:
        connection.execute("GET", "repository/informationsystem/objecttypes",
                           params={"maxItemCount": "1", "name": "*", "data": "usedByProvider"},
                           headers={"X-sap-adt-sessiontype": "stateless"})
    finally:
        connection._http_client.execute_with_session(connection._get_session(), "GET", "sap/public/bc/icf/logoff")


def write(obj, path):
    with obj.open_editor() as editor:
        editor.write(path.read_text(encoding="utf-8"))


def has_code(text):
    """True if an ABAP source has a line that is neither blank nor a comment."""
    return any(line.strip() and not line.lstrip().startswith(("*", '"')) for line in text.splitlines())


def write_object(connection, base):
    name = base.upper()
    intf = ROOT / "src" / f"{base}.intf.abap"
    if intf.exists():
        obj = sap.adt.Interface(connection, name)
        write(obj, intf)
    else:
        obj = sap.adt.Class(connection, name)
        for suffix, attribute in CLASS_INCLUDES:
            path = ROOT / "src" / (f"{base}.clas.{suffix}.abap" if suffix else f"{base}.clas.abap")
            if path.exists():
                write(getattr(obj, attribute) if attribute else obj, path)
        for attribute in LOCAL_INCLUDES:
            include = getattr(obj, attribute)
            if has_code(include.text):
                with include.open_editor() as editor:
                    editor.write("\n")  # sapcli strips one trailing newline; it rejects ""
                print(f"   {name}: local {attribute} emptied")
    return obj


def activate(connection, objects):
    references = sap.adt.objects.ADTObjectReferences()
    for obj in objects:
        references.add_object(obj)
    results, _ = sap.adt.wb.mass_activate(connection, references)
    errors = [m for m in results.messages if m.is_error]
    warnings = [m for m in results.messages if m.is_warning]
    print(f"== {', '.join(obj.name for obj in objects)}: Errors: {len(errors)} Warnings: {len(warnings)}")
    for m in errors + warnings:
        print(f"  {m.typ}: {m.obj_descr} line {m.line}: {m.short_text}")
    return not errors


def main():
    args = [a.lower() for a in sys.argv[1:]]
    together = "--together" in args
    bases = [a for a in args if a != "--together"]
    for group in ([bases] if together else [[base] for base in bases]):
        connection = connect()
        try:
            ok = activate(connection, [write_object(connection, base) for base in group])
        finally:
            close(connection)
        if not ok:
            sys.exit(1)


if __name__ == "__main__":
    main()
