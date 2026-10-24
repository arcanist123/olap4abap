#!/usr/bin/env python3
"""Measures query planning on SAP (docs/query-planning.md, Verification): switches the trace on for the endpoint's user,
sends each statement a few times and prints, per run, the runtime and the SQL statements with their time as the trace
recorded them (ZZXXMLA1_TRACE: runtime_ms, sql_count, sql_ms), then the best run, and the best wall time of the client
(request sent to response read: also what the trace's runtime leaves out, sending the answer). The statements:

    filter_list  Excel's filter list of Store on ZFOODMART (the statement of query-planning.md)
    pivot        an Excel pivot on ZFOODMART: products drilled to Drink's children by customer countries, Store Cost
    time_1998    a NON EMPTY axis with [Time].[1998] on the other axis (the axis is filtered in the default Time, 1997)
    wide_grid    Excel's 1,001 x 1,001 grid on ZXMLWIDEA (two levels of 1,000 members with their All members)
    filter, filter_wide, non_empty
                 Filter on a stored measure of FoodMart's customers and of ZXMLAD00's 100,000 members, NonEmpty of
                 the customers with a second set (step 6); each *_evaluated the same answer by the evaluator
    properties_axis
                 Excel's crossjoin of Diagnosis and Patient on COLUMNS of ZCLVISITA with PARENT_UNIQUE_NAME and the
                 24 member properties of both (docs/next-steps.md, Later: a large axis with member properties)

    python scripts/planning_measure.py                       # every statement, 3 runs each
    python scripts/planning_measure.py --case pivot --runs 5
"""
import argparse
import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import sap_auth

AGENT = "olap4abap planning_measure"
SOAP = ('<SOAP-ENV:Envelope xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/"><SOAP-ENV:Body>'
        '<Execute xmlns="urn:schemas-microsoft-com:xml-analysis"><Command><Statement>{}</Statement></Command>'
        '<Properties><PropertyList><Catalog>{}</Catalog><Format>Multidimensional</Format></PropertyList></Properties>'
        '</Execute></SOAP-ENV:Body></SOAP-ENV:Envelope>')
EXCEL_CELLS = "CELL PROPERTIES VALUE, FORMAT_STRING, LANGUAGE, BACK_COLOR, FORE_COLOR, FONT_FLAGS"

# the member properties of Patient and Diagnosis in the clinic demo, as Excel asks for them
PATIENT_DIAGNOSIS_PROPERTIES = [
    "[ZCLPAT].[ZCLPAT].[Text]",
    "[ZCLPAT].[ZCLPAT].[ZCLPNAME]",
    "[ZCLPAT].[ZCLPAT].[ZCLPNAME Text]",
    "[ZCLPAT].[ZCLPAT].[ZCLSEX]",
    "[ZCLPAT].[ZCLPAT].[ZCLSEX Text]",
    "[ZCLPAT].[ZCLPAT].[ZCLBYEAR]",
    "[ZCLPAT].[ZCLPAT].[ZCLBYEAR Text]",
    "[ZCLPAT].[ZCLPAT].[ZCLAGEGR]",
    "[ZCLPAT].[ZCLPAT].[ZCLAGEGR Text]",
    "[ZCLPAT].[ZCLPAT].[ZCLBLOOD]",
    "[ZCLPAT].[ZCLPAT].[ZCLBLOOD Text]",
    "[ZCLPAT].[ZCLPAT].[ZCLINSUR]",
    "[ZCLPAT].[ZCLPAT].[ZCLINSUR Text]",
    "[ZCLPAT].[ZCLPAT].[ZCLCITY]",
    "[ZCLPAT].[ZCLPAT].[ZCLCITY Text]",
    "[ZCLPAT].[ZCLPAT].[ZCLREGIO]",
    "[ZCLPAT].[ZCLPAT].[ZCLREGIO Text]",
    "[ZCLDIAG].[ZCLDIAG].[Text]",
    "[ZCLDIAG].[ZCLDIAG].[ZCLDTEXT]",
    "[ZCLDIAG].[ZCLDIAG].[ZCLDTEXT Text]",
    "[ZCLDIAG].[ZCLDIAG].[ZCLDGRP]",
    "[ZCLDIAG].[ZCLDIAG].[ZCLDGRP Text]",
    "[ZCLDIAG].[ZCLDIAG].[ZCLDCHAP]",
    "[ZCLDIAG].[ZCLDIAG].[ZCLDCHAP Text]",
]

