#!/usr/bin/env python3
"""Captures one XMLA Execute exchange from the eMondrian container as a test case in reference/<name>/.

    python scripts/capture-execute.py execute_one_measure "select {[Measures].[Unit Sales]} on columns from [ZFMSALES]"

Writes request.xml and response.xml (see docs/test-strategy.md). The properties DataSourceInfo (ABAP BW), Catalog
(ZFOODMART), Format (Multidimensional), AxisFormat (TupleFormat) and Content (SchemaData) are sent; override or add
with -p NAME=VALUE. The statement can also be given as @index of tests/mdx/applicable.json (e.g. @9).

Where olap4abap answers differently from the reference on purpose (docs/known-issues.md, deliberate deviations),
--answer-of takes the expected answer from an equivalent statement the reference answers as olap4abap should:
request.xml holds the statement, response.xml the reference's answer of the equivalent one and equivalent.txt the
equivalent statement, so that the case can be captured again.

    python scripts/capture-execute.py execute_caption_subcube_name -p Catalog=ZFMCAPT \
        'SELECT FROM (SELECT Filter([Promotions].[Promotion].Members, [Promotions].CurrentMember.Name = "0000000001") ON 0 FROM [ZFMSALESCP])' \
        --answer-of 'SELECT FROM (SELECT {[Promotions].[0000000001]} ON 0 FROM [ZFMSALESCP])'
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
    parser.add_argument("--answer-of", metavar="STATEMENT", help="the equivalent statement the reference answers")
    args = parser.parse_args()

    statement = args.statement
    if statement.startswith("@"):
        statement = json.loads((ROOT / "tests/mdx/applicable.json").read_text(encoding="utf-8"))[int(statement[1:])]["mdx"]
    properties = {"DataSourceInfo": "ABAP BW", "Catalog": "ZFOODMART", "Format": "Multidimensional",
                  "AxisFormat": "TupleFormat", "Content": "SchemaData"}
    properties.update(p.split("=", 1) for p in args.property)
    body = request_xml(statement, properties)
    asked = request_xml(args.answer_of, properties) if args.answer_of else body

    request = urllib.request.Request(args.url, data=asked.encode("utf-8"), method="POST", headers={
        "Content-Type": "text/xml; charset=utf-8", "SOAPAction": '"urn:schemas-microsoft-com:xml-analysis:Execute"'})
    with urllib.request.urlopen(request, timeout=600) as response:
        answer = response.read().decode("utf-8")

    folder = ROOT / "reference" / args.name
    folder.mkdir(parents=True, exist_ok=True)
    (folder / "request.xml").write_text(body, encoding="utf-8", newline="\n")
    (folder / "response.xml").write_text(answer, encoding="utf-8", newline="\n")
    if args.answer_of:
        (folder / "equivalent.txt").write_text(args.answer_of + "\n", encoding="utf-8", newline="\n")
    print(f"{args.name}: {len(answer)} bytes, {len(re.findall(r'<Cell ', answer))} cells")


if __name__ == "__main__":
    main()
