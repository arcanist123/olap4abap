#!/usr/bin/env python3
"""Checks the trace of the XMLA endpoint on SAP (ZZXXMLA1_CL_TRACE, GET/POST /zzxxmla1/schema/api/trace...) over
HTTP, as the trace page (web/schema/trace.js) calls it: switches the trace on for the endpoint's user, sends a
Discover and an Execute, finds both in the trace with request, MDX and response (gzipped in the table, unzipped by
the API), then switches it off (and on again if it was on); the traced calls stay (trace/clear would delete the
user's other calls too).

    python scripts/trace_test.py
    python scripts/trace_test.py --url http://localhost:50000/zzxxmla1 --client 001 --catalog ZFOODMART
"""
import argparse
from datetime import datetime, timedelta
import json
import sys
import urllib.error
import urllib.parse
import urllib.request

SOAP = ('<SOAP-ENV:Envelope xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/"><SOAP-ENV:Body>'
        '{}</SOAP-ENV:Body></SOAP-ENV:Envelope>')
DISCOVER = SOAP.format('<Discover xmlns="urn:schemas-microsoft-com:xml-analysis"><RequestType>DBSCHEMA_CATALOGS'
                       '</RequestType><Restrictions><RestrictionList/></Restrictions><Properties><PropertyList/>'
                       '</Properties></Discover>')
MDX = 'SELECT {[Measures].[Unit Sales]} ON COLUMNS\nFROM [ZFMSALES] -- traced & "zipped" <test>'
EXECUTE = SOAP.format('<Execute xmlns="urn:schemas-microsoft-com:xml-analysis"><Command><Statement>{}</Statement>'
                      '</Command><Properties><PropertyList><Catalog>{}</Catalog><Format>Multidimensional</Format>'
                      '</PropertyList></Properties></Execute>')


def http(method, url, body=None, content_type="text/xml; charset=utf-8"):
    request = urllib.request.Request(url, method=method, data=body.encode("utf-8") if body is not None else None,
                                     headers={"Content-Type": content_type, "User-Agent": "olap4abap trace_test"})
    try:
        with urllib.request.urlopen(request) as response:
            return response.status, response.read().decode("utf-8"), {k.lower(): v for k, v in response.headers.items()}
    except urllib.error.HTTPError as error:
        return error.code, error.read().decode("utf-8"), {k.lower(): v for k, v in error.headers.items()}


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--url", default="http://localhost:50000/zzxxmla1")
    parser.add_argument("--client", default="001")
    parser.add_argument("--catalog", default="ZFOODMART")
    args = parser.parse_args()
    failures = []

    def check(name, condition, detail=""):
        print(f"{'ok  ' if condition else 'FAIL'} {name}{'' if condition else ': ' + str(detail)[:300]}")
        if not condition:
            failures.append(name)

    def api(http_method, resource, **params):
        query = urllib.parse.urlencode({"sap-client": args.client, **params})
        status, text, headers = http(http_method, f"{args.url}/schema/api/{resource}?{query}")
        return status, (json.loads(text) if "json" in headers.get("content-type", "") else text)

    xmla = f"{args.url}?sap-client={args.client}"
    status, state = api("GET", "trace")
    check("GET trace", status == 200 and "user" in state and isinstance(state.get("calls"), list), state)
    user = state["user"]
    was_on = any(u["user"] == user for u in state["users"])

    status, state = api("POST", "trace/on", user=user.lower())
    check("trace/on: the user in upper case", status == 200 and any(u["user"] == user for u in state["users"]), state)
    on = next((u for u in state["users"] if u["user"] == user), {})
    check(f"trace/on: on for {state.get('activeHours')} hours", state.get("activeHours") == 2 and on.get("until")
          and datetime.fromisoformat(on["until"].replace("Z", "+00:00"))
          - datetime.fromisoformat(on["since"].replace("Z", "+00:00")) == timedelta(hours=2), on)
    check("trace/on needs POST", api("GET", "trace/on")[0] == 405)
    check("a user name of more than 12 characters is refused", api("POST", "trace/on", user="A" * 13)[0] == 400)

    known = {c["id"] for c in state["calls"]}
    http("POST", xmla, DISCOVER)
    escaped = MDX.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    status, execute_response, _ = http("POST", xmla, EXECUTE.format(escaped, args.catalog))
    check("Execute answered", status == 200 and "ExecuteResponse" in execute_response, execute_response[:300])

    status, state = api("GET", "trace", filter=user)
    new = [c for c in state["calls"] if c["id"] not in known and c["userAgent"] == "olap4abap trace_test"]
    check("both calls traced, newest first", [c["method"] for c in new] == ["EXECUTE", "DISCOVER"], new)
    if len(new) == 2:
        execute, discover = new
        check("Discover: its rowset", discover["type"] == "DBSCHEMA_CATALOGS" and discover["mdx"] == "", discover)
        check("Execute: the extracted MDX", execute["mdx"] == MDX, execute["mdx"])
        check("Execute: status, size, client", execute["status"] == 200 and not execute["fault"]
              and execute["responseLength"] == len(execute_response) and execute["client"], execute)
        status, entry = api("GET", "trace/entry", id=execute["id"].lower())
        check("trace/entry: the SOAP request as sent", status == 200
              and entry["request"] == EXECUTE.format(escaped, args.catalog), entry.get("request", entry)[:300])
        check("trace/entry: the response unzipped", entry.get("response") == execute_response
              and entry.get("responseTruncated") is False, entry.get("response", "")[:300])
        status, raw = api("GET", "trace/response", id=execute["id"])
        check("trace/response: the response as XML", status == 200 and raw == execute_response, str(raw)[:300])

        for method, call in (("EXECUTE", execute), ("DISCOVER", discover)):
            status, only = api("GET", "trace", filter=user, method=method.lower())
            ids = [c["id"] for c in only["calls"]]
            check(f"method={method}: only these calls", status == 200 and call["id"] in ids
                  and all(c["method"] == method for c in only["calls"]), only.get("calls", only)[:2])
    check("an unknown method is refused", api("GET", "trace", method="select")[0] == 400)
    status, one = api("GET", "trace", filter=user, max="1")
    check("max=1: one call", status == 200 and len(one["calls"]) == 1 and one["max"] == 1, one.get("calls", one))
    check("max out of range is refused", api("GET", "trace", max="0")[0] == 400 and api("GET", "trace", max="10001")[0] == 400
          and api("GET", "trace", max="x")[0] == 400)

    status, state = api("POST", "trace/off", user=user)
    check("trace/off", status == 200 and not any(u["user"] == user for u in state["users"]), state)
    calls = len(state["calls"])
    http("POST", xmla, DISCOVER)
    status, state = api("GET", "trace", filter=user)
    check("nothing traced while off", len(state["calls"]) == calls, state["calls"][:1])
    if was_on:
        api("POST", "trace/on", user=user)
    check("trace/entry of an unknown id", api("GET", "trace/entry", id="0" * 32)[0] == 404)

    print(f"\n{'all passed' if not failures else str(len(failures)) + ' failed: ' + ', '.join(failures)}")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
