#!/usr/bin/env python3
"""Compares olap4abap's answers with the cases captured from SSAS Multidimensional (reference/execute_ssasmd_*,
docs/test-strategy.md, Clinic demo: BW hierarchies): each statement is rewritten into olap4abap's names, asked of
SAP's catalog ZCLHIER and compared by its values only; names, captions, levels, parents and order are BW's to check.

The rewrite (SSAS's model is scripts/build-ssas-clinic-md.py's, olap4abap's the schema of ZCLHIER on SAP, which the
clinic generator ZZXXMLA1_CL_BW_CLINIC_GEN deploys, read with scripts/sap-files.py):
- a BW hierarchy [H].[H] is olap4abap's [C.H], its occurrence &[POS] the path of names data/foodmart-bw/ssas/members.json
  (olap4abap's own unique name of it, the key of the path, is compared as that path, scripts/bw_names.py)
  gives, its All member olap4abap's allMemberName, its levels [Level nn] the same;
- a characteristic's hierarchy [C].[C] is [C], its member [C].[C].&[SID] stays (the level's member by key, the SID
  in both);
- DIMENSION PROPERTIES keeps the standard properties and asks MEMBER_KEY, by which a characteristic's member of the
  answer is matched; the member properties of levels are left out (their values are not compared).

An Execute's cells are compared per tuple of the axes (the slicer is not compared, SSAS lists every hierarchy in it):
the tuples of each axis as sets, every cell's value (SSAS's xsd:decimal against olap4abap's xsd:double, a relative
difference below 1e-9 is equal; strings with their unique names rewritten). A drill-through is compared as the set
of distinct rows over the columns of the default action (SSAS answers a node's rows twice), by dimension.

    python scripts/ssas_compare.py                        # every execute_ssasmd_* case
    python scripts/ssas_compare.py prg_roots srv_roots    # some, with or without the prefix
    python scripts/ssas_compare.py --show prg_roots       # also print the rewritten statement
"""
import argparse
import html
import json
import os
import pathlib
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from decimal import Decimal, InvalidOperation

from bw_names import as_name_paths
from xmla_test import DEFAULT_URL, local, post
import sap_auth

ROOT = pathlib.Path(__file__).resolve().parent.parent
PREFIX = "execute_ssasmd_"
MEMBERS = ROOT / "data/foodmart-bw/ssas/members.json"
CATALOG = "ZCLHIER"
# the schema file of the catalog on SAP (ZZXXMLA1_CL_SCHEMA_API's accept writes /WEB-INF/schema/<catalog>.xml)
SCHEMA = f"/WEB-INF/schema/{CATALOG}.xml"
STANDARD_PROPERTIES = {"PARENT_UNIQUE_NAME", "HIERARCHY_UNIQUE_NAME", "MEMBER_KEY", "CHILDREN_CARDINALITY",
                       "PARENT_LEVEL", "PARENT_COUNT", "MEMBER_TYPE", "MEMBER_NAME", "MEMBER_CAPTION", "DESCRIPTION",
                       "LEVEL_UNIQUE_NAME", "LEVEL_NUMBER", "MEMBER_UNIQUE_NAME", "DIMENSION_UNIQUE_NAME"}
TOLERANCE = 1e-9
SHOWN = 10  # differences printed per case

# a compound identifier: [name] or &[key] segments joined by dots (]] inside a name is a ])
SEGMENT = r"&?\[(?:[^\]]|\]\])*\]"
COMPOUND = re.compile(rf"{SEGMENT}(?:\s*\.\s*{SEGMENT})*")


def server_file(path):
    """A file of the server (scripts/sap-files.py get)."""
    result = subprocess.run([sys.executable, str(ROOT / "scripts/sap-files.py"), "get", path], capture_output=True,
                            text=True, encoding="utf-8", env={**os.environ, "MSYS_NO_PATHCONV": "1"})
    if result.returncode or "<Schema" not in result.stdout:
        sys.exit(f"{path} not read from SAP: {result.stdout[-1000:]}{result.stderr[-1000:]}")
    return result.stdout.encode("utf-8")


def quote(name):
    return "[" + name.replace("]", "]]") + "]"


def segments(identifier):
    """The segments of a compound identifier as (name, is_key)."""
    return [(m.group(0)[2 if m.group(0).startswith("&") else 1:-1].replace("]]", "]"), m.group(0).startswith("&"))
            for m in re.finditer(SEGMENT, identifier)]


