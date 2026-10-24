#!/usr/bin/env python3
"""Compares olap4abap's authorization check with BW's answers (docs/next-steps.md, Now: analysis authorisations, step
4): per scenario of reference/auth/ and key date, GET auth/check of the schema API (ZZXXMLA1_CL_BW_AUTH_QUERIES: the
probe's queries, each translated into its selection and checked by ZZXXMLA1_CL_BW_AUTH for the scenario's user) and
the probe's rows compared query by query, by the key of what they ask (auth_probe.statement_key).

BW's outcome is the logged-on answer where the file has one (loggedOn: refused, UNKNOWN if the message says unknown),
else the probe's status; ERROR is a refusal (BW's "Execute as Other User" fails where the logged-on user is refused:
every ERROR of 9999-12-31 is refused logged on). The check agrees when
- ALLOWED: BW answers (OK; EMPTY too for a NON EMPTY query, whose members may have no facts);
- EMPTY: BW answers EMPTY;
- NO AUTH, UNKNOWN: BW gives the same; at the other key dates, which have no logon, BW's EMPTY counts as refused where
  the check refuses a hierarchy without a line or a characteristic without values (the switch answers those EMPTY,
  the logon refuses them; counted apart as "empty through the switch").
For a restricted hierarchy the members the check says the query shows are compared with BW's rows: equal, or for a
NON EMPTY query BW's among them. The hierarchies BW lists (HIERARCHIES) are compared as sets.

    python scripts/auth_check_test.py                       # every scenario at its key dates
    python scripts/auth_check_test.py --scenario H1 --key-date 9999-12-31 --show 50
"""
import argparse
import glob
import json
import os
import sys

from auth_probe import PAIRS, ROOT, Session, read_env, statement_key

REFUSED = ("NO AUTH", "UNKNOWN")
SWITCH_REASONS = ("HIERARCHY", "NO VALUES")


def bw_outcome(row):
    refused = row.get("loggedOn", {}).get("refused")
    if refused is not None:
        return "UNKNOWN" if "unknown" in refused.lower() else "NO AUTH"
    return "NO AUTH" if row["status"] == "ERROR" else row["status"]


def compare(bw, check):
    """None if they agree, "switch" if they agree as an EMPTY of the switch, else what differs."""
    outcome, status, test = bw_outcome(bw), check["status"], bw["test"]
    if test == "HIERARCHIES":
        listed = {h for h in bw.get("answer", "").split("; ") if h}
        mine = {h for h in check["answer"].split("; ") if h}
        return None if listed == mine else f"listed {sorted(listed)}, check {sorted(mine)}"
    if status == "ALLOWED":
        agrees = outcome == "OK" or (outcome == "EMPTY" and test.endswith(" NE"))
    elif status in REFUSED and outcome == "EMPTY" and "loggedOn" not in bw and bw["keyDate"] != "9999-12-31" \
            and check["reason"] in SWITCH_REASONS:
        return "switch"
    else:
        agrees = outcome == status
    if not agrees:
        return f"BW {outcome}, check {status}"
    if status == "ALLOWED" and check["members"] is not None and outcome == "OK":
        shown = [cell[0] for cell in bw.get("cells", [])]
        if test.endswith(" NE"):
            extra = sorted(set(shown) - set(check["members"]))
            if extra:
                return f"BW shows {extra} the check does not"
        elif sorted(shown) != sorted(check["members"]):
            return f"members: BW {shown}, check {check['members']}"
    return None


def describe(row):
    return " ".join(str(row[name]) for name in ("test", "characteristic", "hierarchy", "node", "filterHierarchy",
                                                "filterNode") if row.get(name))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--scenario", action="append", help="a scenario name (FULL, EQ, ...); repeatable")
    parser.add_argument("--key-date", action="append", help="YYYY-MM-DD; repeatable")
    parser.add_argument("--show", type=int, default=10, help="differences shown per scenario and key date")
    parser.add_argument("--dir", default=os.path.join(ROOT, "reference", "auth"))
    args = parser.parse_args()
    env = read_env()
    scheme = "https" if env.get("SAP_USE_SSL", "").lower() in ("true", "1", "yes") else "http"
    api = Session(f"{scheme}://{env['SAP_ASHOST']}:{env['SAP_PORT']}/zzxxmla1", env.get("SAP_CLIENT", "001"),
                  env["SAP_USER"], env["SAP_PASSWORD"])

    files = sorted(f for f in glob.glob(os.path.join(args.dir, "*.json")) if not f.endswith("statements.json"))
    documents = [json.load(open(f, encoding="utf-8")) for f in files]
    documents = [d for d in documents if not args.scenario or d["scenario"] in args.scenario]
    if args.scenario and len(documents) != len(set(args.scenario)):
        sys.exit(f"unknown scenario among {args.scenario}")

    failed = 0
    try:
        for document in documents:
            for key_date in [k for k in document["keyDates"] if not args.key_date or k in args.key_date]:
                status, body = api.get_json("/schema/api/auth/check",
                                            {"user": document["user"], "keyDate": key_date, "pairs": ",".join(PAIRS)})
                if status != 200:
                    sys.exit(f"{document['scenario']} {key_date}: {status} {body.get('error', body)}")
                checked = {}
                for row in body["results"]:
                    checked.setdefault(statement_key({**row, "keyDate": key_date}), []).append(row)
                counts, differences, unasked = {"agree": 0, "switch": 0}, [], 0
                for bw in (r for r in document["results"] if r["keyDate"] == key_date):
                    candidates = checked.get(statement_key(bw))
                    if not candidates:
                        unasked += 1
                        differences.append((bw, "the check does not ask it", None))
                        continue
                    mine = candidates.pop(0)
                    difference = compare(bw, mine)
                    if difference is None:
                        counts["agree"] += 1
                    elif difference == "switch":
                        counts["switch"] += 1
                    else:
                        differences.append((bw, difference, mine))
                extra = sum(len(rows) for rows in checked.values())
                print(f"{document['scenario']} {key_date}: {counts['agree']} agree, {counts['switch']} empty through "
                      f"the switch, {len(differences) - unasked} differ, {unasked} not asked by the check, {extra} "
                      f"asked only by the check (authorizations {body['authorizations']})", flush=True)
                kinds = {}
                for bw, difference, _ in differences:
                    kind = f"{bw['test']}: {difference.split(',')[0] if difference.startswith('BW') else difference[:40]}"
                    kinds[kind] = kinds.get(kind, 0) + 1
                for kind, count in sorted(kinds.items(), key=lambda item: -item[1]):
                    print(f"    {count:5} {kind}")
                for bw, difference, mine in differences[:args.show]:
                    why = f" ({mine['reason']}: {mine['message']})" if mine and mine["reason"] else ""
                    print(f"      {describe(bw)}: {difference}{why}")
                failed += len(differences) + extra
    finally:
        api.logoff()
    print("all agree" if not failed else f"{failed} differences")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
