#!/usr/bin/env python3
"""Tests the fiscal defaults of a proposal (ZZXXMLA1_CL_SCHEMA_DEFAULTS, docs/bw-schema-design-guide.md, section 3.8,
fiscal time) end to end against SAP, on BW's technical content cube 0TSC0T001, which has 0FISCVARNT, 0FISCYEAR and
0FISCPER (no facts are needed: the members come from the views):
- the proposal fixes the fiscal year variant to K4 (olap4abap.filter.0FISCVARNT = I EQ 'K4'), restricts the members
  of year and period to BW's interval of RSRHIERARCHYVIRT (GET time) and the period's to the regular periods
  (olap4abap.members.0FISCYEAR = I BT '1995' '2029', olap4abap.members.0FISCPER = I BT '1995010' '2029012' without
  E CP '*000', '*013' ... '*016'), names year and period by their own keys and makes both time dimensions (TimeYears,
  TimeMonths), without members with facts;
- accepted into a test catalog, the period has the twelve regular periods of every fiscal year of the interval with a
  SID (no 000, no 013 to 016, which BW's SID table holds), so Lag(1) of 2025001 is 2024012 and Lag(12) is 2024001;
  the year has the fiscal years of the interval. The fiscal time master data must be filled (time.html, POST time/fill?characteristics=0FISCYEAR,
  0FISCPER; docs/time-master-data.md): every year of BW's interval then has its periods.
It changes the server: it writes and removes the catalog ZZFISCTEST, whose cube is named as the catalog.

    python scripts/fiscal_default_test.py
    python scripts/fiscal_default_test.py --url http://localhost:50000/zzxxmla1 --client 001
"""
import argparse
import html
import json
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

import sap_auth

EXECUTE = """<SOAP-ENV:Envelope xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/"><SOAP-ENV:Body>
<Execute xmlns="urn:schemas-microsoft-com:xml-analysis"><Command><Statement>{statement}</Statement></Command>
<Properties><PropertyList><DataSourceInfo>ABAP BW</DataSourceInfo><Catalog>{catalog}</Catalog>
<Format>Multidimensional</Format><AxisFormat>TupleFormat</AxisFormat><Content>Data</Content></PropertyList></Properties>
</Execute></SOAP-ENV:Body></SOAP-ENV:Envelope>"""

PROVIDER = "0TSC0T001"
TEST = "ZZFISCTEST"
QUOTE = r"(?:\x27|&apos;|&#39;)"


def api(base, client, method, resource, params=None, body=None):
    query = urllib.parse.urlencode({"sap-client": client, **(params or {})})
    request = urllib.request.Request(f"{base}/schema/api/{resource}?{query}", method=method,
                                     data=body.encode("utf-8") if body is not None else None,
                                     headers={"Content-Type": "application/xml; charset=utf-8"})
    try:
        with urllib.request.urlopen(request, timeout=600) as response:
            return response.status, json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        return error.code, json.loads(error.read().decode("utf-8"))


def captions(base, client, catalog, statement):
    """The names of the members of Axis1 (from their unique names; the captions are texts), or the fault."""
    request = urllib.request.Request(
        f"{base}?sap-client={client}",
        data=EXECUTE.format(statement=html.escape(statement, quote=False), catalog=catalog).encode("utf-8"),
        headers={"Content-Type": "text/xml; charset=utf-8",
                 "SOAPAction": '"urn:schemas-microsoft-com:xml-analysis:Execute"'})
    try:
        with urllib.request.urlopen(request, timeout=600) as response:
            text = response.read().decode("utf-8")
    except urllib.error.HTTPError as error:
        text = error.read().decode("utf-8", "replace")
    found = re.search(r"<faultstring>(.*?)</faultstring>", text, re.S)
    if found:
        return None, html.unescape(found.group(1))
    axis = re.search(r'<Axis name="Axis1">(.*?)</Axis>', text, re.S)
    return [html.unescape(c) for c in re.findall(r"<UName>[^<]*\.\[([^<\]]*)\]</UName>", axis.group(1))] if axis else [], None


def dimension(xml, name):
    found = re.search(rf'<Dimension [^>]*name="{name}"[^>]*>.*?</Dimension>', xml, re.S)
    return found.group(0) if found else ""


