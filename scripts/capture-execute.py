#!/usr/bin/env python3
"""Captures one XMLA Execute exchange from the eMondrian container as a test case in reference/<name>/.

    python scripts/capture-execute.py execute_one_measure "select {[Measures].[Unit Sales]} on columns from [ZFMSALES]"

Writes request.xml and response.xml (see docs/test-strategy.md). The properties DataSourceInfo (ABAP BW), Catalog
(ZFOODMART), Format (Multidimensional), AxisFormat (TupleFormat) and Content (SchemaData) are sent; override or add
with -p NAME=VALUE. The statement can also be given as @index of tests/mdx/applicable.json (e.g. @9).
"""
import argparse
import json
import re
import urllib.request
from pathlib import Path
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parent.parent


def request_xml(statement, properties):
    items = "".join(f"<{k}>{escape(v)}</{k}>" for k, v in properties.items())
    return f"""<SOAP-ENV:Envelope xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/" SOAP-ENV:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
<SOAP-ENV:Body>
<Execute xmlns="urn:schemas-microsoft-com:xml-analysis" SOAP-ENV:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
<Command><Statement>{escape(statement)}</Statement></Command>
<Properties><PropertyList>{items}</PropertyList></Properties>
</Execute></SOAP-ENV:Body></SOAP-ENV:Envelope>
"""


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("name")
    parser.add_argument("statement")
    parser.add_argument("-p", "--property", action="append", default=[], metavar="NAME=VALUE")
    parser.add_argument("--url", default="http://localhost:8080/emondrian/xmla")
    args = parser.parse_args()

    statement = args.statement
    if statement.startswith("@"):
        statement = json.loads((ROOT / "tests/mdx/applicable.json").read_text(encoding="utf-8"))[int(statement[1:])]["mdx"]
    properties = {"DataSourceInfo": "ABAP BW", "Catalog": "ZFOODMART", "Format": "Multidimensional",
                  "AxisFormat": "TupleFormat", "Content": "SchemaData"}
    properties.update(p.split("=", 1) for p in args.property)
    body = request_xml(statement, properties)

    request = urllib.request.Request(args.url, data=body.encode("utf-8"), method="POST", headers={
        "Content-Type": "text/xml; charset=utf-8", "SOAPAction": '"urn:schemas-microsoft-com:xml-analysis:Execute"'})
    with urllib.request.urlopen(request, timeout=600) as response:
        answer = response.read().decode("utf-8")

    folder = ROOT / "reference" / args.name
    folder.mkdir(parents=True, exist_ok=True)
    (folder / "request.xml").write_text(body, encoding="utf-8", newline="\n")
    (folder / "response.xml").write_text(answer, encoding="utf-8", newline="\n")
    print(f"{args.name}: {len(answer)} bytes, {len(re.findall(r'<Cell ', answer))} cells")


if __name__ == "__main__":
    main()
