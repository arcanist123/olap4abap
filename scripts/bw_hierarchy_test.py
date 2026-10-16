#!/usr/bin/env python3
"""Compares olap4abap's BW hierarchies with BW's own MDX on the clinic demo (docs/next-steps.md, time-independent BW
hierarchies). The reference server knows no BW hierarchy, so the oracle is BW itself, asked live on the same system:
ZZXXMLA1_CL_BW_HIERARCHY_PROBE (run with sapcli class execute) gives per plain hierarchy every member BW's MDX shows,
in BW's order, with its level, number of children, caption and the values of the measures; the script asks olap4abap
for the same members through XMLA and compares them position by position.

The hierarchies (docs/clinic-demo.md): ZCLDIAG_ICD (a plain tree), ZCLPAT_PRG (link nodes, recursively, duplicate and
link leaves, postable nodes) and ZCLSERV_CAT (intervals, overlapping and linked). What BW shows and the test expects:
- a member per occurrence (a node under two parents is two members, its subtree under each); BW's unique names repeat
  for the occurrences of a node, so members are compared by position, not by unique name;
- a node's value is the sum over the distinct values below it (a value reached by two paths counts once);
- an interval is no member: its values are the leaves, directly under its parent;
- a postable node is a node whose first child is its own value;
- the not-assigned node (REST_H), unless the hierarchy suppresses it, is a root after the hierarchy, its values below
  it; BW gives them its deepest level;
- no All member: olap4abap's All member (MEMBER_TYPE 2), if it has one, is checked against the provider's total and
  left out.

Per member: level (relative to the first root, not under the not-assigned node; a member's DEPTH where it has one,
as the members of a parent-child level all have the level's number), number of children, caption (BW's text; with
--names a text node's technical name or a leaf's key is accepted too, as long as olap4abap has no texts) and the
values. Members BW shows without value are left out by olap4abap's members-with-facts dimensions; --with-facts
compares only the members with a value, in BW's order.

--reference checks the reference server's copy of the hierarchies in which every node occurs once (docs/next-steps.md,
Reference scenario; catalog ZCLVISIT, reference/schema/ClinicBW.xml, built by scripts/build-bw-reference-db.py) against
BW's MDX instead, names as captions: so the export is known to be BW's hierarchy before cases are captured from it.
BW is asked on the aDSO ZCLVISITA, the reference serves the InfoCube ZCLVISIT: both hold the same visits. The
reference serves them as level hierarchies (Level 01 to Level 04); they assign every value and suppress REST_H.

    python scripts/bw_hierarchy_test.py
    python scripts/bw_hierarchy_test.py --names --with-facts --url http://localhost:50000/zzxxmla1?sap-client=001
    python scripts/bw_hierarchy_test.py --bw-only           # BW's answer and its own checks
    python scripts/bw_hierarchy_test.py --reference         # the reference server's ZCLDIAG_ICD
"""
import argparse
import html
import os
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
PROBE = "ZZXXMLA1_CL_BW_HIERARCHY_PROBE"
CATALOG = "ZCLVISITA"
MEASURES = ["[Measures].[ZCLVISNO]", "[Measures].[ZCLCHRG]"]
# BW's hierarchy (characteristic and hierarchy name) -> olap4abap's hierarchy unique name
HIERARCHIES = {
    ("ZCLDIAG", "ZCLDIAG_ICD"): "[ZCLDIAG.ZCLDIAG_ICD]",
    ("ZCLPAT", "ZCLPAT_PRG"): "[ZCLPAT.ZCLPAT_PRG]",
    ("ZCLSERV", "ZCLSERV_CAT"): "[ZCLSERV.ZCLSERV_CAT]",
}
NOT_ASSIGNED = "1HIER_REST"
# --reference: the reference server, its catalog and the hierarchies it serves
REFERENCE_URL = "http://localhost:8080/emondrian/xmla"
REFERENCE_CATALOG = "ZCLHIER"
REFERENCE_HIERARCHIES = [("ZCLDIAG", "ZCLDIAG_ICD")]

EXECUTE = """<SOAP-ENV:Envelope xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/"><SOAP-ENV:Body>
<Execute xmlns="urn:schemas-microsoft-com:xml-analysis"><Command><Statement>{statement}</Statement></Command>
<Properties><PropertyList><DataSourceInfo>ABAP BW</DataSourceInfo><Catalog>{catalog}</Catalog>
<Format>Multidimensional</Format><AxisFormat>TupleFormat</AxisFormat><Content>Data</Content></PropertyList></Properties>
</Execute></SOAP-ENV:Body></SOAP-ENV:Envelope>"""


