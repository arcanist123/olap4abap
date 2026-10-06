#!/usr/bin/env python3
"""Captures the answers of existing test cases again from the eMondrian container, after the reference schema changed.

Posts reference/<case>/request.xml as it is and replaces response.xml (status.txt if the case has one; rows.txt, the
number of rows, for a count-only case). Cases whose request names something the schema no longer has must be edited
first. Prints the cases whose answer changed, so that the change can be reviewed with git diff.

    python scripts/recapture-cases.py              # all cases
    python scripts/recapture-cases.py members_ execute_store_children   # cases whose names start with these
"""
import argparse
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOAP_ACTION = {"Discover": '"urn:schemas-microsoft-com:xml-analysis:Discover"',
               "Execute": '"urn:schemas-microsoft-com:xml-analysis:Execute"'}


def post(url, body):
    action = SOAP_ACTION["Execute" if "<Execute" in body else "Discover"]
    request = urllib.request.Request(url, data=body.encode("utf-8"), method="POST",
                                     headers={"Content-Type": "text/xml; charset=utf-8", "SOAPAction": action})
    try:
        with urllib.request.urlopen(request, timeout=600) as response:
            return response.status, response.read().decode("utf-8")
    except urllib.error.HTTPError as error:
        return error.code, error.read().decode("utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("prefixes", nargs="*")
    parser.add_argument("--url", default="http://localhost:8080/emondrian/xmla")
    args = parser.parse_args()

    changed = []
    for folder in sorted(p for p in (ROOT / "reference").iterdir() if (p / "request.xml").exists()):
        if args.prefixes and not any(folder.name.startswith(p) for p in args.prefixes):
            continue
        status, answer = post(args.url, (folder / "request.xml").read_text(encoding="utf-8"))
        if (folder / "rows.txt").exists():
            target, text = folder / "rows.txt", f"{len(re.findall(r'<row>', answer))}\n"
        else:
            target, text = folder / "response.xml", answer
        if (folder / "status.txt").exists():
            (folder / "status.txt").write_text(f"{status}\n", encoding="utf-8", newline="\n")
        if not target.exists() or target.read_text(encoding="utf-8") != text:
            changed.append(folder.name)
        target.write_text(text, encoding="utf-8", newline="\n")
    print(f"{len(changed)} changed: {' '.join(changed)}")


if __name__ == "__main__":
    sys.exit(main())