class Model:
    """The names of both servers: per hierarchy of SSAS olap4abap's hierarchy and All member, and the occurrences."""

    def __init__(self):
        schema = ET.fromstring(server_file(SCHEMA))
        self.flat, self.bw = {}, {}  # SSAS's hierarchy name -> (olap4abap's hierarchy, olap4abap's All member)
        self.drill_columns = {}  # olap4abap's drill-through column name -> dimension
        for dimension in schema.findall("Dimension"):
            name = dimension.get("name")
            for hierarchy in dimension.findall("Hierarchy"):
                if hierarchy.get("name"):
                    unique = quote(f"{name}.{hierarchy.get('name')}")
                    self.bw[hierarchy.get("name")] = (unique, f"{unique}.{quote(hierarchy.get('allMemberName'))}")
                else:
                    unique = quote(name)
                    self.flat[name] = (unique, f"{unique}.{quote(hierarchy.get('allMemberName'))}")
        for action in schema.find("Cube").findall("DrillThroughAction"):
            if action.get("default") == "true":
                self.drill_columns = {a.get("name"): a.get("dimension") for a in action.findall("DrillThroughAttribute")}
        members = json.loads(MEMBERS.read_text(encoding="utf-8"))
        self.occurrence = {h: {m["pos"]: m["olap4abap"] for m in rows} for h, rows in members.items()}
        missing = set(self.occurrence) - set(self.bw)
        assert not missing, f"hierarchies of members.json not in {SCHEMA}: {missing}"

    # --- statements ----------------------------------------------------------------------------------------------

    def rewrite_identifier(self, identifier):
        """olap4abap's name of an SSAS identifier, or None to leave it alone (measures, cube, functions' names)."""
        parts = segments(identifier)
        names = [n for n, _ in parts]
        if len(parts) >= 2 and names[0] == names[1] and not parts[1][1]:
            hierarchy, rest = names[0], parts[2:]
            if hierarchy in self.bw:
                unique, all_member = self.bw[hierarchy]
                if not rest:
                    return unique
                (name, is_key), = rest if len(rest) == 1 else [(None, None)]
                if is_key:
                    return self.occurrence[hierarchy][int(name)]
                if name and name.startswith("All "):
                    return all_member
                if name and re.fullmatch(r"Level \d\d", name):
                    return f"{unique}.{quote(name)}"
                if name == hierarchy:
                    return None  # the parent attribute's level, a member property only: left out by the caller
                raise ValueError(f"cannot rewrite {identifier}")
            if hierarchy in self.flat:
                unique, all_member = self.flat[hierarchy]
                if not rest:
                    return unique
                if len(rest) == 1:
                    name, is_key = rest[0]
                    if is_key:
                        return f"{unique}.{quote(hierarchy)}.&{quote(name)}"  # the level's member by key
                    if name.startswith("All "):
                        return all_member
                    if name == hierarchy:
                        return f"{unique}.{quote(name)}"  # the level
                return None  # a member property of the level: left out by the caller
            raise ValueError(f"unknown hierarchy in {identifier}")
        return identifier

    def rewrite_properties(self, match):
        kept = [p.strip() for p in match.group(1).split(",")]
        kept = [p for p in kept if p.upper() in STANDARD_PROPERTIES]
        if "MEMBER_KEY" not in (p.upper() for p in kept):
            kept.append("MEMBER_KEY")
        return f"DIMENSION PROPERTIES {','.join(kept)} ON"

    def rewrite(self, statement):
        statement = re.sub(r"DIMENSION\s+PROPERTIES\s+(.*?)\s+ON\b", self.rewrite_properties, statement,
                           flags=re.S | re.I)

        def one(match):
            rewritten = self.rewrite_identifier(match.group(0))
            if rewritten is None:
                raise ValueError(f"cannot rewrite {match.group(0)}")
            return rewritten
        return COMPOUND.sub(one, statement)

    # --- answers -------------------------------------------------------------------------------------------------

    def ssas_member(self, unique_name):
        """The member of an SSAS answer as olap4abap's: a BW hierarchy's by name, a characteristic's by its key."""
        rewritten = self.rewrite_identifier(unique_name)
        parts = segments(unique_name)
        if parts[0][0] in self.flat and len(parts) == 3 and parts[2][1]:
            return (self.flat[parts[0][0]][0], parts[2][0])
        return rewritten

    def olap4abap_member(self, unique_name, hierarchy, key):
        if hierarchy in (u for u, _ in self.flat.values()) and unique_name not in (a for _, a in self.flat.values()):
            return (hierarchy, key)
        return as_name_paths(unique_name)

    def rewrite_text(self, value):
        """A string cell (Excel's __XLPath: unique names joined by __XLPSEP) in olap4abap's names."""
        return COMPOUND.sub(lambda m: self.rewrite_identifier(m.group(0)) or m.group(0), value)


