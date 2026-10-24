#!/usr/bin/env python3
"""Records BW's answers for the analysis authorization scenarios (docs/clinic-demo.md, Authorization scenarios): runs
the probe (GET auth/probe of the schema API, ZZXXMLA1_CL_BW_AUTH_PROBE: BW's own MDX on $ZCLVISITA) with the
analysis authorizations of each test user ZZXXMLA1_A01 ... A21 at each key date, one request per key date and kind of
query, and writes reference/auth/<scenario>.json, the oracle of olap4abap's authorization check (docs/next-steps.md,
Now: analysis authorisations, step 2).

The probe runs as BW's "Execute as Other User" (RSUDO) does: the caller stays the node's user, BW checks the
authorizations of the test user (RSEC_SET_USERNAME), so no test user logs on. With --verify N every N-th statement of
the key date 9999-12-31 is sent to BW's own XMLA service (/sap/bw/xml/soap/xmla) logged on as the user (password
SAP_TEST_PASSWORD of .env.sap, the one the setup gave the users) and its answer compared with the probe's: both answer
with the same values or both refuse; the logged-on answer is kept with the statement where it is a refusal or differs
(loggedOn). Observed: the values are the same; BW refuses with other words through the switch; and a statement on a
hierarchy the user has no node of BW answers empty through the switch but refuses logged on ("No authority for the
node ..."), which is the only difference that does not fail the run. BW's XMLA uses today as key date, which is in the
slices valid to 9999-12-31.

A file holds the scenario, its user and analysis authorizations, the authorizations the probe lists for the user and
per query its key date, what it asks (characteristic, hierarchy, test, node, the other characteristic), BW's status
(OK, EMPTY, NO AUTH, UNKNOWN: a value BW does not show the user, ERROR), message and its cells: per row the
members of its tuple (the member's part of BW's unique name, blanks collapsed: All, 008, CLINIC 0HIER_NODE) and the
value (null if empty; {"status": ...} after it if BW gives a cell status). Empty fields are left out. The statements
are the same for every user: reference/auth/statements.json holds each once, by the key of what the row asks
(statement_key).

    python scripts/auth_probe.py                      # every scenario, key dates 2024-06-15, 2025-06-15, 9999-12-31
    python scripts/auth_probe.py --scenario EQ --scenario H1 --key-date 9999-12-31
    python scripts/auth_probe.py --verify 10          # and compare every 10th statement with a logon of the user
"""
import argparse
import base64
import http.cookiejar
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from xml.sax.saxutils import escape

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
KEY_DATES = ["2024-06-15", "2025-06-15", "9999-12-31"]
# the probe's kinds of query, one request each (combine_leaves is left out: the leaves as slicers add nothing)
TESTS = ["flat", "members", "slicer", "rows", "children", "parent", "combined", "non_empty", "crossjoin", "levels",
         "pairs"]
# the value pairs of the test pairs (ZCLDOC, ZCLDIAG): the physicians and diagnoses the scenarios name (EQ, PULM's
# 012 and 013, CROSS's 009 with I10 and 012 with J45) with a respiratory (J06) and another diagnosis (A09)
PAIRS = [f"{doc}:{diag}" for doc in ("001", "008", "009", "012", "013") for diag in ("I10", "J45", "J06", "A09")]
FIELDS = ["keyDate", "characteristic", "hierarchy", "validTo", "test", "node", "nodeType", "level", "filterChar",
          "filterHierarchy", "filterNode", "status", "rows", "message", "mdx"]
KEY_FIELDS = ["keyDate", "test", "characteristic", "hierarchy", "node", "filterChar", "filterHierarchy", "filterNode"]
ANSWERED = ("OK", "EMPTY")
SOAP = ('<?xml version="1.0"?><SOAP-ENV:Envelope xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/">'
        '<SOAP-ENV:Body>{}</SOAP-ENV:Body></SOAP-ENV:Envelope>')