def env():
    values = {}
    for line in (ROOT / ".env.sap").read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            key, value = line.split("=", 1)
            values[key.strip()] = value.strip().strip('"').strip("'")
    return values


def bw_number(text):
    """BW's formatted value (33.956,000) as a float, None for an empty cell."""
    text = text.strip()
    if not text:
        return None
    return float(text.replace(".", "").replace(",", "."))


def bw_members():
    """Runs the probe; returns the provider's total and per hierarchy (characteristic, name) its members."""
    e = env()
    command = ["sapcli", "--ashost", e["SAP_ASHOST"], "--client", e["SAP_CLIENT"], "--user", e["SAP_USER"]]
    if e.get("SAP_PORT"):
        command += ["--port", e["SAP_PORT"]]
    if e.get("SAP_USE_SSL", "false") != "true":
        command += ["--no-ssl"]
    command += ["class", "execute", PROBE]
    output = subprocess.run(command, capture_output=True, text=True, encoding="utf-8",
                            env={**os.environ, "SAP_PASSWORD": e["SAP_PASSWORD"]})
    if output.returncode != 0 or "\t" not in output.stdout:
        sys.exit(f"{PROBE} failed: {output.stdout[-2000:]}{output.stderr[-2000:]}")
    total, hierarchies = None, {}
    for line in output.stdout.splitlines():
        fields = line.split("\t")
        if len(fields) < 6:
            continue
        hierarchy, ordinal, level, children, unique, caption, *values = fields
        if caption.startswith("ERROR"):
            sys.exit(f"{PROBE}: {hierarchy} {caption}")
        values = [bw_number(v) for v in values]
        if hierarchy == "TOTAL":
            total = values
            continue
        found = re.fullmatch(r"\[(\S+)\s+(\S+)\]", hierarchy)
        node = re.fullmatch(r".*\]\.\[(.*)\]", unique).group(1)
        # a node is its name padded to 32 characters and its InfoObject: a name of 32 leaves no blank between them
        if " " in node:
            name, _, kind = node.rpartition(" ")
        else:
            name, kind = node[:32], node[32:]
        hierarchies.setdefault((found.group(1), found.group(2)), []).append({
            "level": int(level), "children": int(children), "caption": caption, "values": values,
            "name": name.strip(), "kind": kind})
    return total, hierarchies


def post(url, statement):
    import urllib.error
    import urllib.request
    body = EXECUTE.format(statement=html.escape(statement, quote=False), catalog=CATALOG)
    request = urllib.request.Request(url, data=body.encode("utf-8"), headers={
        "Content-Type": "text/xml; charset=utf-8", "SOAPAction": '"urn:schemas-microsoft-com:xml-analysis:Execute"'})
    try:
        with urllib.request.urlopen(request, timeout=600) as response:
            return response.read().decode("utf-8")
    except urllib.error.HTTPError as error:
        return error.read().decode("utf-8", "replace")


def olap4abap_members(url, hierarchy):
    """olap4abap's members of the hierarchy with level, children, caption and values; or the fault."""
    text = post(url, f"SELECT {{{', '.join(MEASURES)}}} ON 0, {{{hierarchy}.Members}} "
                     f"DIMENSION PROPERTIES DEPTH, CHILDREN_CARDINALITY, MEMBER_TYPE ON 1 FROM [{CATALOG}]")
    fault = re.search(r"<faultstring>(.*?)</faultstring>", text, re.S)
    if fault:
        return None, html.unescape(fault.group(1))
    axis = re.search(r'<Axis name="Axis1">(.*?)</Axis>', text, re.S)
    tuples = re.findall(r"<Tuple>(.*?)</Tuple>", axis.group(1), re.S) if axis else []
    cells = {int(o): float(v) for o, v in re.findall(
        r'<Cell CellOrdinal="(\d+)">.*?<Value[^>]*>([^<]*)</Value>', text, re.S)}

    def field(member, tag):
        found = re.search(rf"<{tag}>([^<]*)</{tag}>", member)
        return html.unescape(found.group(1)) if found else ""

    members = []
    for row, member in enumerate(tuples):
        members.append({
            "unique": field(member, "UName"), "caption": field(member, "Caption"),
            "level": int(field(member, "DEPTH") or field(member, "LNum") or 0),
            "children": int(field(member, "CHILDREN_CARDINALITY") or 0),
            "all": field(member, "MEMBER_TYPE") == "2",
            "values": [cells.get(row * len(MEASURES) + column) for column in range(len(MEASURES))]})
    return members, None