def usage(xml, name):
    found = re.search(rf'<DimensionUsage [^>]*name="{name}"[^>]*>.*?</DimensionUsage>', xml, re.S)
    return found.group(0) if found else ""


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--url", default="http://localhost:50000/zzxxmla1")
    parser.add_argument("--client", default="001")
    args = parser.parse_args()
    sap_auth.install()
    failures = []

    def check(name, condition, detail=""):
        print(f"{'ok  ' if condition else 'FAIL'} {name}{'' if condition else ': ' + str(detail)[:400]}")
        if not condition:
            failures.append(name)

    status, proposal = api(args.url, args.client, "GET", "proposal", {"provider": PROVIDER})
    check(f"{PROVIDER}: proposed", status == 200, proposal)
    if status != 200:
        sys.exit(1)
    xml = proposal["xml"]
    check("the variant is fixed to K4 (filter the cube)",
          re.search(rf'<Annotation name="olap4abap\.filter\.0FISCVARNT">\s*I EQ {QUOTE}K4{QUOTE}\s*</Annotation>', xml)
          is not None, xml[:600])
    status, time = api(args.url, args.client, "GET", "time")
    check("BW's interval is read", status == 200, time)
    first, last = (time["from"][:4], time["from"][5:7]), (time["to"][:4], time["to"][5:7])
    members = re.search(r'<Annotation name="olap4abap\.members\.0FISCPER">([^<]*)</Annotation>', xml)
    rows = html.unescape(members.group(1)).strip().replace("'", "") if members else "no annotation"
    check("the period's members are restricted to the regular periods of BW's interval",
          rows == f"E CP *000;E CP *013;E CP *014;E CP *015;E CP *016;"
                  f"I BT {first[0]}0{first[1]} {last[0]}0{last[1]}", rows)
    members = re.search(r'<Annotation name="olap4abap\.members\.0FISCYEAR">([^<]*)</Annotation>', xml)
    rows = html.unescape(members.group(1)).strip().replace("'", "") if members else "no annotation"
    check("the year's members are restricted to BW's interval", rows == f"I BT {first[0]} {last[0]}", rows)
    # the regular periods of the interval: its months
    months = (int(last[0]) - int(first[0])) * 12 + int(last[1]) - int(first[1]) + 1
    for name, level_type in (("0FISCPER", "TimeMonths"), ("0FISCYEAR", "TimeYears")):
        dim = dimension(xml, name)
        level = re.search(r'<Level [^>]*>', dim)
        check(f"{name} is a time dimension, its level {level_type}",
              'type="TimeDimension"' in dim and level is not None and f'levelType="{level_type}"' in level.group(0),
              dim[:600])
        check(f"{name} is named by its own key (not compounded under K4)", "COMPOUND_KEY" not in dim, dim[:600])
        check(f"{name}: its usage shows all members (no members with facts on time)",
              usage(xml, name) and "membersWithFacts" not in usage(xml, name), usage(xml, name))
    check("the variant is no time dimension, with members with facts",
          'type="TimeDimension"' not in dimension(xml, "0FISCVARNT") and "membersWithFacts" in usage(xml, "0FISCVARNT"))
    notes = {n["iobjnm"]: n["reason"] for n in proposal.get("notes", [])}
    check("the notes say what the defaults did", "K4" in notes.get("0FISCVARNT", "")
          and "regular periods" in notes.get("0FISCPER", "")
          and all("RSRHIERARCHYVIRT" in notes.get(n, "") for n in ("0FISCPER", "0FISCYEAR")), notes)
    listed = {c["name"]: c for c in proposal.get("characteristics", [])}
    check("the characteristics list K4 fixed and the period restricted",
          listed.get("0FISCVARNT", {}).get("value") == "K4" and listed.get("0FISCPER", {}).get("mode") == "members",
          {k: listed.get(k) for k in ("0FISCVARNT", "0FISCPER")})

    xml = xml.replace(f'<Cube name="{PROVIDER}"', f'<Cube name="{TEST}"', 1)
    status, accepted = api(args.url, args.client, "POST", "accept", {"catalog": TEST}, xml)
    check(f"{TEST}: accepted", status == 200, accepted)
    if status == 200:
        try:
            periods, error = captions(args.url, args.client, TEST,
                                      f"SELECT {{}} ON 0, [0FISCPER].[0FISCPER].Members ON 1 FROM [{TEST}]")
            check("the periods are the regular ones of the interval, every month a period",
                  error is None and periods and len(periods) == months
                  and all(1 <= int(p[-3:]) <= 12 for p in periods)
                  and all(f"2024{p:03d}" in periods and f"2025{p:03d}" in periods for p in range(1, 13)),
                  error or [p for p in periods if not 1 <= int(p[-3:]) <= 12][:10] or len(periods))
            years, error = captions(args.url, args.client, TEST,
                                    f"SELECT {{}} ON 0, [0FISCYEAR].[0FISCYEAR].Members ON 1 FROM [{TEST}]")
            check("the years are the fiscal years of the interval",
                  error is None and years and "2024" in years and len(years) == int(last[0]) - int(first[0]) + 1
                  and min(years) >= first[0] and max(years) <= last[0],
                  error or (len(years), len(periods or []), years[:1], years[-1:]))
            for statement, expected in (("[0FISCPER].[2025001].Lag(1)", ["2024012"]),
                                        ("[0FISCPER].[2025001].Lag(12)", ["2024001"]),
                                        ("[0FISCPER].[2024012].Lead(1)", ["2025001"])):
                found, error = captions(args.url, args.client, TEST,
                                        f"SELECT {{}} ON 0, {{{statement}}} ON 1 FROM [{TEST}]")
                check(f"{statement} is {expected[0]}: the special periods are no members",
                      error is None and found == expected, error or found)
        finally:
            status, removed = api(args.url, args.client, "POST", "remove", {"catalog": TEST})
            check(f"{TEST}: removed", status == 200, removed)

    print(f"\n{len(failures)} failure(s)" if failures else "\nall passed")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