def read_env():
    env = {}
    with open(os.path.join(ROOT, ".env.sap"), encoding="utf-8") as f:
        for line in f:
            if "=" in line and not line.lstrip().startswith("#"):
                name, value = line.rstrip("\n").split("=", 1)
                env[name.strip()] = value.strip()
    return env


class Session:
    """One cookie session, logged off at the end; basic authentication if a user is given."""

    def __init__(self, url, client, user=None, password=None):
        self.url = url
        self.client = client
        self.opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))
        self.headers = {}
        if user:
            token = base64.b64encode(f"{user}:{password}".encode("utf-8")).decode("ascii")
            self.headers["Authorization"] = f"Basic {token}"

    def open(self, path, params=None, body=None, headers=None):
        query = urllib.parse.urlencode({"sap-client": self.client, **(params or {})})
        request = urllib.request.Request(f"{self.url}{path}?{query}", headers={**self.headers, **(headers or {})},
                                         data=body.encode("utf-8") if body is not None else None)
        try:
            with self.opener.open(request, timeout=900) as response:
                return response.status, response.read().decode("utf-8")
        except urllib.error.HTTPError as error:
            return error.code, error.read().decode("utf-8", "replace")

    def get_json(self, path, params=None):
        status, text = self.open(path, params)
        try:
            return status, json.loads(text)
        except ValueError:
            return status, {"error": text[:300]}

    def logoff(self):
        try:
            self.open("", {"sap-sessioncmd": "logoff"})
        except (urllib.error.URLError, OSError):
            pass


def member_key(unique_name):
    """The member's part of BW's unique name, blanks collapsed: [ZCLDOC  ZCLDOC_ORG  001].[CLINIC  0HIER_NODE] is
    CLINIC 0HIER_NODE."""
    part = unique_name.split("].[", 1)[1][:-1] if "].[" in unique_name else unique_name
    return re.sub(r"\s+", " ", part).strip()


def number(text):
    if text == "":
        return None
    value = float(text)
    return int(value) if value.is_integer() else value


def compact(row):
    entry = {name: row[name] for name in FIELDS if row.get(name) not in ("", None, 0)}
    if not row["mdx"]:
        # a row without a statement (HIERARCHIES: the hierarchies BW lists to the user) is its answer
        entry["answer"] = row["answer"]
    elif row["status"] in ANSWERED:
        entry["cells"] = [[member_key(m) for m in cell["members"]] + [number(cell["value"])]
                          + ([{"status": cell["status"]}] if cell["status"] else []) for cell in row["cells"]]
    return entry


def probe(api, user, key_dates):
    """The probe with the user's authorizations: per key date and kind of query one request; the authorizations of
    the first."""
    authorizations, results = None, []
    for key_date in key_dates:
        for test in TESTS:
            params = {"user": user, "keyDates": key_date, "tests": test}
            if test == "pairs":
                params["pairs"] = ",".join(PAIRS)
            status, body = api.get_json("/schema/api/auth/probe", params)
            if status != 200:
                raise RuntimeError(f"{user} {key_date} {test}: {status} {body.get('error', body)}")
            if body["user"] != user:
                raise RuntimeError(f"probed as {body['user']}, not {user}")
            if authorizations is None:
                authorizations = body["authorizations"]
            results.extend(compact(row) for row in body["results"])
            counts = {}
            for row in body["results"]:
                counts[row["status"]] = counts.get(row["status"], 0) + 1
            print(f"  {key_date} {test}: {counts}", flush=True)
    return authorizations, results


def cell_value(cell):
    """The value of a compact cell: members, value and, if BW gives one, {"status": ...}."""
    return cell[-2] if isinstance(cell[-1], dict) else cell[-1]


