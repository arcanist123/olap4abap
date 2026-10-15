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
    numbers = {(c["column"], c["intColumn"], c["dataType"]) for c in body.get("intColumns", [])}
    check("proposal: NUMC as BW holds it, its number listed for the UI",
          '<NameColumn dataType="String" columnName="ZFMSTORE">' in zfmsales_xml
          and ("ZFMSTORE", "ZFMSTORE_INT", "Integer") in numbers and ("ZFMYEAR", "ZFMYEAR_INT", "Numeric") in numbers,
          body.get("intColumns"))
    outline = body.get("outline", {})
    cube = (outline.get("cubes") or [{}])[0]
    check("proposal of an InfoCube", status == 200 and body["xml"].startswith("<Schema name=\"ZFMSALES\"")
          and [m["name"] for m in cube.get("measures", [])] == ["ZFMUNITS", "ZFMSCOST", "ZFMSSALES"]
          and len(outline.get("dimensions", [])) == len(cube.get("dimensions", [])), body)
    check("proposal: the cube omits its empty cells",
          re.search(r'<Annotation name="olap4abap.omitEmptyCells">\s*true\s*</Annotation>', zfmsales_xml) is not None,
          zfmsales_xml[zfmsales_xml.find("<Cube"):][:300])

    status, body, _ = call(args.url, args.client, "GET", "proposal", {"provider": "ZFMSALESA"})
    adso_xml = body.get("xml", "")
    outline = body.get("outline", {})
    usages = outline.get("cubes", [{}])[0].get("dimensions", [])
    month = [d for d in outline.get("dimensions", []) if d["name"] == "0CALMONTH"]
    check("proposal of an aDSO: time characteristics are dimensions on their views",
          status == 200 and all("source" in u for u in usages)
          and all(d["type"] != "TimeDimension" for d in outline.get("dimensions", []))
          and len(month) == 1 and month[0]["table"] and body.get("notes") == [
              {"iobjnm": "0CALDAY", "reason": "no SID table, so no view"}], body)

    # 0D_NW_SOLD, 0D_NW_SHIP and 0D_NW_PAYER of the SAP demo cube reference 0D_NW_CUST: no tables of their own, each a
    # dimension on the customer's view (or its placeholder)
    status, body, _ = call(args.url, args.client, "GET", "proposal", {"provider": "0D_NW_C01"})
    references = ["0D_NW_SHIP", "0D_NW_SOLD", "0D_NW_PAYER"]
    xml = body.get("xml", "")
    dims = {d["name"]: d for d in body.get("outline", {}).get("dimensions", [])}
    tables = {dims.get(r, {}).get("table") for r in references}
    check("proposal with reference characteristics: dimensions on the referenced characteristic's view",
          status == 200 and len(tables) == 1 and None not in tables
          and xml.count('columnName="D_NW_CUST"') >= len(references)
          and not any(n["iobjnm"] in references for n in body.get("notes", [])), body)
    # docs/bw-schema-design-guide.md: a navigation attribute the cube switches on is a hierarchy of its own
    code = dims.get("0D_NW_CODE", {})
    check("proposal with a navigation attribute: a flat hierarchy CHARACTERISTIC__ATTRIBUTE",
          [h["name"] for h in code.get("hierarchies", [])] == ["", "0D_NW_CODE__0D_NW_CNTRY"]
          and all(a["name"] != "0D_NW_CNTRY" for a in code.get("attributes", [])), code)

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
        if name == "ZFOODMART":
            # the view's number depends on the system's other views (scripts/sap-files.py deploy)
            numbers = {(c["column"], c["intColumn"]) for c in body.get("intColumns", [])
                       if re.fullmatch(r"ZZXXMLA1V\d{7}", c["table"])}
            check("schema of ZFOODMART: the numbers of its views' NUMC columns",
                  ("ZFMSQFT", "ZFMSQFT_INT") in numbers, body.get("intColumns"))
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
    check("check refuses an attribute hierarchy named like the unnamed Hierarchy",
          status == 400 and any(text in body.get("error", "") for text in
                                ["by an unnamed Hierarchy and by the attribute", "is defined twice"]), body)

    # selections (docs/bw-schema-design-guide.md, section 3.8), an edit of the schema (POST fix): the proposal lists
    # the characteristics with their dimensions, what cannot be restricted is refused; fixing and accepting is tested
    # by scripts/fixed_selection_test.py, which writes catalogs
    proposals = {}
    for provider in ("ZFMSALESA", "ZCLVISIT", "ZCLVISITA"):
        status, body, _ = call(args.url, args.client, "GET", "proposal", {"provider": provider})
        proposals[provider] = body.get("xml", "")
        if provider == "ZCLVISITA":
            listed = {c["name"]: c for c in body.get("characteristics", [])}
            check("proposal lists the characteristics, the period compounded with the variant, none fixed",
                  status == 200 and listed.get("ZCLFISCPR", {}).get("compounding") == ["ZCLFISCVR"]
                  and listed.get("ZCLFISCPR", {}).get("dimension") == "ZCLFISCPR"
                  and listed["ZCLFISCPR"].get("foreignKey") == "SID_ZCLFISCPR"
                  and not any(c["fixed"] for c in listed.values()), body.get("characteristics"))
    for provider, fixed, text in (
            ("ZFMSALESA", {"fixed.0FISCVARNT": "K4"}, "is not a characteristic of"),
            ("ZCLVISITA", {"filter.ZCLFISCVR": "I BT 'K1'"}, "needs a high value"),
            ("ZCLVISITA", {"filter.ZCLFISCVR": "I EQ 'K4"}, "without its closing quote"),
            ("ZCLVISITA", {"fixed.ZCLFISCVR": "K4", "members.ZCLFISCVR": "I EQ 'K4'"}, "has two selections"),
            ("ZCLVISITA", {"members.ZCLFISCPR": "I EQ '2024999'"}, "has no value 2024999"),
            ("ZCLVISITA", {"fixed.ZCLFISCVR": "K4", "members.ZCLFISCPR": "I EQ '2024013'"},
             "has no value 2024013 under the selection of its compounding"),
            ("ZCLVISITA", {"fixed.ZCLFISCVR": "ZZ"}, "has no value ZZ"),
            ("ZCLVISITA", {"fixed.ZCLFISCVR": "K'"}, "cannot contain a quote")):
        status, body, _ = call(args.url, args.client, "POST", "fix", fixed, proposals[provider])
        check(f"fix of {provider} refuses {fixed}", status == 400 and text in body.get("error", ""), body)
    # restrict members: the annotation with the rows, the facts as they are, the period still compounded
    status, body, _ = call(args.url, args.client, "POST", "fix", {"members.ZCLFISCPR": "E CP '*013';E CP '*014'"},
                           proposals["ZCLVISITA"])
    xml = body.get("xml", "")
    listed = {c["name"]: c for c in body.get("characteristics", [])}
    fact = re.findall(r'<Table name="([^"]+)"', xml)[-1:] == re.findall(r'<Table name="([^"]+)"', proposals["ZCLVISITA"])[-1:]
    check("fix restricts the members of the period, the facts stay",
          status == 200 and fact
          and re.search(r'<Annotation name="olap4abap\.members\.ZCLFISCPR">\s*E CP (?:\'|&apos;|&#39;)\*013', xml) is not None
          and listed.get("ZCLFISCPR", {}).get("mode") == "members"
          and listed["ZCLFISCPR"].get("selection") == "E CP '*013';E CP '*014'"
          and [r["option"] for r in listed["ZCLFISCPR"].get("rows", [])] == ["CP", "CP"]
          and listed["ZCLFISCPR"].get("fixed") is False, body.get("error") or body.get("characteristics"))
    status, body, _ = call(args.url, args.client, "POST", "fix", {"cube": "NO_SUCH_CUBE"}, proposals["ZCLVISITA"])
    check("fix of an unknown cube", status == 400 and "no cube 'NO_SUCH_CUBE'" in body.get("error", ""), body)
    status, body, headers = call(args.url, args.client, "GET", "fix")
    check("fix needs POST", status == 405 and headers.get("allow", headers.get("Allow")) == "POST", body)
    # the probe (ZZXXMLA1_CL_SCHEMA_PROBE): restricting members refused while the facts hold excluded values, on the
    # cube's own facts (filtered on K4 they hold no 2024 value of K1)
    for provider in ("ZCLVISIT", "ZCLVISITA"):
        status, body, _ = call(args.url, args.client, "POST", "fix", {"members.ZCLFISCPR": "I CP '2024*'"},
                               proposals[provider])
        check(f"probe of {provider} refuses periods of 2025 in the facts",
              status == 400 and "restricts the members of ZCLFISCPR" in body.get("error", "")
              and "K1/2025001 (" in body.get("error", ""), body)
        status, body, _ = call(args.url, args.client, "POST", "fix",
                               {"filter.ZCLFISCVR": "I EQ 'K4'", "members.ZCLFISCPR": "I CP '2024*'"},
                               proposals[provider])
        check(f"probe of {provider} reads the cube's facts, filtered on K4",
              status == 400 and "K4/2025001 (" in body.get("error", "") and "K1/" not in body.get("error", ""), body)
    status, body, _ = call(args.url, args.client, "POST", "probe")
    catalogs = {c["catalog"]: c for c in body.get("catalogs", [])}
    check("probe of all catalogs", status == 200 and isinstance(body.get("runtime"), int)
          and catalogs.get("ZCLVISIT", {}).get("ok") is True
          and catalogs["ZCLVISIT"].get("cubes", [{}])[0].get("cube") == "ZCLVISIT", body)
    status, body, _ = call(args.url, args.client, "POST", "probe", {"catalog": "ZCLVISITA"})
    check("probe of one catalog", status == 200 and [c["catalog"] for c in body.get("catalogs", [])] == ["ZCLVISITA"],
          body)
    status, body, _ = call(args.url, args.client, "POST", "probe", {"catalog": "NO_SUCH_CATALOG"})
    check("probe of an unknown catalog", status == 404, body)
    status, body, headers = call(args.url, args.client, "GET", "probe")
    check("probe needs POST", status == 405 and headers.get("allow", headers.get("Allow")) == "POST", body)
    # the values the UI offers: a compounded characteristic's under the selection of its compounding, if it has one
    status, body, _ = call(args.url, args.client, "GET", "values", {"characteristic": "ZCLFISCVR"})
    check("values of the fiscal year variant", status == 200 and body.get("values") == ["K1", "K2", "K4"]
          and body.get("more") is False, body)
    status, body, _ = call(args.url, args.client, "GET", "values", {"characteristic": "ZCLFISCPR"})
    check("values of the period under every variant", status == 200 and len(body.get("values", [])) >= 24
          and body["values"][0] == "2024001", body)
    status, body, _ = call(args.url, args.client, "GET", "values",
                           {"characteristic": "ZCLFISCPR", "fixed.ZCLFISCVR": "K4"})
    check("values of the period under K4", status == 200 and len(body.get("values", [])) == 24
          and body["values"][0] == "2024001", body)

    # the time master data: only read; time/fill is called with what it refuses before writing
    status, body, _ = call(args.url, args.client, "GET", "time", {"from": "1997-01-01", "to": "1997-12-31"})
    found = {c["name"]: c for c in body.get("characteristics", [])}
    check("time: state of the calendar characteristics",
          status == 200 and body.get("from") == "1997-01-01" and found.get("0CALMONTH", {}).get("expected") == 12
          and found.get("0CALWEEK", {}).get("expected") == 53 and found.get("0WEEKDAY1", {}).get("attributeTable") is None,
          body)
    status, body, _ = call(args.url, args.client, "GET", "time", {"from": "1997-02-30"})
    check("time refuses an impossible date", status == 400 and "not a date" in body.get("error", ""), body)
    status, body, headers = call(args.url, args.client, "GET", "time/fill")
    check("time/fill needs POST", status == 405 and headers.get("allow", headers.get("Allow")) == "POST", body)
    status, body, _ = call(args.url, args.client, "POST", "time/fill", {"from": "1998-01-01", "to": "1997-01-01"})
    check("time/fill refuses an interval that ends before it starts", status == 400 and "starts after" in body.get("error", ""), body)

    print(f"{'all passed' if not failures else str(len(failures)) + ' failed'} ({args.url})")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