# name -> (catalog, statement)
CASES = {
    "filter_list": ("ZFOODMART",
                    "SELECT NON EMPTY Hierarchize({DrilldownLevel({[Store].[All Stores]},,,INCLUDE_CALC_MEMBERS)}) "
                    "DIMENSION PROPERTIES PARENT_UNIQUE_NAME ON COLUMNS FROM [ZFMSALES] " + EXCEL_CELLS),
    "pivot": ("ZFOODMART",
              "SELECT NON EMPTY Hierarchize(DrilldownMember({{DrilldownLevel({[Product].[All Products]},,,"
              "INCLUDE_CALC_MEMBERS)}}, {[Product].[Drink]},,,INCLUDE_CALC_MEMBERS)) DIMENSION PROPERTIES "
              "PARENT_UNIQUE_NAME ON COLUMNS, NON EMPTY Hierarchize({DrilldownLevel({[Customers].[All Customers]},,,"
              "INCLUDE_CALC_MEMBERS)}) DIMENSION PROPERTIES PARENT_UNIQUE_NAME ON ROWS FROM [ZFMSALES] "
              "WHERE ([Measures].[Store Cost]) " + EXCEL_CELLS),
    "time_1998": ("ZFOODMART",
                  "SELECT NON EMPTY {[Store].[Store State].Members} ON COLUMNS, {[Time].[1998]} ON ROWS "
                  "FROM [ZFMSALES]"),
    "wide_grid": ("ZXMLWIDEA",
                  "SELECT NON EMPTY Hierarchize({DrilldownLevel({[ZXMLAD01].[All Dimension 01]},,,INCLUDE_CALC_MEMBERS)}) "
                  "DIMENSION PROPERTIES PARENT_UNIQUE_NAME ON COLUMNS, NON EMPTY Hierarchize({DrilldownLevel("
                  "{[ZXMLAD02].[All Dimension 02]},,,INCLUDE_CALC_MEMBERS)}) DIMENSION PROPERTIES PARENT_UNIQUE_NAME "
                  "ON ROWS FROM [ZXMLWIDEA] " + EXCEL_CELLS),
    # step 6: Filter on a stored measure (native, one statement) and the same with NOT NOT (the evaluator per tuple)
    "filter": ("ZFOODMART",
               "SELECT {[Measures].[Unit Sales]} ON COLUMNS, Filter([Customers].[Name].Members, "
               "[Measures].[Unit Sales] > 300) ON ROWS FROM [ZFMSALES]"),
    "filter_evaluated": ("ZFOODMART",
                         "SELECT {[Measures].[Unit Sales]} ON COLUMNS, Filter([Customers].[Name].Members, "
                         "NOT (NOT ([Measures].[Unit Sales] > 300))) ON ROWS FROM [ZFMSALES]"),
    "filter_wide": ("ZXMLWIDEA",
                    "SELECT {[Measures].[ZXMLAKF]} ON COLUMNS, Filter([ZXMLAD00].[All Dimension 00].Children, "
                    "[Measures].[ZXMLAKF] > 7000) ON ROWS FROM [ZXMLWIDEA]"),
    "filter_wide_evaluated": ("ZXMLWIDEA",
                              "SELECT {[Measures].[ZXMLAKF]} ON COLUMNS, Filter([ZXMLAD00].[All Dimension 00].Children, "
                              "NOT (NOT ([Measures].[ZXMLAKF] > 7000))) ON ROWS FROM [ZXMLWIDEA]"),
    # step 6: NonEmpty with a second set by groups, and the same with a calculated measure (the evaluator)
    "non_empty": ("ZFOODMART",
                  "WITH MEMBER [Measures].[U] AS [Measures].[Unit Sales] SELECT {[Measures].[Unit Sales]} ON COLUMNS, "
                  "NonEmpty([Customers].[Name].Members, {([Product].[Drink].[Dairy], [Measures].[Unit Sales])}) "
                  "ON ROWS FROM [ZFMSALES]"),
    "non_empty_evaluated": ("ZFOODMART",
                            "WITH MEMBER [Measures].[U] AS [Measures].[Unit Sales] SELECT {[Measures].[Unit Sales]} "
                            "ON COLUMNS, NonEmpty([Customers].[Name].Members, {([Product].[Drink].[Dairy], "
                            "[Measures].[U])}) ON ROWS FROM [ZFMSALES]"),
    "properties_axis": ("ZCLVISITA",
                        "SELECT NON EMPTY CrossJoin(Hierarchize({DrilldownLevel({[ZCLDIAG].[All Diagnosis]},,,"
                        "INCLUDE_CALC_MEMBERS)}), Hierarchize({DrilldownLevel({[ZCLPAT].[All Patient]},,,"
                        "INCLUDE_CALC_MEMBERS)})) DIMENSION PROPERTIES PARENT_UNIQUE_NAME, "
                        + ", ".join(PATIENT_DIAGNOSIS_PROPERTIES) + " ON COLUMNS FROM [ZCLVISITA] " + EXCEL_CELLS),
}