def statement_of(request_xml):
    return html.unescape(re.search(r"<Statement>(.*?)</Statement>", request_xml, re.S).group(1))


def with_statement(request_xml, statement):
    escaped = statement.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    return re.sub(r"<Statement>.*?</Statement>", lambda _: f"<Statement>{escaped}</Statement>", request_xml,
                  flags=re.S)


def children(element, name):
    return [c for c in element if local(c.tag) == name]


def child_text(element, name):
    found = children(element, name)
    return found[0].text or "" if found else None


def md_answer(text, member_of):
    """Axes (a list of tuples per axis but the slicer) and cells (ordinal -> value) of a multidimensional answer."""
    root = ET.fromstring(text)
    faults = [e for e in root.iter() if local(e.tag) in ("Fault", "Error")]
    if faults:
        raise ValueError("fault: " + ET.tostring(faults[0], encoding="unicode")[:300])
    axes = []
    for axis in (e for e in root.iter() if local(e.tag) == "Axis"):
        if axis.get("name") == "SlicerAxis":
            continue
        tuples = []
        for tuple_ in (e for e in axis.iter() if local(e.tag) == "Tuple"):
            tuples.append(tuple(member_of(m) for m in children(tuple_, "Member")))
        axes.append(tuples)
    cells = {}
    for cell in (e for e in root.iter() if local(e.tag) == "Cell"):
        value = children(cell, "Value")
        if value:
            cells[int(cell.get("CellOrdinal"))] = (value[0].text or "", value[0].get(
                "{http://www.w3.org/2001/XMLSchema-instance}type", ""))
    return axes, cells


def by_tuple(axes, cells):
    """The cells keyed by the tuple of every axis' tuple."""
    result = {}
    sizes = [len(a) for a in axes]
    total = 1
    for size in sizes:
        total *= size
    for ordinal in range(total):
        rest, key = ordinal, []
        for axis, size in zip(axes, sizes):
            key.append(axis[rest % size])
            rest //= size
        result[tuple(key)] = cells.get(ordinal)
    return result


def number(value):
    if value is None:
        return None
    text, kind = value
    if not kind.endswith("string"):  # xsd:decimal, xsd:double, xsd:int, xsd:integer, ... or untyped
        try:
            return Decimal(text)
        except InvalidOperation:
            return text
    return text


def equal(expected, actual):
    if isinstance(expected, Decimal) and isinstance(actual, Decimal):
        if expected == actual:
            return True
        return abs(expected - actual) <= Decimal(TOLERANCE) * max(abs(expected), abs(actual))
    return expected == actual


def compare_md(model, expected_xml, actual_xml):
    def ssas(member):
        return model.ssas_member(child_text(member, "UName"))

    def ours(member):
        return model.olap4abap_member(child_text(member, "UName"), member.get("Hierarchy"),
                                      child_text(member, "MEMBER_KEY"))
    expected_axes, expected_cells = md_answer(expected_xml, ssas)
    actual_axes, actual_cells = md_answer(actual_xml, ours)
    problems = []
    if len(expected_axes) != len(actual_axes):
        return [f"{len(actual_axes)} axes, expected {len(expected_axes)}"], ""
    for number_, (e, a) in enumerate(zip(expected_axes, actual_axes)):
        missing, extra = [t for t in e if t not in set(a)], [t for t in a if t not in set(e)]
        if missing or extra or len(e) != len(a):
            problems.append(f"Axis{number_}: {len(a)} tuples, expected {len(e)}; "
                            f"{len(missing)} missing, {len(extra)} extra")
            problems += [f"  missing {t}" for t in missing[:SHOWN]] + [f"  extra   {t}" for t in extra[:SHOWN]]
    expected, actual = by_tuple(expected_axes, expected_cells), by_tuple(actual_axes, actual_cells)
    differ = []
    for key, value in expected.items():
        if key not in actual:
            continue
        e, a = number(value), number(actual[key])
        if isinstance(e, str):
            e = model.rewrite_text(e)
        if isinstance(a, str):
            a = as_name_paths(a)
        if not equal(e, a):
            differ.append(f"  {key}: {a}, expected {e}")
    if differ:
        problems.append(f"{len(differ)} of {len(expected)} cells differ")
        problems += differ[:SHOWN]
    return problems, f"{len(expected)} cells"


