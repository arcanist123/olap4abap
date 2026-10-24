#!/usr/bin/env python3
"""Finds the MDX statements of Mondrian's integration tests that run against our reference schema.

1. Extracts every MDX statement on the FoodMart cube [Sales] from the Java tests (mondrian/mondrian/src/it/java): string
   literals joined with +, the variable nl standing for a line feed.
2. Runs each one against the reference catalog in the eMondrian container (cube renamed to [ZFMSALES], as our schema
   names it) and records whether Mondrian accepts it. The tests were written for the original FoodMart schema, so most
   statements fail because the hierarchies they use do not exist in our model; the ones that run are the "applicable"
   tests.
3. Writes tests/mdx/applicable.json (statement, source file and line) and prints a summary with the most common errors.

    python scripts/extract-mdx-tests.py [--url http://localhost:8080/emondrian/xmla] [--limit N]
"""
import argparse
import collections
import json
import re
import sys
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parent.parent
JAVA = ROOT / "mondrian/mondrian/src/it/java"
OUT = ROOT / "tests/mdx/applicable.json"
CATALOG = "ZFOODMART"
CUBE = "ZFMSALES"

LIT = r'"(?:[^"\\\n]|\\.)*"'
SEQUENCE = re.compile(rf"{LIT}(?:\s*\+\s*(?:{LIT}|\bnl\b))*")
FROM_SALES = re.compile(r"\bfrom\s+\[Sales\]", re.IGNORECASE)


def unescape(literal):
    body = literal[1:-1]
    return re.sub(r"\\(.)", lambda m: {"n": "\n", "t": "\t", '"': '"', "\\": "\\", "'": "'"}.get(m.group(1), m.group(1)), body)


def statements(path):
    text = path.read_text(encoding="utf-8", errors="replace")
    for match in SEQUENCE.finditer(text):
        parts = re.findall(rf"{LIT}|\bnl\b", match.group(0))
        mdx = "".join("\n" if p == "nl" else unescape(p) for p in parts)
        if re.search(r"\bselect\b", mdx, re.IGNORECASE) and FROM_SALES.search(mdx):
            yield text.count("\n", 0, match.start()) + 1, mdx.strip()


def execute(url, mdx):
    body = f"""<SOAP-ENV:Envelope xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/"><SOAP-ENV:Body>
<Execute xmlns="urn:schemas-microsoft-com:xml-analysis"><Command><Statement>{escape(mdx)}</Statement></Command>
<Properties><PropertyList><DataSourceInfo>ABAP BW</DataSourceInfo><Catalog>{CATALOG}</Catalog>
<Format>Multidimensional</Format><AxisFormat>TupleFormat</AxisFormat></PropertyList></Properties></Execute>
</SOAP-ENV:Body></SOAP-ENV:Envelope>"""
    request = urllib.request.Request(url, data=body.encode("utf-8"), method="POST", headers={
        "Content-Type": "text/xml; charset=utf-8", "SOAPAction": '"urn:schemas-microsoft-com:xml-analysis:Execute"'})
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            text = response.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as error:
        text = error.read().decode("utf-8", "replace")
    except Exception as error:  # timeout, connection
        return str(error)
    fault = re.search(r"<faultstring>(.*?)</faultstring>", text, re.S)
    return None if not fault else re.sub(r"\s+", " ", fault.group(1))[:300]


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--url", default="http://localhost:8080/emondrian/xmla")
    parser.add_argument("--limit", type=int, default=0)
    args = parser.parse_args()

    found = {}
    total = 0
    for path in sorted(JAVA.rglob("*.java")):
        for line, mdx in statements(path):
            total += 1
            found.setdefault(FROM_SALES.sub(f"from [{CUBE}]", mdx), f"{path.relative_to(ROOT).as_posix()}:{line}")
    items = list(found.items())
    if args.limit:
        items = items[:args.limit]
    print(f"{total} statements on [Sales], {len(found)} different; running {len(items)} ...", flush=True)

    with ThreadPoolExecutor(max_workers=4) as pool:
        errors = list(pool.map(lambda item: execute(args.url, item[0]), items))

    applicable = [{"source": src, "mdx": mdx} for (mdx, src), err in zip(items, errors) if err is None]
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(applicable, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")

    # group the errors by their text without the names of the missing objects
    def kind(err):
        return re.sub(r"'[^']*'|\[[^\]]*\]|\d+", "_", err)[:110]
    groups = collections.Counter(kind(e) for e in errors if e)
    print(f"{len(applicable)} of {len(items)} run in Mondrian on our schema -> {OUT.relative_to(ROOT)}")
    for text, count in groups.most_common(12):
        print(f"  {count:5d}  {text}")


if __name__ == "__main__":
    sys.exit(main())
