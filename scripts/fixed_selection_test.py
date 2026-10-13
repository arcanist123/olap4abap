#!/usr/bin/env python3
"""Tests fixed selections (docs/bw-schema-design-guide.md, section 3.8) end to end on the clinic demo against SAP.

The clinic demo (docs/clinic-demo.md) books each visit under one of the fiscal year variants K1, K2 and K4 and
deploys, per provider (the cube ZCLVISIT, the aDSO ZCLVISITA), a plain catalog and one that fixes the variant to K4:
- the plain catalog is the oracle: the variant a dimension, the years and periods compounded with it (K1/2024001,
  ..., K4/2025012), the visits under [Fiscal Year Variant].[K4];
- the K4 catalog (ZCLVISIT_K4, ZCLVISITA_K4) has the variant as a dimension with the one member K4, its visits are
  those under K4, its years 2024 and 2025 and its periods 2024001 to 2025012 by their own key, and they add up to
  its visits.
Then the way of the schema builder's UI, the API: the plain proposal is fixed as an edit (POST fix, fixed.ZCLFISCVR=K4):
the cube is annotated olap4abap.fixed.ZCLFISCVR, keeps the dimension ZCLFISCVR and names the periods by their own key
(no COMPOUND_KEY), on the views filtered on K4 (the fact view, ZCLFISCVR, ZCLFISCYR and ZCLFISCPR: the demo's own,
which the provider read finds and accept reuses); accepted into a test catalog it has the K4 visits and the one
variant; fixing it again with nothing (un-fixing) gives the plain proposal's tables back; removing the catalog keeps
the filtered views, as the demo's K4 catalog names them. It changes the server: it writes and removes the catalog
ZZFIXTEST_<provider>, whose cube is named as the catalog (the demo's catalogs have the providers' names).

    python scripts/fixed_selection_test.py
    python scripts/fixed_selection_test.py --url http://localhost:50000/zzxxmla1 --client 001
"""
import argparse
import html
import json
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

EXECUTE = """<SOAP-ENV:Envelope xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/"><SOAP-ENV:Body>
<Execute xmlns="urn:schemas-microsoft-com:xml-analysis"><Command><Statement>{statement}</Statement></Command>
<Properties><PropertyList><DataSourceInfo>ABAP BW</DataSourceInfo><Catalog>{catalog}</Catalog>
<Format>Multidimensional</Format><AxisFormat>TupleFormat</AxisFormat><Content>Data</Content></PropertyList></Properties>
</Execute></SOAP-ENV:Body></SOAP-ENV:Envelope>"""

YEARS = ["2024", "2025"]
PERIODS = [f"{year}{month:03d}" for year in (2024, 2025) for month in range(1, 13)]
VARIANTS = ("K1", "K2", "K4")
# the demo cube's Time has no All member and defaults to 2025 (docs/clinic-demo.md); the aDSO's calendar has one
ALL_YEARS = {"ZCLVISIT": "{[Time].[2024], [Time].[2025]}", "ZCLVISITA": ""}


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