def rows_of(text):
    root = ET.fromstring(text)
    faults = [e for e in root.iter() if local(e.tag) in ("Fault", "Error")]
    if faults:
        raise ValueError("fault: " + ET.tostring(faults[0], encoding="unicode")[:300])
    return [{decoded(local(c.tag)): c.text or "" for c in row} for row in root.iter() if local(row.tag) == "row"]


def decoded(name):
    return re.sub(r"_x([0-9A-Fa-f]{4})_", lambda m: chr(int(m.group(1), 16)), name)


def compare_drillthrough(model, expected_xml, actual_xml):
    def ssas_dimension(column):  # [$ZCLPAT].[ZCLPAT Key]
        return segments(column)[0][0].lstrip("$")
    expected_rows = [{ssas_dimension(k): v for k, v in r.items()} for r in rows_of(expected_xml)]
    actual_rows = rows_of(actual_xml)
    actual_rows = [{model.drill_columns.get(k, k): v for k, v in r.items()} for r in actual_rows]
    columns = sorted(set(expected_rows[0]) if expected_rows else set())
    problems = []
    if actual_rows and set(actual_rows[0]) != set(columns):
        problems.append(f"columns {sorted(actual_rows[0])}, expected {columns}")
    expected = {tuple(r.get(c) for c in columns) for r in expected_rows}
    actual = {tuple(r.get(c) for c in columns) for r in actual_rows}
    if expected != actual:
        problems.append(f"{len(actual)} distinct rows ({len(actual_rows)} rows), expected {len(expected)} "
                        f"({len(expected_rows)} rows); {len(expected - actual)} missing, {len(actual - expected)} extra")
        problems += [f"  missing {dict(zip(columns, r))}" for r in sorted(expected - actual)[:SHOWN]]
        problems += [f"  extra   {dict(zip(columns, r))}" for r in sorted(actual - expected)[:SHOWN]]
    return problems, f"{len(expected)} distinct rows"


def run_case(model, url, folder, show):
    request_xml = (folder / "request.xml").read_text(encoding="utf-8")
    statement = model.rewrite(statement_of(request_xml))
    if show:
        print(statement)
    request_xml = re.sub(r"<Catalog>[^<]*</Catalog>", f"<Catalog>{CATALOG}</Catalog>", request_xml)
    status, body = post(url, with_statement(request_xml, statement))
    if status != 200:
        return [f"HTTP {status}: {body[:300]}"], ""
    expected = (folder / "response.xml").read_text(encoding="utf-8")
    try:
        if statement.lstrip().upper().startswith("DRILLTHROUGH"):
            return compare_drillthrough(model, expected, body)
        return compare_md(model, expected, body)
    except (ValueError, ET.ParseError) as error:
        return [str(error)], ""


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("cases", nargs="*", help="case names, with or without execute_ssasmd_; default all")
    parser.add_argument("--url", default=DEFAULT_URL)
    parser.add_argument("--show", action="store_true", help="print the rewritten statements")
    args = parser.parse_args()
    sap_auth.install()
    model = Model()
    cases = sorted(p for p in (ROOT / "reference").glob(PREFIX + "*") if (p / "ssas.txt").exists())
    if args.cases:
        names = {c if c.startswith(PREFIX) else PREFIX + c for c in args.cases}
        cases = [c for c in cases if c.name in names]
    if not cases:
        sys.exit("no cases found")
    failed = 0
    for folder in cases:
        try:
            problems, compared = run_case(model, args.url, folder, args.show)
        except ValueError as error:
            problems, compared = [f"rewrite: {error}"], ""
        if problems:
            failed += 1
            print(f"FAIL {folder.name}")
            print("\n".join("     " + line for line in problems))
        else:
            print(f"ok   {folder.name} ({compared})")
    print(f"{len(cases) - failed} of {len(cases)} passed ({args.url})")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
