#!/usr/bin/env python3
"""Tests the dimensions that show only their members with facts (the annotation olap4abap.membersWithFacts, our
extension; docs/mvp-scope.md, Members with facts) on the clinic demo against SAP. The reference server cannot do this,
so there is no captured answer: the oracle is the engine's own NON EMPTY, which reads the members with facts from the
fact table, while a level's members come from the dimension table with the restriction.

The clinic demo (docs/clinic-demo.md) has 300 patients registered without a visit; its schemas are the schema
generator's proposals, which annotate every dimension (none is marked time). Checks, on the cube ZCLVISIT and the aDSO
ZCLVISITA:
- every dimension's level (a flat hierarchy per characteristic, named by its technical name) and the All member's
  children: the members are those of NON EMPTY over all facts, in the same order;
- a patient without facts cannot be named (the registered patient 002001), the one before can;
- counts, ranges along a level, native TopCount and MDSCHEMA_LEVELS' LEVEL_CARDINALITY agree with them;
- and, not about members with facts: the Text property of two hierarchies on one axis is written per hierarchy.

    python scripts/clinic_test.py
    python scripts/clinic_test.py --url http://localhost:50000/zzxxmla1?sap-client=001
"""
import argparse
import html
import re
import sys
import urllib.error
import urllib.request

EXECUTE = """<SOAP-ENV:Envelope xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/"><SOAP-ENV:Body>
<Execute xmlns="urn:schemas-microsoft-com:xml-analysis"><Command><Statement>{statement}</Statement></Command>
<Properties><PropertyList><DataSourceInfo>ABAP BW</DataSourceInfo><Catalog>{catalog}</Catalog>
<Format>Multidimensional</Format><AxisFormat>TupleFormat</AxisFormat><Content>Data</Content></PropertyList></Properties>
</Execute></SOAP-ENV:Body></SOAP-ENV:Envelope>"""
DISCOVER = """<SOAP-ENV:Envelope xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/"><SOAP-ENV:Body>
<Discover xmlns="urn:schemas-microsoft-com:xml-analysis"><RequestType>{request_type}</RequestType>
<Restrictions><RestrictionList><CATALOG_NAME>{catalog}</CATALOG_NAME><CUBE_NAME>{catalog}</CUBE_NAME>
</RestrictionList></Restrictions>
<Properties><PropertyList><DataSourceInfo>ABAP BW</DataSourceInfo><Catalog>{catalog}</Catalog><Content>Data</Content>
</PropertyList></Properties></Discover></SOAP-ENV:Body></SOAP-ENV:Envelope>"""

# the characteristics with a dimension on both providers; the cube also has the date, the aDSO BW's calendar
DIMENSIONS = ["ZCLPAT", "ZCLDOC", "ZCLDIAG", "ZCLVTYPE", "ZCLSERV", "ZCLSITE", "ZCLROOM", "ZCLFISCVR", "ZCLFISCYR", "ZCLFISCPR"]
OWN = {"ZCLVISIT": ["ZCLDATE"], "ZCLVISITA": ["0CALWEEK", "0CALMONTH", "0CALQUARTER", "0CALYEAR"]}
MEASURE = "[Measures].[ZCLVISNO]"
# the members that have no facts: not members at all (the first patient registered without a visit)
UNKNOWN = ["[ZCLPAT].[002001]"]
# the members with facts next to them: found
KNOWN = ["[ZCLPAT].[002000]"]
# the levels whose LEVEL_CARDINALITY is checked
CARDINALITIES = {"[ZCLPAT].[ZCLPAT]": "[ZCLPAT].[ZCLPAT].Members", "[ZCLDOC].[ZCLDOC]": "[ZCLDOC].[ZCLDOC].Members",
                 "[ZCLDIAG].[ZCLDIAG]": "[ZCLDIAG].[ZCLDIAG].Members"}


def sets(catalog):
    """The sets whose members must be those with facts."""
    return ([f"[{d}].[{d}].Members" for d in DIMENSIONS + OWN[catalog]]
            + ["[ZCLPAT].[All Patient].Children", "[ZCLDOC].[All Physician].Children"])


def post(url, body, action):
    request = urllib.request.Request(url, data=body.encode("utf-8"), headers={
        "Content-Type": "text/xml; charset=utf-8", "SOAPAction": f'"urn:schemas-microsoft-com:xml-analysis:{action}"'})
    try:
        with urllib.request.urlopen(request, timeout=600) as response:
            return response.read().decode("utf-8")
    except urllib.error.HTTPError as error:
        return error.read().decode("utf-8", "replace")


def fault(text):
    found = re.search(r"<faultstring>(.*?)</faultstring>", text, re.S)
    return html.unescape(found.group(1)) if found else None


