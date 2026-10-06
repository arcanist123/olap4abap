#!/usr/bin/env python3
"""Captures the error behaviour of the eMondrian container as test cases.

Takes the requests of Mondrian's XmlaErrorTest (mondrian/mondrian/src/it/java/mondrian/xmla/XmlaErrorTest.ref.xml: junk,
bad XML, bad SOAP, bad bodies, ...), posts each to the container and stores request, HTTP status and answer in
reference/error_<case>/ (request.xml, response.xml, status.txt). scripts/xmla_test.py then replays them against SAP and
compares status and body, so the faults of the ABAP server are exactly those of Mondrian.

The authorization tests (testAuth*) need the test harness' credentials and are skipped.

    python scripts/capture-error-cases.py [--url http://localhost:8080/emondrian/xmla]
"""
import argparse
import re
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REF = ROOT / "mondrian/mondrian/src/it/java/mondrian/xmla/XmlaErrorTest.ref.xml"
OUT = ROOT / "reference"


def post(url, body):
    request = urllib.request.Request(url, data=body.encode("utf-8"), method="POST", headers={
        "Content-Type": "text/xml; charset=utf-8", "SOAPAction": '"urn:schemas-microsoft-com:xml-analysis:Discover"'})
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            return response.status, response.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as error:
        return error.code, error.read().decode("utf-8", "replace")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--url", default="http://localhost:8080/emondrian/xmla")
    args = parser.parse_args()

    for case in ET.parse(REF).getroot().iter("TestCase"):
        name = case.get("name")
        resource = case.find("Resource[@name='request']")
        if not name.startswith("test") or name.startswith("testAuth") or resource is None or resource.text is None:
            continue
        body = resource.text.strip("\r\n")
        status, answer = post(args.url, body)
        folder = OUT / ("error_" + re.sub(r"(?<!^)(?=[A-Z])", "_", name[4:]).lower())
        folder.mkdir(parents=True, exist_ok=True)
        (folder / "request.xml").write_text(body + "\n", encoding="utf-8", newline="\n")
        (folder / "response.xml").write_text(answer, encoding="utf-8", newline="\n")
        (folder / "status.txt").write_text(f"{status}\n", encoding="utf-8", newline="\n")
        fault = re.search(r"<faultcode>(.*?)</faultcode>\s*<faultstring>(.*?)</faultstring>", answer, re.S)
        print(f"{folder.name:28} HTTP {status}  {fault.group(1) if fault else 'no fault'}  {fault.group(2)[:70] if fault else ''}")


if __name__ == "__main__":
    main()
