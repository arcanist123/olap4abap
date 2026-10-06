#!/usr/bin/env python3
"""Checks the schema generator's API on SAP (/zzxxmla1/schema/api, ZZXXMLA1_CL_SCHEMA_API) over HTTP, as the UI calls
it. Changes nothing on the server: check writes nothing, and accept is only called with schemas it refuses before
writing; remove only with catalogs it does not have.

    python scripts/schema_api_test.py
    python scripts/schema_api_test.py --url http://localhost:50000/zzxxmla1/schema/api --client 001
"""
import argparse
import json
import re
import sys
import urllib.error
import urllib.parse
import urllib.request


def call(base, client, method, resource, params=None, body=None):
    query = urllib.parse.urlencode({"sap-client": client, **(params or {})})
    request = urllib.request.Request(f"{base}/{resource}?{query}", method=method,
                                     data=body.encode("utf-8") if body is not None else None,
                                     headers={"Content-Type": "application/xml; charset=utf-8"})
    try:
        with urllib.request.urlopen(request) as response:
            return response.status, json.loads(response.read().decode("utf-8")), dict(response.headers)
    except urllib.error.HTTPError as error:
        return error.code, json.loads(error.read().decode("utf-8")), dict(error.headers)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--url", default="http://localhost:50000/zzxxmla1/schema/api")
    parser.add_argument("--client", default="001")
    args = parser.parse_args()
    failures = []

    def check(name, condition, detail=""):
        print(f"{'ok  ' if condition else 'FAIL'} {name}{'' if condition else ': ' + str(detail)[:300]}")
        if not condition:
            failures.append(name)

    status, body, _ = call(args.url, args.client, "GET", "providers")
    names = {p["name"]: p["kind"] for p in body.get("providers", [])}
    check("providers", status == 200 and names.get("ZFMSALES") == "InfoCube" and names.get("ZFMSALESA") == "aDSO", body)

    status, body, _ = call(args.url, args.client, "GET", "proposal", {"provider": "ZFMSALES"})
    zfmsales_xml = body.get("xml", "")
    outline = body.get("outline", {})
    cube = (outline.get("cubes") or [{}])[0]
    check("proposal of an InfoCube", status == 200 and body["xml"].startswith("<Schema name=\"ZFMSALES\"")
          and [m["name"] for m in cube.get("measures", [])] == ["Unit Sales", "Store Cost", "Store Sales"]
          and len(outline.get("dimensions", [])) == len(cube.get("dimensions", [])), body)

    status, body, _ = call(args.url, args.client, "GET", "proposal", {"provider": "ZFMSALESA"})
    adso_xml = body.get("xml", "")
    outline = body.get("outline", {})
    usages = outline.get("cubes", [{}])[0].get("dimensions", [])
    month = [d for d in outline.get("dimensions", []) if d["name"] == "Calendar Year/Month"]
    check("proposal of an aDSO: time characteristics are dimensions on their views",
          status == 200 and all("source" in u for u in usages)
          and all(d["type"] != "TimeDimension" for d in outline.get("dimensions", []))
          and len(month) == 1 and month[0]["table"] and body.get("notes") == [
              {"iobjnm": "0CALDAY", "reason": "no SID table, so no view"}], body)

    # 0D_NW_SOLD, 0D_NW_SHIP and 0D_NW_PAYER of the SAP demo cube reference 0D_NW_CUST: no tables of their own
    status, body, _ = call(args.url, args.client, "GET", "proposal", {"provider": "0D_NW_C01"})
    references = ["0D_NW_SHIP", "0D_NW_SOLD", "0D_NW_PAYER"]
    xml = body.get("xml", "")
    check("proposal with reference characteristics: dimensions on the referenced characteristic's tables",
          status == 200 and all(f'table="ZZXXMLA1_C_{r}"' in xml for r in references)
          and xml.count('columnName="D_NW_CUST"') >= len(references)
          and not any(n["iobjnm"] in references for n in body.get("notes", [])), body)

    status, body, _ = call(args.url, args.client, "GET", "proposal", {"provider": "NO_SUCH_PROVIDER"})
    check("proposal of an unknown provider", status == 404 and "error" in body, body)

    status, body, _ = call(args.url, args.client, "GET", "proposal")
    check("proposal without provider", status == 400 and body == {"error": "Parameter provider is missing"}, body)

    status, body, headers = call(args.url, args.client, "GET", "accept")
    check("accept needs POST", status == 405 and headers.get("allow", headers.get("Allow")) == "POST", body)

    status, body, _ = call(args.url, args.client, "GET", "nothing")
    check("unknown resource", status == 404, body)

    status, body, _ = call(args.url, args.client, "POST", "accept", {"catalog": "ZZXXMLA1_API_TEST"}, "<Schema>")
    check("accept of unreadable XML", status == 400 and body["error"].startswith("Schema not readable"), body)

    status, body, _ = call(args.url, args.client, "POST", "accept", {"catalog": "../x"}, adso_xml)
    check("accept of a bad catalog name", status == 400 and "Catalog name" in body.get("error", ""), body)

    status, body, _ = call(args.url, args.client, "GET", "schemas")
    schemas = {c["catalog"]: c for c in body.get("schemas", [])}
    check("schemas", status == 200 and schemas.get("ZFOODMART", {}).get("file") == "/WEB-INF/schema/FoodmartBW.xml"
          and all(c["exists"] for c in schemas.values()), body)

    for name, entry in schemas.items():
        status, body, _ = call(args.url, args.client, "GET", "schema", {"catalog": name})
        stored = body.get("xml", "")
        check(f"schema of {name}", status == 200 and body.get("file") == entry["file"]
              and stored.lstrip().startswith(("<Schema", "<?xml")) and body.get("outline", {}).get("cubes"), body)
        status, body, _ = call(args.url, args.client, "POST", "check", {"catalog": name}, stored)
        check(f"check of {name} as stored", status == 200 and body.get("newCatalog") is False
              and body.get("file") == entry["file"], body)

    status, body, _ = call(args.url, args.client, "GET", "schema", {"catalog": "NO_SUCH_CATALOG"})
    check("schema of an unknown catalog", status == 404 and "error" in body, body)

    status, body, headers = call(args.url, args.client, "GET", "remove", {"catalog": "ZFOODMART"})
    check("remove needs POST", status == 405 and headers.get("allow", headers.get("Allow")) == "POST", body)

    status, body, _ = call(args.url, args.client, "POST", "remove", {"catalog": "NO_SUCH_CATALOG"})
    check("remove of an unknown catalog", status == 404 and body == {"error": "No catalog 'NO_SUCH_CATALOG'"}, body)

    status, body, _ = call(args.url, args.client, "POST", "check", {"catalog": "ZZXXMLA1_API_TEST"}, zfmsales_xml)
    check("check refuses a cube another catalog has", status == 400 and "is defined twice" in body.get("error", ""), body)

    # an unnamed Hierarchy next to the key attribute named like its dimension
    first = re.search(r'<Dimension\s[^>]*\bname="([^"]+)"[^>]*>.*?</Dimension>', adso_xml, re.S)
    clash = (adso_xml[:first.end() - len("</Dimension>")]
             + f'<Hierarchy hasAll="true"><Level name="L" sourceAttribute="{first.group(1)}"/></Hierarchy>'
             + adso_xml[first.end() - len("</Dimension>"):])
    status, body, _ = call(args.url, args.client, "POST", "check", {"catalog": "ZFMSALESA"}, clash)
    check("check refuses an unnamed hierarchy named like an attribute",
          status == 400 and "by an unnamed Hierarchy and by the attribute" in body.get("error", ""), body)

    print(f"{'all passed' if not failures else str(len(failures)) + ' failed'} ({args.url})")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