def xmla_answer(xmla, data_source, mdx):
    """BW's XMLA answer: (True, {ordinal: value}) or (False, the fault's description)."""
    body = SOAP.format('<Execute xmlns="urn:schemas-microsoft-com:xml-analysis"><Command><Statement>'
                       f'{escape(mdx)}</Statement></Command><Properties><PropertyList>'
                       f'<DataSourceInfo>{escape(data_source)}</DataSourceInfo><Catalog>$INFOCUBE</Catalog>'
                       '<Format>Multidimensional</Format><AxisFormat>TupleFormat</AxisFormat>'
                       '</PropertyList></Properties></Execute>')
    _, text = xmla.open("", body=body, headers={"Content-Type": "text/xml",
                                                "SOAPAction": '"urn:schemas-microsoft-com:xml-analysis:Execute"'})
    if "<faultstring>" in text:
        description = re.search(r'Description="([^"]*)"', text)
        return False, " ".join((description.group(1) if description else text[:200]).split())
    cells = {}
    for ordinal, value in re.findall(r'<Cell CellOrdinal="(\d+)">\s*<Value[^>]*>([^<]*)</Value>', text):
        if number(value) is not None:
            cells[int(ordinal)] = number(value)
    return True, cells


def verify(xmla, data_source, results, every):
    """Every N-th statement of 9999-12-31 through BW's XMLA as the user, compared with the probe's answer: the
    statements whose outcome or values differ, and the pairs of refusal messages that differ (probe, logged on) with
    their counts. A statement the logged-on user is refused gets loggedOn {"refused": message}, one whose answer
    differs loggedOn {"cells": {ordinal: value}} (the cells that are not empty)."""
    rows = [r for r in results if r.get("keyDate") == "9999-12-31" and r.get("mdx")][::every]
    failures, messages = [], {}
    for row in rows:
        answered, xmla_result = xmla_answer(xmla, data_source, row["mdx"])
        probe_answered = row["status"] in ANSWERED
        if not answered:
            row["loggedOn"] = {"refused": xmla_result}
        if answered != probe_answered:
            if answered:
                row["loggedOn"] = {"cells": xmla_result}
            failures.append((row, f"probe {row['status']} {row.get('message', '')}, logged on "
                                  f"{'answered' if answered else xmla_result}",
                             f"{row['status']} through the switch, "
                             f"{'answered' if answered else 'refused'} logged on"))
        elif answered:
            probe_cells = {i: value for i, value in enumerate(cell_value(cell) for cell in row["cells"])
                           if value is not None}
            if probe_cells != xmla_result:
                differ = sorted(i for i in set(probe_cells) | set(xmla_result)
                                if probe_cells.get(i) != xmla_result.get(i))
                row["loggedOn"] = {"cells": xmla_result}
                failures.append((row, f"values differ at {len(differ)} of {len(row['cells'])} cells: probe "
                                      f"{[(i, probe_cells.get(i)) for i in differ[:5]]}, logged on "
                                      f"{[(i, xmla_result.get(i)) for i in differ[:5]]}", "values differ"))
        else:
            message = row.get("message", "").split(": ", 2)[-1]
            if message != xmla_result:
                messages[(message, xmla_result)] = messages.get((message, xmla_result), 0) + 1
    return len(rows), failures, messages


def statement_key(row):
    """What a row asks, the key of its statement in statements.json."""
    return "|".join(str(row.get(name, "")) for name in KEY_FIELDS)


def write_statements(path, results):
    """Adds the statements of the rows to statements.json; a key that is there with another statement is an error
    (the probe's statements changed: record every scenario again)."""
    statements = {}
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            statements = json.load(f)
    for row in results:
        if row.get("mdx"):
            if statements.setdefault(statement_key(row), row["mdx"]) != row["mdx"]:
                raise RuntimeError(f"another statement for {statement_key(row)}: record every scenario again")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("{\n")
        f.write(",\n".join(f" {json.dumps(key)}: {json.dumps(mdx, ensure_ascii=False)}"
                           for key, mdx in sorted(statements.items())))
        f.write("\n}\n")


