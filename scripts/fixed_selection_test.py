#!/usr/bin/env python3
"""Tests fixed selections (docs/bw-schema-design-guide.md, section 3.8) end to end on the clinic demo against SAP:
for the cube ZCLVISIT and the aDSO ZCLVISITA, a schema proposed with the fiscal year variant fixed to K4
(GET proposal?fixed.ZCLFISCVR=K4) is accepted into a test catalog, queried and removed again.

The clinic demo (docs/clinic-demo.md) books each visit under one of K1, K2 and K4. The oracle is the plain proposal,
accepted first: the variant a dimension, the periods compounded with it (K1/2024001, ..., K4/2025012), the visits
under [ZCLFISCVR].[K4]. With K4 fixed
- the proposal has no dimension ZCLFISCVR, annotates the cube olap4abap.fixed.ZCLFISCVR and names the periods of
  ZCLFISCPR by their own key (no COMPOUND_KEY), on a fact view filtered on K4;
- accept generates the filtered views (selection ZCLFISCVR=K4: the fact view, ZCLFISCPR, ZCLFISCYR);
- the cube's visits are those under K4, its periods 2024001 to 2025012, no other;
- remove deletes the catalog and the filtered views (deletedViews), the plain views stay.
It changes the server: it writes and removes the catalogs ZZPLAIN_<provider> and ZZFIXTEST_<provider>, whose cubes
are named as the catalogs (the demo's catalogs have the providers' names).

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

PERIODS = [f"{year}{month:03d}" for year in (2024, 2025) for month in range(1, 13)]


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

    def accept(provider, catalog, params):
        """Proposes, accepts into the catalog with the cube named as the catalog (another catalog has the provider's
        name); returns the proposal and the answer of accept, None if one failed."""
        status, proposal = api(args.url, args.client, "GET", "proposal", {"provider": provider, **params})
        check(f"{catalog}: proposal {params}", status == 200, proposal)
        if status != 200:
            return proposal, None
        xml = proposal["xml"].replace(f'<Cube name="{provider}"', f'<Cube name="{catalog}"', 1)
        status, accepted = api(args.url, args.client, "POST", "accept", {"catalog": catalog}, xml)
        check(f"{catalog}: accepted", status == 200, accepted)
        return proposal, accepted if status == 200 else None

    def remove(catalog):
        status, removed = api(args.url, args.client, "POST", "remove", {"catalog": catalog})
        check(f"{catalog}: removed", status == 200, removed)
        return [html.unescape(v) for v in removed.get("deletedViews", [])]

    for provider in ("ZCLVISIT", "ZCLVISITA"):
        # the oracle: the plain proposal, the variant a dimension and the periods compounded with it
        plain = f"ZZPLAIN_{provider}"
        _, accepted = accept(provider, plain, {})
        expected = None
        if accepted:
            try:
                _, values, error = execute(args.url, args.client, plain,
                                           f"SELECT [Measures].[ZCLVISNO] ON 0 FROM {plain} WHERE [ZCLFISCVR].[K4]")
                check(f"{plain}: the visits under K4", error is None and values, error)
                expected = float(values[0]) if values else None
                captions, _, error = execute(
                    args.url, args.client, plain,
                    f"SELECT [Measures].[ZCLVISNO] ON 0, NON EMPTY [ZCLFISCPR].[ZCLFISCPR].Members ON 1 FROM {plain}")
                check(f"{plain}: the periods compounded, K1/2024001 to K4/2025012",
                      error is None and captions == [f"{v}/{p}" for v in ("K1", "K2", "K4") for p in PERIODS],
                      error or (captions or [])[:6])
            finally:
                remove(plain)
        if expected is None:
            continue

        catalog = f"ZZFIXTEST_{provider}"
        proposal, accepted = accept(provider, catalog, {"fixed.ZCLFISCVR": "K4"})
        xml = proposal.get("xml", "")
        check(f"{catalog}: the cube is annotated, the variant has no dimension",
              re.search(r'<Annotation name="olap4abap\.fixed\.ZCLFISCVR">\s*K4\s*</Annotation>', xml) is not None
              and re.search(r'<Dimension [^>]*name="ZCLFISCVR"', xml) is None, xml[:400])
        period = re.search(r'<Dimension [^>]*name="ZCLFISCPR".*?</Dimension>', xml, re.S)
        check(f"{catalog}: ZCLFISCPR is not compounded", period is not None and "COMPOUND_KEY" not in period.group(0),
              period.group(0)[:400] if period else "no dimension ZCLFISCPR")
        check(f"{catalog}: the proposal lists the fixed characteristic",
              proposal.get("provider", {}).get("fixed") == [{"characteristic": "ZCLFISCVR", "value": "K4"}],
              proposal.get("provider", {}).get("fixed"))
        if not accepted:
            continue
        filtered = [v["viewName"] for v in accepted.get("views", []) if v.get("selection") == "ZCLFISCVR=K4"]
        check(f"{catalog}: the views of the selection: the fact view, ZCLFISCPR and ZCLFISCYR",
              len(filtered) == 3, accepted.get("views"))
        try:
            _, values, error = execute(args.url, args.client, catalog,
                                       f"SELECT [Measures].[ZCLVISNO] ON 0 FROM {catalog}")
            check(f"{catalog}: the cube's visits are the K4 ones ({expected:.0f})",
                  error is None and values and abs(float(values[0]) - expected) < 0.5, error or values)
            captions, values, error = execute(
                args.url, args.client, catalog,
                f"SELECT [Measures].[ZCLVISNO] ON 0, NON EMPTY [ZCLFISCPR].[ZCLFISCPR].Members ON 1 FROM {catalog}")
            check(f"{catalog}: periods by their own key, 2024001 to 2025012", error is None and captions == PERIODS,
                  error or captions)
            check(f"{catalog}: the periods add up to the cube's visits",
                  error is None and values and abs(sum(float(v) for v in values) - expected) < 0.5, values)
        finally:
            deleted = remove(catalog)
            check(f"{catalog}: the views of the selection are deleted", set(filtered) <= set(deleted),
                  {"deleted": deleted, "generated": filtered})

    print(f"\n{len(failures)} failure(s)" if failures else "\nall passed")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