def execute(base, client, catalog, statement):
    """The answer's captions of Axis1 and its cell values, or the fault."""
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
        return None, None, html.unescape(found.group(1))
    axis = re.search(r'<Axis name="Axis1">(.*?)</Axis>', text, re.S)
    captions = [html.unescape(c) for c in re.findall(r"<Caption>([^<]*)</Caption>", axis.group(1))] if axis else []
    values = [html.unescape(v) for v in re.findall(r"<Value[^>]*>([^<]*)</Value>", text)]
    return captions, values, None


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--url", default="http://localhost:50000/zzxxmla1")
    parser.add_argument("--client", default="001")
    args = parser.parse_args()
    failures = []

    def check(name, condition, detail=""):
        print(f"{'ok  ' if condition else 'FAIL'} {name}{'' if condition else ': ' + str(detail)[:400]}")
        if not condition:
            failures.append(name)

    def run(catalog, statement):
        return execute(args.url, args.client, catalog, statement)

    for provider in ("ZCLVISIT", "ZCLVISITA"):
        years = ALL_YEARS[provider]
        where = f" WHERE {years}" if years else ""
        # the demo's plain catalog: the oracle
        _, values, error = run(provider, f"SELECT [Measures].[Visits] ON 0 FROM {provider} WHERE "
                                         + (f"{years} * {{[Fiscal Year Variant].[K4]}}" if years
                                            else "[Fiscal Year Variant].[K4]"))
        check(f"{provider}: the visits under K4", error is None and values, error)
        expected = float(values[0]) if values else None
        captions, _, error = run(provider, f"SELECT [Measures].[Visits] ON 0, "
                                           f"NON EMPTY [Fiscal Period].[Fiscal Period].Members ON 1 FROM {provider}{where}")
        check(f"{provider}: the periods compounded, K1/2024001 to K4/2025012",
              error is None and captions == [f"{v}/{p}" for v in VARIANTS for p in PERIODS],
              error or (captions or [])[:6])
        captions, _, error = run(provider, f"SELECT [Measures].[Visits] ON 0, "
                                           f"NON EMPTY [Fiscal Year].[Fiscal Year].Members ON 1 FROM {provider}{where}")
        check(f"{provider}: the years compounded, K1/2024 to K4/2025",
              error is None and captions == [f"{v}/{y}" for v in VARIANTS for y in YEARS], error or captions)
        if expected is None:
            continue

        # the demo's K4 catalog
        catalog = f"{provider}_K4"
        _, values, error = run(catalog, f"SELECT [Measures].[Visits] ON 0 FROM {catalog}{where}")
        check(f"{catalog}: the cube's visits are the K4 ones ({expected:.0f})",
              error is None and values and abs(float(values[0]) - expected) < 0.5, error or values)
        captions, values, error = run(catalog, f"SELECT [Measures].[Visits] ON 0, "
                                               f"NON EMPTY [Fiscal Period].[Fiscal Period].Members ON 1 FROM {catalog}{where}")
        check(f"{catalog}: periods by their own key, 2024001 to 2025012", error is None and captions == PERIODS,
              error or captions)
        check(f"{catalog}: the periods add up to the cube's visits",
              error is None and values and abs(sum(float(v) for v in values) - expected) < 0.5, values)
        captions, _, error = run(catalog, f"SELECT [Measures].[Visits] ON 0, "
                                          f"NON EMPTY [Fiscal Year].[Fiscal Year].Members ON 1 FROM {catalog}{where}")
        check(f"{catalog}: years by their own key", error is None and captions == YEARS, error or captions)
        captions, _, error = run(catalog, f"SELECT [Measures].[Visits] ON 0, "
                                          f"[Fiscal Year Variant].[Variant].Members ON 1 FROM {catalog}{where}")
        check(f"{catalog}: the variant has one member, K4", error is None and captions == ["K4"], error or captions)

        # the API, as the schema builder uses it: the plain proposal, fixed as an edit
        test = f"ZZFIXTEST_{provider}"
        status, proposal = api(args.url, args.client, "GET", "proposal", {"provider": provider})
        check(f"{test}: plain proposal", status == 200 and "olap4abap.fixed" not in proposal.get("xml", ""), proposal)
        if status != 200:
            continue
        plain = proposal["xml"]
        status, fixed = api(args.url, args.client, "POST", "fix", {"fixed.ZCLFISCVR": "K4"}, plain)
        check(f"{test}: fixed ZCLFISCVR=K4", status == 200, fixed)
        if status != 200:
            continue
        xml = fixed["xml"]
        check(f"{test}: the cube is annotated, the variant keeps its dimension",
              re.search(r'<Annotation name="olap4abap\.fixed\.ZCLFISCVR">\s*K4\s*</Annotation>', xml) is not None
              and re.search(r'<Dimension [^>]*name="ZCLFISCVR"', xml) is not None, xml[:400])
        period = re.search(r'<Dimension [^>]*name="ZCLFISCPR".*?</Dimension>', xml, re.S)
        check(f"{test}: ZCLFISCPR is not compounded", period is not None and "COMPOUND_KEY" not in period.group(0),
              period.group(0)[:400] if period else "no dimension ZCLFISCPR")
        listed = {c["name"]: c for c in fixed.get("characteristics", [])}
        check(f"{test}: the answer lists ZCLFISCVR fixed to K4, on its dimension",
              listed.get("ZCLFISCVR", {}).get("fixed") is True and listed["ZCLFISCVR"].get("value") == "K4"
              and listed["ZCLFISCVR"].get("dimension") == "ZCLFISCVR", fixed.get("characteristics"))
        # the views filtered on K4 exist (the demo's K4 catalog uses them), so the fixed schema names them
        tables = {}
        for name in (provider, catalog):
            _, schema = api(args.url, args.client, "GET", "schema", {"catalog": name})
            tables[name] = set(re.findall(r'(?:<Table name|table)="([^"]+)"', schema.get("xml", "")))
        filtered = tables[catalog] - tables[provider]
        named = set(re.findall(r'(?:<Table name|table)="([^"]+)"', xml))
        check(f"{test}: the fixed schema names the demo's views filtered on K4 (facts, variant, year, period)",
              len(filtered) == 4 and filtered <= named and "ZZXXMLA1_F_" not in xml and "ZZXXMLA1_C_" not in xml,
              {"filtered": filtered, "named": named})
        replaced = {(t["from"], t["to"]) for t in fixed.get("tables", [])}
        check(f"{test}: the answer lists the tables replaced", {t for _, t in replaced} == filtered, replaced)
        xml = xml.replace(f'<Cube name="{provider}"', f'<Cube name="{test}"', 1)
        status, accepted = api(args.url, args.client, "POST", "accept", {"catalog": test}, xml)
        check(f"{test}: accepted", status == 200, accepted)
        if status != 200:
            continue
        try:
            # the proposal's date has an All member
            _, values, error = run(test, f"SELECT [Measures].[ZCLVISNO] ON 0 FROM {test}")
            check(f"{test}: the cube's visits are the K4 ones ({expected:.0f})",
                  error is None and values and abs(float(values[0]) - expected) < 0.5, error or values)
            captions, _, error = run(test, f"SELECT [Measures].[ZCLVISNO] ON 0, "
                                           f"NON EMPTY [ZCLFISCPR].[ZCLFISCPR].Members ON 1 FROM {test}")
            check(f"{test}: periods by their own key, 2024001 to 2025012", error is None and captions == PERIODS,
                  error or captions)
            captions, _, error = run(test, f"SELECT [Measures].[ZCLVISNO] ON 0, "
                                           f"[ZCLFISCVR].[ZCLFISCVR].Members ON 1 FROM {test}")
            check(f"{test}: the variant has one member, K4", error is None and captions == ["K4"], error or captions)
            # un-fixing the accepted schema: the plain proposal's tables, the period compounded again
            status, unfixed = api(args.url, args.client, "POST", "fix", {}, accepted["xml"])
            plain_tables = set(re.findall(r'(?:<Table name|table)="([^"]+)"', plain))
            back = set(re.findall(r'(?:<Table name|table)="([^"]+)"', unfixed.get("xml", "")))
            period = re.search(r'<Dimension [^>]*name="ZCLFISCPR".*?</Dimension>', unfixed.get("xml", ""), re.S)
            check(f"{test}: un-fixed, the plain tables and the period compounded again",
                  status == 200 and back == plain_tables and "olap4abap.fixed" not in unfixed["xml"]
                  and period is not None and period.group(0).count("COMPOUND_KEY") == 2,
                  unfixed if status != 200 else {"back": back, "plain": plain_tables})
        finally:
            status, removed = api(args.url, args.client, "POST", "remove", {"catalog": test})
            check(f"{test}: removed", status == 200, removed)
            deleted = [html.unescape(v) for v in removed.get("deletedViews", [])]
            check(f"{test}: the views of the selection stay, {catalog} names them",
                  not set(filtered) & set(deleted), {"deleted": deleted, "filtered": filtered})

    print(f"\n{len(failures)} failure(s)" if failures else "\nall passed")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