def same_values(a, b):
    return all((x is None and y is None) or (x is not None and y is not None and abs(x - y) < 0.005)
               for x, y in zip(a, b))


def bw_checks(total, key, members, check):
    """BW's answer itself: the roots and the not-assigned node add up to the total, at most one not-assigned node."""
    roots = [m for m in members if m["level"] == 0]
    sums = [sum(m["values"][i] or 0 for m in roots) for i in range(len(MEASURES))]
    check(f"BW {key[1]}: roots and not assigned add up to the total", same_values(sums, total), f"{sums} != {total}")
    check(f"BW {key[1]}: at most one not-assigned root", sum(m["kind"] == NOT_ASSIGNED for m in roots) <= 1, roots)


def compare(total, key, expected, actual, args, check):
    if actual and actual[0]["all"]:
        # olap4abap's All member: the provider's total
        check(f"{key[1]}: All member is the total", same_values(actual[0]["values"], total),
              f"{actual[0]['values']} != {total}")
        actual = [{**m, "level": m["level"] - 1} for m in actual[1:]]
    if args.with_facts:
        expected = [m for m in expected if any(v is not None for v in m["values"])]
        actual = [m for m in actual if any(v is not None for v in m["values"])]
    check(f"{key[1]}: {len(expected)} members", len(actual) == len(expected), f"olap4abap has {len(actual)}")

    differences = []
    under_rest = False
    for position, (bw, ours) in enumerate(zip(expected, actual)):
        if bw["level"] == 0:
            under_rest = bw["kind"] == NOT_ASSIGNED
        problems = []
        if not under_rest and bw["level"] != ours["level"]:
            problems.append(f"level {ours['level']} != {bw['level']}")
        if not args.with_facts and bw["children"] != ours["children"]:
            problems.append(f"children {ours['children']} != {bw['children']}")
        captions = {bw["caption"]} | ({bw["name"]} if args.names else set())
        if ours["caption"] not in captions:
            problems.append(f"caption {ours['caption']!r} not in {sorted(captions)}")
        if not same_values(bw["values"], ours["values"]):
            problems.append(f"values {ours['values']} != {bw['values']}")
        if problems:
            differences.append(f"#{position} {bw['caption']} ({ours['unique']}): {', '.join(problems)}")
    check(f"{key[1]}: members the same as BW's, in BW's order", not differences,
          f"{len(differences)} differ; " + "; ".join(differences[:args.show]))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--url", help="the XMLA endpoint (default SAP's, with --reference the reference server)")
    parser.add_argument("--names", action="store_true", help="accept a node's name or key as its caption")
    parser.add_argument("--with-facts", action="store_true", help="compare only the members with a value")
    parser.add_argument("--bw-only", action="store_true", help="only BW's answer and its own checks")
    parser.add_argument("--reference", action="store_true",
                        help="check the reference server's hierarchies (catalog ZCLHIER) against BW's")
    parser.add_argument("--show", type=int, default=10, help="differences shown per hierarchy")
    args = parser.parse_args()
    global CATALOG
    hierarchies_checked = HIERARCHIES
    if args.reference:
        CATALOG = REFERENCE_CATALOG
        hierarchies_checked = {key: HIERARCHIES[key] for key in REFERENCE_HIERARCHIES}
        args.names = True
    args.url = args.url or (REFERENCE_URL if args.reference else "http://localhost:50000/zzxxmla1?sap-client=001")
    failures = []

    def check(name, condition, detail=""):
        print(f"{'ok  ' if condition else 'FAIL'} {name}{'' if condition else ': ' + str(detail)[:2000]}")
        if not condition:
            failures.append(name)

    total, hierarchies = bw_members()
    for key, hierarchy in hierarchies_checked.items():
        expected = hierarchies.get(key)
        if not expected:
            check(f"BW {key[1]}: shown by BW's MDX", False, "not in the probe's answer")
            continue
        bw_checks(total, key, expected, check)
        if args.bw_only:
            continue
        actual, fault = olap4abap_members(args.url, hierarchy)
        if fault:
            check(f"{key[1]}: {hierarchy}.Members", False, fault)
            continue
        compare(total, key, expected, actual, args, check)

    print(f"\n{len(failures)} failure(s)")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
