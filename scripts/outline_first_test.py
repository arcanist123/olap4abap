#!/usr/bin/env python3
"""Tests cells first of outlines (ZZXXMLA1_CL_MDX_ENGINE=>outline_first, docs/query-planning.md, Cells first of an
outline) on the clinic demo against SAP: Excel's expanded members of BW hierarchies on both axes, crossjoined with
other outlines and characteristics, under slicers of several dimensions, compound slicers and subselects. Each
statement is asked twice: as given, and with an unused named set (WITH SET), which keeps a query off cells first, so
the per-function path answers it. Both answers must be the same (but for their timestamps), and the statement must
take the path it is meant to: its cells and axes one statement of phase "Cells first", or the per-function path
where a subselect restricts a BW hierarchy of an axis (restrict_to_subcube). Both catalogs of the demo are asked:
ZCLVISITA (an aDSO, the facts keyed by the value) and ZCLVISIT (an InfoCube, keyed by the SID). The calls are traced
with the header X-olap4abap-Trace (the MDX console's).

    python scripts/outline_first_test.py
    python scripts/outline_first_test.py --catalog ZCLVISITA --show
"""
import argparse
import collections
import json
import re
import sys
import urllib.request

import sap_auth

SOAP = ('<SOAP-ENV:Envelope xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/"><SOAP-ENV:Body>'
        '<Execute xmlns="urn:schemas-microsoft-com:xml-analysis"><Command><Statement>{}</Statement></Command>'
        '<Properties><PropertyList><Catalog>{}</Catalog><Format>Multidimensional</Format></PropertyList></Properties>'
        '</Execute></SOAP-ENV:Body></SOAP-ENV:Envelope>')
EXCEL_CELLS = " CELL PROPERTIES VALUE, FORMAT_STRING, LANGUAGE, BACK_COLOR, FORE_COLOR, FONT_FLAGS"
PROPERTIES = " DIMENSION PROPERTIES PARENT_UNIQUE_NAME"


def outline(all_member, *expanded):
    """Excel's expanded members: DrilldownMember nested down to DrilldownLevel of the All member, in Hierarchize."""
    hierarchy = all_member[:all_member.index("].") + 1]
    current = f"{{DrilldownLevel({{{hierarchy}.[{all_member[len(hierarchy) + 2:-1]}]}},,,INCLUDE_CALC_MEMBERS)}}"
    for members in expanded:
        current = f"{{DrilldownMember({{{current}}}, {{{members}}},,,INCLUDE_CALC_MEMBERS)}}"
    return f"Hierarchize({current[1:-1]})"


def level(all_member):
    return f"Hierarchize({{DrilldownLevel({{{all_member}}},,,INCLUDE_CALC_MEMBERS)}})"


DIAG = "[ZCLDIAG.ZCLDIAG_ICD].[All Diagnoses by ICD-10 Chapter]"
DIAG_1 = "[ZCLDIAG.ZCLDIAG_ICD].[Level 01].&[0HIER_NODE]&[DIAGNOSES]"
DIAG_2 = "[ZCLDIAG.ZCLDIAG_ICD].[Level 02].&[0HIER_NODE]&[DIAGNOSES]&[0HIER_NODE]&[ENDOCRINE_AND_METABOLIC]"
ORG = "[ZCLDOC.ZCLDOC_ORG_001].[All Clinic Organization]"
ORG_1 = "[ZCLDOC.ZCLDOC_ORG_001].[Level 01].&[0HIER_NODE]&[CLINIC]"
ORG_2 = "[ZCLDOC.ZCLDOC_ORG_001].[Level 02].&[0HIER_NODE]&[CLINIC]&[0HIER_NODE]&[PRIMARY]"
PRG = "[ZCLPAT.ZCLPAT_PRG].[All Care Programs]"
PRG_1 = "[ZCLPAT.ZCLPAT_PRG].[Level 01].&[0HIER_NODE]&[PROGRAMS]"
PRG_CHRONIC = "[ZCLPAT.ZCLPAT_PRG].[Level 02].&[0HIER_NODE]&[PROGRAMS]&[0HIER_NODE]&[CHRONIC]"
CONSULT = "[ZCLSERV.ZCLSERV_CAT].[Level 02].&[0HIER_NODE]&[SERVICES]&[0HIER_NODE]&[CONSULT]"
THERAPY = "[ZCLSERV.ZCLSERV_CAT].[Level 02].&[0HIER_NODE]&[SERVICES]&[0HIER_NODE]&[THERAPY]"
VTYPE = "[ZCLVTYPE].[All Visit Type]"
SITE = "[ZCLSITE].[All Site]"
SITES = "[ZCLDOC.ZCLDOC_SITE_001].[All Clinic Sites]"


def select(columns, rows=None, where="([Measures].[ZCLVISNO])", cube="{cube}"):
    axes = f"NON EMPTY {columns}{PROPERTIES} ON COLUMNS"
    if rows:
        axes += f", NON EMPTY {rows}{PROPERTIES} ON ROWS"
    return f"SELECT {axes} FROM {cube} WHERE {where}{EXCEL_CELLS}"


def subselect(members):
    return f"(SELECT ({{{members}}}) ON COLUMNS FROM {{cube}})"


