#!/usr/bin/env python3
"""Runs the captured XMLA exchanges in reference/<case>/ against an XMLA endpoint and compares the responses.

Each case directory holds request.xml and response.xml (captured from eMondrian, see docs/test-strategy.md) and
optionally status.txt (the HTTP status; 200 if missing) and ignore.txt: one XML element name per line whose text may
differ (URLs, descriptions, ...); `Name@Key=Text` limits that to rows that have a child element Key with the text Text;
`@Name` ignores the attribute Name of every element (used for parser messages in faults). Responses are
compared as canonical XML without whitespace-only text, so formatting does not matter, but names, namespaces, order
and values do.

    python scripts/xmla_test.py                          # SAP (default URL below)
    python scripts/xmla_test.py --url http://localhost:8080/emondrian/xmla   # check a case against eMondrian itself
    python scripts/xmla_test.py discover_datasources     # one case
"""
import argparse
import difflib
import pathlib
import sys
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET

from reference_texts import as_olap4abap

ROOT = pathlib.Path(__file__).resolve().parent.parent
DEFAULT_URL = "http://localhost:50000/zzxxmla1?sap-client=001"
SOAP_ACTION = {"Discover": '"urn:schemas-microsoft-com:xml-analysis:Discover"',
               "Execute": '"urn:schemas-microsoft-com:xml-analysis:Execute"'}


def local(tag):
    return tag.rsplit("}", 1)[-1]


def soap_action(request_xml):
    return SOAP_ACTION["Execute" if "<Execute" in request_xml else "Discover"]


def canonical(xml_text, ignore):
    root = ET.fromstring(xml_text)
    plain = {i for i in ignore if "@" not in i}
    attributes = {i[1:] for i in ignore if i.startswith("@")}
    in_rows = [i.split("@", 1) for i in ignore if "@" in i and not i.startswith("@")]
    for element in root.iter():
        if local(element.tag) in plain:
            element.text = "*"
        for attribute in attributes & set(element.attrib):
            element.set(attribute, "*")
    for row in (e for e in root.iter() if local(e.tag) == "row"):
        children = {local(c.tag): c for c in row}
        for name, condition in in_rows:
            key, text = condition.split("=", 1)
            if name in children and key in children and children[key].text == text:
                children[name].text = "*"
    return ET.canonicalize(ET.tostring(root, encoding="unicode"), strip_text=True)


def pretty(canonical_xml):
    return canonical_xml.replace("><", ">\n<").splitlines()


def post(url, request_xml):
    req = urllib.request.Request(url, data=request_xml.encode("utf-8"), method="POST",
                                 headers={"Content-Type": "text/xml; charset=utf-8",
                                          "SOAPAction": soap_action(request_xml)})
    try:
        with urllib.request.urlopen(req, timeout=60) as response:
            return response.status, response.read().decode("utf-8")
    except urllib.error.HTTPError as error:
        return error.code, error.read().decode("utf-8", "replace")


def run_case(url, case_dir):
    request_xml = (case_dir / "request.xml").read_text(encoding="utf-8")
    rows_file = case_dir / "rows.txt"
    if rows_file.exists():  # too big to keep: only the number of rows is compared
        status, body = post(url, request_xml)
        expected_rows = int(rows_file.read_text(encoding="utf-8").strip())
        actual_rows = body.count("<row>")
        if status != 200 or actual_rows != expected_rows:
            return [f"HTTP {status}, {actual_rows} rows, expected {expected_rows} rows: {body[:200] if status != 200 else ''}"]
        return []
    expected_xml = (case_dir / "response.xml").read_text(encoding="utf-8")
    ignore_file = case_dir / "ignore.txt"
    ignore = set(ignore_file.read_text(encoding="utf-8").split()) if ignore_file.exists() else set()

    status_file = case_dir / "status.txt"
    expected_status = int(status_file.read_text(encoding="utf-8").strip()) if status_file.exists() else 200
    status, body = post(url, request_xml)
    if status != expected_status:
        return [f"HTTP {status}, expected {expected_status}: {body[:300]}"]
    try:
        actual = canonical(as_olap4abap(body), ignore)
    except ET.ParseError as error:
        return [f"response is not XML ({error}): {body[:300]}"]
    expected = canonical(as_olap4abap(expected_xml), ignore)
    if actual == expected:
        return []
    return list(difflib.unified_diff(pretty(expected), pretty(actual), "expected", "actual", lineterm="", n=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("cases", nargs="*", help="case names (directories under reference/); default all")
    parser.add_argument("--url", default=DEFAULT_URL)
    args = parser.parse_args()

    cases = sorted(p.parent for p in (ROOT / "reference").glob("*/request.xml")
                   if (p.parent / "response.xml").exists() or (p.parent / "rows.txt").exists())
    if args.cases:
        cases = [c for c in cases if c.name in args.cases]
    if not cases:
        sys.exit("no cases found")

    failed = 0
    for case_dir in cases:
        problems = run_case(args.url, case_dir)
        if problems:
            failed += 1
            print(f"FAIL {case_dir.name}")
            print("\n".join("     " + line for line in problems))
        else:
            print(f"ok   {case_dir.name}")
    print(f"{len(cases) - failed} of {len(cases)} passed ({args.url})")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
