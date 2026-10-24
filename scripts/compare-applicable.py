#!/usr/bin/env python3
"""Runs the statements of tests/mdx/applicable.json on eMondrian and on SAP and compares the answers.

Compares the axes (unique names of the tuples) and the cell values, or the fault text. Prints how many statements give
the same answer, and the statements SAP cannot answer grouped by the first gap the engine reports ("... is not
implemented yet", other faults), most frequent first. The engine stops at the first gap, so a statement may need more.

    python scripts/compare-applicable.py                       # all statements
    python scripts/compare-applicable.py 46 124 126            # these statements (indexes into applicable.json)
    python scripts/compare-applicable.py --details out.txt     # also write both answers of every statement
    python scripts/compare-applicable.py --workers 1           # one statement at a time

Every statement prints a line to stderr as it completes (its time on SAP and on eMondrian); the summary ends with the
total time and the slowest statements on SAP.

Three statements run at once by default: every one keeps a dialog work process of SAP busy, and the development
system has only a few (seven).
"""
import argparse
import html
import json
import re
import sys
import time
import urllib.error
import urllib.request
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from reference_texts import as_olap4abap

ROOT = Path(__file__).resolve().parent.parent
TEMPLATE = """<SOAP-ENV:Envelope xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/"><SOAP-ENV:Body>
<Execute xmlns="urn:schemas-microsoft-com:xml-analysis"><Command><Statement>{}</Statement></Command>
<Properties><PropertyList><DataSourceInfo>ABAP BW</DataSourceInfo><Catalog>ZFOODMART</Catalog><Format>Multidimensional</Format><AxisFormat>TupleFormat</AxisFormat><Content>Data</Content></PropertyList></Properties>
</Execute></SOAP-ENV:Body></SOAP-ENV:Envelope>"""


def answer(url, mdx):
    """The answer as comparable text: FAULT and the fault string, or the axes and the cells."""
    body = TEMPLATE.format(html.escape(mdx, quote=False))
    request = urllib.request.Request(url, data=body.encode(), headers={
        "Content-Type": "text/xml", "SOAPAction": '"urn:schemas-microsoft-com:xml-analysis:Execute"'})
    try:
        text = as_olap4abap(urllib.request.urlopen(request, timeout=900).read().decode())
    except urllib.error.HTTPError as error:
        text = as_olap4abap(error.read().decode(errors="replace"))
    except Exception as error:  # noqa: BLE001 - a dump or a timeout is an answer too
        return f"NO ANSWER {error}"
    fault = re.search(r"<faultstring>(.*?)</faultstring>", text, re.S)
    if fault:
        return "FAULT " + html.unescape(fault.group(1))
    lines = []
    for name, axis in re.findall(r'<Axis name="(Axis\d+|SlicerAxis)">(.*?)</Axis>', text, re.S):
        tuples = re.findall(r"<Tuple>(.*?)</Tuple>", axis, re.S)
        lines.append(name + ": " + " | ".join(
            ",".join(html.unescape(u) for u in re.findall(r"<UName>([^<]*)</UName>", t)) for t in tuples))
    cells = re.findall(r'<Cell CellOrdinal="(\d+)">.*?<Value[^>]*>([^<]*)<', text, re.S)
    lines.append("cells: " + " ".join(f"{o}={html.unescape(v)}" for o, v in cells))
    return "\n".join(lines)


def gap(sap):
    """The first gap SAP reports for a statement it cannot answer."""
    m = re.search(r"Error:(?:The (?:evaluation of|function) )?(.*?)(?: is| are)? not implemented yet", sap)
    if m:
        return m.group(1)
    m = re.search(r"Error:(.*)", sap)
    return (m.group(1) if m else sap)[:100]


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("indexes", nargs="*", type=int)
    parser.add_argument("--emondrian", default="http://localhost:8080/emondrian/xmla")
    parser.add_argument("--sap", default="http://localhost:50000/zzxxmla1?sap-client=001")
    parser.add_argument("--details", help="file for both answers of every statement")
    parser.add_argument("--workers", type=int, default=3, help="statements run at once (default 3)")
    args = parser.parse_args()

    statements = json.loads((ROOT / "tests" / "mdx" / "applicable.json").read_text(encoding="utf-8"))
    indexes = args.indexes or range(len(statements))

    def timed(url, mdx):
        start = time.monotonic()
        text = answer(url, mdx)
        return text, time.monotonic() - start

    def both(index):
        mdx = statements[index]["mdx"]
        expected, emondrian_seconds = timed(args.emondrian, mdx)
        actual, sap_seconds = timed(args.sap, mdx)
        outcome = "same" if expected == actual else "FAULT" if actual.startswith(("FAULT", "NO ANSWER")) else "differs"
        # progress, one line per statement as it completes
        print(f"#{index:<4} sap {sap_seconds:7.2f}s  emondrian {emondrian_seconds:7.2f}s  {outcome}",
              file=sys.stderr, flush=True)
        return index, mdx, expected, actual, emondrian_seconds, sap_seconds

    started = time.monotonic()
    with ThreadPoolExecutor(max_workers=max(1, args.workers)) as pool:
        results = list(pool.map(both, indexes))
    elapsed = time.monotonic() - started

    same, differs, gaps = [], [], defaultdict(list)
    for index, _, expected, actual, _, _ in results:
        if expected == actual:
            same.append(index)
        elif actual.startswith(("FAULT", "NO ANSWER")) and not expected.startswith("FAULT"):
            gaps[gap(actual)].append(index)
        else:
            differs.append(index)
    print(f"{len(results)} statements: {len(same)} same, {len(differs)} differ, "
          f"{sum(map(len, gaps.values()))} not answered by SAP")
    if differs:
        print(f"differ: #{', #'.join(map(str, differs))}")
    for reason, items in sorted(gaps.items(), key=lambda kv: -len(kv[1])):
        print(f"{len(items):4}  {reason}  #{','.join(map(str, items))}")
    print(f"time: {elapsed:.0f}s elapsed with {max(1, args.workers)} worker(s); SAP {sum(r[5] for r in results):.0f}s, "
          f"eMondrian {sum(r[4] for r in results):.0f}s in total")
    slowest = sorted(results, key=lambda r: -r[5])[:10]
    print("slowest on SAP: " + ", ".join(f"#{r[0]} {r[5]:.1f}s" for r in slowest))
    if args.details:
        with open(args.details, "w", encoding="utf-8") as out:
            for index, mdx, expected, actual, emondrian_seconds, sap_seconds in results:
                out.write(f"=== {index}\n{mdx}\n--- emondrian ({emondrian_seconds:.2f}s)\n{expected}\n"
                          f"--- sap ({sap_seconds:.2f}s)\n{actual}\n\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