# name -> (statement with {cube}, cells first)
CASES = {
    "two_outlines": (select(outline(DIAG, DIAG_1, DIAG_2), outline(ORG, ORG_1, ORG_2), f"({CONSULT}, [Measures].[ZCLVISNO])"), True),
    "outline_crossjoin": (select(f"CrossJoin({outline(DIAG, DIAG_1)}, {level(VTYPE)})", outline(ORG, ORG_1, ORG_2),
                                 f"({CONSULT}, [Measures].[ZCLVISNO])"), True),
    "three_outlines": (select(f"CrossJoin({outline(DIAG, DIAG_1)}, {outline(PRG, PRG_1)})",
                              f"CrossJoin({level(VTYPE)}, {outline(ORG, ORG_1)})"), True),
    "compound_slicer": (select(outline(DIAG, DIAG_1), f"CrossJoin({outline(ORG, ORG_1)}, {level(SITE)})",
                               "{[ZCLVTYPE].[Emergency], [ZCLVTYPE].[Outpatient]}"), True),
    "compound_slicer_bw": (select(outline(DIAG, DIAG_1), f"CrossJoin({level(VTYPE)}, {outline(ORG, ORG_1)})",
                                  f"CrossJoin({{{CONSULT}, {THERAPY}}}, {{[Measures].[ZCLVISNO]}})"), True),
    "subselect": (select(outline(DIAG, DIAG_1), outline(ORG, ORG_1),
                         cube=subselect("[ZCLVTYPE].[Emergency], [ZCLVTYPE].[Outpatient]")), True),
    "subselect_bw": (select(outline(DIAG, DIAG_1), f"CrossJoin({outline(ORG, ORG_1)}, {level(VTYPE)})",
                            cube=subselect(f"{CONSULT}, {THERAPY}")), True),
    "subselect_bw_axis": (select(outline(DIAG, DIAG_1), outline(PRG, PRG_1), cube=subselect(PRG_CHRONIC)), False),
    "one_axis_star": (select(f"{outline(DIAG, DIAG_1)} * {level(VTYPE)} * {outline(ORG, ORG_1)}",
                             where="([Measures].[ZCLDUR])"), True),
    "slicer_dimensions": (select(f"CrossJoin({outline(DIAG, DIAG_1)}, {outline(PRG, PRG_1)})", outline(ORG, ORG_1),
                                 f"([ZCLSITE].[NORTH], [ZCLVTYPE].[Outpatient], {CONSULT}, [Measures].[ZCLVISNO])"), True),
    "first_levels": (select(level(PRG), level(SITES)), True),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--url", default="http://localhost:50000/zzxxmla1")
    parser.add_argument("--client", default="001")
    parser.add_argument("--catalog", nargs="*", default=["ZCLVISITA", "ZCLVISIT"])
    parser.add_argument("--show", action="store_true", help="print each statement")
    parser.add_argument("cases", nargs="*", help="the cases (default: all)")
    args = parser.parse_args()
    sap_auth.install()

    def execute(catalog, mdx):
        body = SOAP.format(mdx.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"), catalog)
        request = urllib.request.Request(f"{args.url}?sap-client={args.client}", data=body.encode("utf-8"),
                                         method="POST", headers={"Content-Type": "text/xml; charset=utf-8",
                                                                 "X-olap4abap-Trace": "true",
                                                                 "User-Agent": "olap4abap outline_first_test"})
        with urllib.request.urlopen(request, timeout=600) as response:
            answer = response.read().decode("utf-8")
            trace_id = response.headers.get("X-olap4abap-Trace-Id")
        entry = json.loads(urllib.request.urlopen(
            f"{args.url}/schema/api/trace/entry?sap-client={args.client}&id={trace_id}&response=false",
            timeout=600).read())
        return re.sub(r"<(LastDataUpdate|LastSchemaUpdate)[^>]*>[^<]*</\1>", "", answer), entry

    failed = 0
    total = 0
    for catalog in args.catalog:
        for name, (statement, cells_first) in CASES.items():
            if args.cases and name not in args.cases:
                continue
            total += 1
            mdx = statement.replace("{cube}", f"[{catalog}]")
            if args.show:
                print(mdx)
            new, new_entry = execute(catalog, mdx)
            old, old_entry = execute(catalog, "WITH SET [olap4abap_off] AS '{}' " + mdx)
            phases = collections.Counter(s["phase"] for s in new_entry["sql"])
            problems = []
            if "Fault" in new or "Fault" in old:
                problems.append("fault: " + "; ".join(re.findall(r"<faultstring>(.*?)</faultstring>", new + old)[:2]))
            elif new != old:
                problems.append("the answers differ")
            took = phases.get("Cells first", 0) == 1 and not phases.get("Cells")
            if took != cells_first:
                problems.append("cells first expected" if cells_first else "per-function path expected")
            failed += 1 if problems else 0
            print(f"{'ok  ' if not problems else 'FAIL'} {catalog} {name}: {new.count('<Cell ')} cells, "
                  f"{new_entry['sqlCount']} statements (per-function path {old_entry['sqlCount']}) "
                  f"{dict(phases)}{'  ' + ', '.join(problems) if problems else ''}")
    print(f"{total - failed} of {total} passed ({args.url}?sap-client={args.client})")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