def write(path, document):
    """A scenario's file, a result per line, without the statements (statements.json has them)."""
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("{\n")
        for name in [k for k in document if k != "results"]:
            f.write(f" {json.dumps(name)}: {json.dumps(document[name], ensure_ascii=False)},\n")
        f.write(' "results": [\n')
        f.write(",\n".join("  " + json.dumps({k: v for k, v in r.items() if k != "mdx"}, ensure_ascii=False)
                           for r in document["results"]))
        f.write("\n ]\n}\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--scenario", action="append", help="a scenario name (FULL, EQ, ...); repeatable")
    parser.add_argument("--key-date", action="append", help="YYYY-MM-DD; repeatable")
    parser.add_argument("--verify", type=int, default=0, metavar="N",
                        help="compare every N-th statement of 9999-12-31 with a logon of the user (BW's XMLA)")
    parser.add_argument("--out", default=os.path.join(ROOT, "reference", "auth"))
    args = parser.parse_args()
    env = read_env()
    scheme = "https" if env.get("SAP_USE_SSL", "").lower() in ("true", "1", "yes") else "http"
    host = f"{scheme}://{env['SAP_ASHOST']}:{env['SAP_PORT']}"
    client = env.get("SAP_CLIENT", "001")
    key_dates = args.key_date or KEY_DATES
    if args.verify and not env.get("SAP_TEST_PASSWORD"):
        sys.exit("--verify needs SAP_TEST_PASSWORD in .env.sap")

    api = Session(f"{host}/zzxxmla1", client, env["SAP_USER"], env["SAP_PASSWORD"])
    status, body = api.get_json("/schema/api/auth/scenarios")
    if status != 200:
        sys.exit(f"auth/scenarios: {status} {body}")
    scenarios = [s for s in body["scenarios"] if not args.scenario or s["name"] in args.scenario]
    if args.scenario and len(scenarios) != len(set(args.scenario)):
        sys.exit(f"unknown scenario among {args.scenario}: {[s['name'] for s in body['scenarios']]}")
    os.makedirs(args.out, exist_ok=True)

    failed = 0
    try:
        for scenario in scenarios:
            print(f"{scenario['name']} ({scenario['user']})", flush=True)
            authorizations, results = probe(api, scenario["user"], key_dates)
            if args.verify:
                xmla = Session(f"{host}/sap/bw/xml/soap/xmla", client, scenario["user"], env["SAP_TEST_PASSWORD"])
                try:
                    _, text = xmla.open("", body=SOAP.format(
                        '<Discover xmlns="urn:schemas-microsoft-com:xml-analysis"><RequestType>'
                        'DISCOVER_DATASOURCES</RequestType><Restrictions/><Properties/></Discover>'),
                        headers={"Content-Type": "text/xml"})
                    data_source = re.search(r"<DataSourceInfo>([^<]*)</DataSourceInfo>", text).group(1)
                    count, failures, messages = verify(xmla, data_source, results, args.verify)
                finally:
                    xmla.logoff()
                print(f"  verified {count} statements logged on as {scenario['user']}: "
                      f"{'same outcome and values' if not failures else f'{len(failures)} differ'}", flush=True)
                kinds = {}
                for _, _, kind in failures:
                    kinds[kind] = kinds.get(kind, 0) + 1
                for kind, count in kinds.items():
                    print(f"    {kind}: {count}")
                for row, reason, _ in failures[:10]:
                    print(f"    {row['test']} {row.get('hierarchy', '')} {row.get('node', '')}: {reason}")
                for (probe_message, logged_on), count in messages.items():
                    print(f"    refused with another message ({count}): probe {probe_message!r}, "
                          f"logged on {logged_on!r}")
                # a statement BW answers empty through the switch and refuses logged on is a known difference
                failed += sum(1 for row, _, kind in failures if not (row["status"] == "EMPTY"
                                                                     and kind.endswith("refused logged on")))
            write_statements(os.path.join(args.out, "statements.json"), results)
            write(os.path.join(args.out, f"{scenario['name']}.json"),
                  {"scenario": scenario["name"], "user": scenario["user"], "description": scenario["description"],
                   "auths": scenario["auths"], "keyDates": key_dates, "authorizations": authorizations,
                   "verified": args.verify, "results": results})
    finally:
        api.logoff()
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
