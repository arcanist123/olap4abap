#!/usr/bin/env python3
"""Captures one XMLA Discover exchange from the eMondrian container as a test case in reference/<name>/.

    python scripts/capture-case.py mdschema_members_gender MDSCHEMA_MEMBERS \
        -r CATALOG_NAME=ZFOODMART -r CUBE_NAME=ZFMSALES -r HIERARCHY_UNIQUE_NAME=[Customer.Gender]

Writes request.xml and response.xml (see docs/test-strategy.md). The properties DataSourceInfo (ABAP BW), Catalog
(ZFOODMART) and Content (Data) are always sent; add more with -p NAME=VALUE. With --count-only the answer is too big
to keep: only rows.txt (the number of rows) is written, and xmla_test.py compares the number of rows.
"""
import argparse
import re
import urllib.request
from pathlib import Path
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parent.parent


def request_xml(request_type, restrictions, properties):
    items = lambda pairs: "".join(f"<{k}>{escape(v)}</{k}>" for k, v in pairs)
    return f"""<SOAP-ENV:Envelope xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/" SOAP-ENV:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
<SOAP-ENV:Body>
<Discover xmlns="urn:schemas-microsoft-com:xml-analysis" SOAP-ENV:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
<RequestType>{request_type}</RequestType>
<Restrictions><RestrictionList>{items(restrictions)}</RestrictionList></Restrictions>
<Properties><PropertyList>{items(properties)}</PropertyList></Properties>
</Discover></SOAP-ENV:Body></SOAP-ENV:Envelope>
"""


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("name")
    parser.add_argument("request_type")
    parser.add_argument("-r", "--restriction", action="append", default=[], metavar="NAME=VALUE")
    parser.add_argument("-p", "--property", action="append", default=[], metavar="NAME=VALUE")
    parser.add_argument("--count-only", action="store_true")
    parser.add_argument("--url", default="http://localhost:8080/emondrian/xmla")
    args = parser.parse_args()

    pair = lambda text: tuple(text.split("=", 1))
    properties = [("DataSourceInfo", "ABAP BW"), ("Catalog", "ZFOODMART"), ("Content", "Data")]
    properties += [pair(p) for p in args.property]
    body = request_xml(args.request_type, [pair(r) for r in args.restriction], properties)

    request = urllib.request.Request(args.url, data=body.encode("utf-8"), method="POST", headers={
        "Content-Type": "text/xml; charset=utf-8", "SOAPAction": '"urn:schemas-microsoft-com:xml-analysis:Discover"'})
    with urllib.request.urlopen(request, timeout=600) as response:
        answer = response.read().decode("utf-8")

    folder = ROOT / "reference" / args.name
    folder.mkdir(parents=True, exist_ok=True)
    (folder / "request.xml").write_text(body, encoding="utf-8", newline="\n")
    rows = len(re.findall(r"<row>", answer))
    if args.count_only:
        (folder / "rows.txt").write_text(f"{rows}\n", encoding="utf-8", newline="\n")
        print(f"{args.name}: {rows} rows (count only)")
    else:
        (folder / "response.xml").write_text(answer, encoding="utf-8", newline="\n")
        print(f"{args.name}: {rows} rows, {len(answer)} bytes")


if __name__ == "__main__":
    main()