class Execute:
    def __init__(self, url, catalog, statement):
        self.statement = statement
        self.text = post(url, EXECUTE.format(statement=html.escape(statement, quote=False), catalog=catalog), "Execute")
        self.fault = fault(self.text)

    def axis(self, name):
        found = re.search(rf'<Axis name="{name}">(.*?)</Axis>', self.text, re.S)
        if not found:
            return []
        return [",".join(html.unescape(u) for u in re.findall(r"<UName>([^<]*)</UName>", t))
                for t in re.findall(r"<Tuple>(.*?)</Tuple>", found.group(1), re.S)]

    def values(self):
        return [html.unescape(v) for v in re.findall(r"<Value[^>]*>([^<]*)</Value>", self.text)]


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--url", default="http://localhost:50000/zzxxmla1?sap-client=001")
    args = parser.parse_args()
    failures = []

    def check(name, condition, detail=""):
        print(f"{'ok  ' if condition else 'FAIL'} {name}{'' if condition else ': ' + str(detail)[:400]}")
        if not condition:
            failures.append(name)

    for catalog in ("ZCLVISIT", "ZCLVISITA"):
        def run(statement):
            return Execute(args.url, catalog, statement)

        counts = {}
        for set_expression in sets(catalog):
            members = run(f"SELECT {MEASURE} ON 0, {set_expression} ON 1 FROM {catalog}")
            with_facts = run(f"SELECT {MEASURE} ON 0, NON EMPTY {set_expression} ON 1 FROM {catalog}")
            if members.fault or with_facts.fault:
                check(f"{catalog} {set_expression}", False, members.fault or with_facts.fault)
                continue
            rows = members.axis("Axis1")
            counts[set_expression] = len(rows)
            check(f"{catalog} {set_expression}: {len(rows)} members, those with facts", rows == with_facts.axis("Axis1"),
                  sorted(set(rows) ^ set(with_facts.axis("Axis1")))[:10])

        for member in UNKNOWN:
            answer = run(f"SELECT {member} ON 0 FROM {catalog}")
            check(f"{catalog} {member} is no member", answer.fault is not None and "not found" in answer.fault,
                  answer.fault or answer.axis("Axis0"))

        for member in KNOWN:
            answer = run(f"SELECT {member} ON 0 FROM {catalog}")
            check(f"{catalog} {member} is a member", answer.axis("Axis0") == [member], answer.fault)

        patients = "[ZCLPAT].[ZCLPAT].Members"
        answer = run(
            f"WITH MEMBER [Measures].[Members] AS Count({patients})\n"
            f" MEMBER [Measures].[Range] AS Count({{{patients}.Item(0) : "
            f"{patients}.Item(Count({patients}) - 1)}})\n"
            f" MEMBER [Measures].[Lead] AS {patients}.Item(0).Lead(Count({patients}) - 1).UniqueName\n"
            f" MEMBER [Measures].[Last] AS {patients}.Item(Count({patients}) - 1).UniqueName\n"
            f"SELECT {{[Measures].[Members], [Measures].[Range], [Measures].[Lead], [Measures].[Last]}} ON 0 "
            f"FROM {catalog}")
        values = answer.values()
        expected = str(counts.get(patients))
        check(f"{catalog} Count, range and Lead along the patients", answer.fault is None and len(values) == 4
              and values[0] == expected and values[1] == expected and values[2] == values[3],
              answer.fault or values)

        # native TopCount: the members' crossjoin is read with the restriction too, members without facts would be
        # empty values at the end
        answer = run(f"SELECT {MEASURE} ON 0, TopCount({patients}, 100000, {MEASURE}) ON 1 FROM {catalog}")
        check(f"{catalog} native TopCount over the patients", answer.fault is None
              and len(answer.axis("Axis1")) == counts.get(patients) and "" not in answer.values(),
              answer.fault or len(answer.axis("Axis1")))

        # a property of the same name on levels of two hierarchies of one axis (every characteristic's Text, as Excel
        # asks for it when two fields are nested): each hierarchy lists it once and each member has its own
        answer = run(f"SELECT {{[ZCLDIAG].[A09]}} * Head([ZCLPAT].[ZCLPAT].Members, 2) DIMENSION PROPERTIES "
                     f"[ZCLPAT].[ZCLPAT].[Text], [ZCLDIAG].[ZCLDIAG].[Text] ON 0 FROM {catalog}")
        infos = dict(re.findall(r'<HierarchyInfo name="([^"]*)">(.*?)</HierarchyInfo>', answer.text, re.S))
        members = re.findall(r'<Member Hierarchy="([^"]*)">(.*?)</Member>', answer.text, re.S)
        check(f"{catalog} Text of two hierarchies on one axis", answer.fault is None and len(members) == 4
              and all(infos.get(h, "").count(f'name="{h}.[Text]"') == 1 for h in ("[ZCLDIAG]", "[ZCLPAT]"))
              and all(m.count("<Text ") == 1 for _, m in members), answer.fault or infos or members)

        text = post(args.url, DISCOVER.format(request_type="MDSCHEMA_LEVELS", catalog=catalog), "Discover")
        cardinality = {html.unescape(u): int(c) for u, c in re.findall(
            r"<LEVEL_UNIQUE_NAME>([^<]*)</LEVEL_UNIQUE_NAME>.*?<LEVEL_CARDINALITY>(\d+)</LEVEL_CARDINALITY>", text, re.S)}
        for level, set_expression in CARDINALITIES.items():
            check(f"{catalog} LEVEL_CARDINALITY of {level}", cardinality.get(level) == counts.get(set_expression),
                  f"{cardinality.get(level)} != {counts.get(set_expression)}")

    print(f"\n{len(failures)} failure(s)")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