def http(method, url, body=None):
    request = urllib.request.Request(url, method=method, data=body.encode("utf-8") if body is not None else None,
                                     headers={"Content-Type": "text/xml; charset=utf-8", "User-Agent": AGENT})
    try:
        with urllib.request.urlopen(request, timeout=600) as response:
            return response.status, response.read().decode("utf-8"), response.headers.get("Content-Type", "")
    except urllib.error.HTTPError as error:
        return error.code, error.read().decode("utf-8"), error.headers.get("Content-Type", "")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--url", default="http://localhost:50000/zzxxmla1")
    parser.add_argument("--client", default="001")
    parser.add_argument("--case", nargs="*", choices=sorted(CASES), help="the statements (default: all)")
    parser.add_argument("--runs", type=int, default=3)
    args = parser.parse_args()
    sap_auth.install()

    def api(http_method, resource, **params):
        query = urllib.parse.urlencode({"sap-client": args.client, **params})
        status, text, content_type = http(http_method, f"{args.url}/schema/api/{resource}?{query}")
        if status != 200:
            sys.exit(f"{http_method} {resource}: {status} {text[:300]}")
        return json.loads(text)

    user = api("GET", "trace")["user"]
    api("POST", "trace/on", user=user)
    xmla = f"{args.url}?sap-client={args.client}"
    for name in args.case or CASES:
        catalog, statement = CASES[name]
        known = {c["id"] for c in api("GET", "trace", filter=user, method="execute", max="50")["calls"]}
        walls = []
        for _ in range(args.runs):
            escaped = statement.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
            started = time.perf_counter()
            status, text, _ = http("POST", xmla, SOAP.format(escaped, catalog))
            walls.append(round((time.perf_counter() - started) * 1000))
            if status != 200 or "Fault>" in text:
                sys.exit(f"{name}: {status} {text[:500]}")
        calls = [c for c in api("GET", "trace", filter=user, method="execute", max="50")["calls"]
                 if c["id"] not in known and c["userAgent"] == AGENT]
        calls.reverse()
        runs = ", ".join(f"{c['runtimeMs']} ms ({c.get('sqlCount', '?')} SQL, {c.get('sqlMs', '?')} ms)"
                         for c in calls)
        best = min(calls, key=lambda c: c["runtimeMs"])
        print(f"{name:12} best {best['runtimeMs']:>6} ms, {best.get('sqlCount', '?')} SQL "
              f"{best.get('sqlMs', '?')} ms, {best['responseLength']:,} characters, wall best {min(walls):,} ms"
              f"   runs: {runs}; wall: {', '.join(f'{w:,} ms' for w in walls)}")


if __name__ == "__main__":
    main()
