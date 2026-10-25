#!/usr/bin/env python3
"""Compares the check of BW's MDX on our endpoint with BW's answers (docs/next-steps.md, Next: BW's MDX on
InfoProviders, step 5): every statement of reference/auth/statements.json, in BW's names, sent for each test user at
each key date to POST /zzxxmla1/bw/checks, BATCH statements per call (ZZXXMLA1_CL_BW_MDX_API: the statement's
members without cells, their selection checked in HANA; the user's profile read once per call) and its status compared with the probe's row of reference/auth/ as auth_check_test.py
compares the check's (the logged-on answer where the file has one, an EMPTY of the switch at the other key dates):
- OK: BW answers OK (EMPTY too for a NON EMPTY query, whose members may have no facts);
- EMPTY, NO AUTH, UNKNOWN: BW gives the same;
- ERROR: never agrees (the endpoint failed: the message says why).

    python scripts/bw_auth_compare.py                                  # every scenario at its key dates
    python scripts/bw_auth_compare.py --scenario H1 --key-date 9999-12-31 --show 50
    python scripts/bw_auth_compare.py --scenario H1 --test MEMBERS     # only the probe's test MEMBERS
    python scripts/bw_auth_compare.py --user ZZXXMLA1_A13 --statement "SELECT ... FROM [$ZCLVISITA]" --sql
"""
import argparse
import glob
import json
import os
import sys

from auth_check_test import SWITCH_REASONS, bw_outcome, describe
from auth_probe import ROOT, Session, read_env, statement_key


def check(api, user, key_date, statement, sql=False):
    params = {"user": user, "keyDate": key_date}
    if sql:
        params["sql"] = "true"
    status, text = api.open("/bw/check", params, statement, {"Content-Type": "text/plain; charset=utf-8"})
    try:
        answer = json.loads(text)
    except ValueError:
        answer = {"error": text[:300]}
    if status != 200:
        return {"status": "ERROR", "reason": "", "message": f"HTTP {status}: {answer.get('error', answer)}"}
    return answer


BATCH = 200


def check_batch(api, user, key_date, statements):
    """The answers of POST bw/checks, one per statement; an ERROR answer for each if the call fails."""
    status, text = api.open("/bw/checks", {"user": user, "keyDate": key_date}, json.dumps(statements),
                            {"Content-Type": "application/json; charset=utf-8"})
    try:
        answer = json.loads(text)
    except ValueError:
        answer = {"error": text[:300]}
    if status != 200 or len(answer.get("results", [])) != len(statements):
        failure = {"status": "ERROR", "reason": "", "message": f"HTTP {status}: {answer.get('error', answer)}"}
        return [failure] * len(statements)
    return answer["results"]


def compare(bw, answer):
    """None if they agree, "switch" if they agree as an EMPTY of the switch, else what differs."""
    outcome, status, test = bw_outcome(bw), answer["status"], bw["test"]
    if status == "OK":
        agrees = outcome == "OK" or (outcome == "EMPTY" and test.endswith(" NE"))
    elif status in ("NO AUTH", "UNKNOWN") and outcome == "EMPTY" and "loggedOn" not in bw \
            and bw["keyDate"] != "9999-12-31" and answer.get("reason") in SWITCH_REASONS:
        return "switch"
    else:
        agrees = outcome == status
    return None if agrees else f"BW {outcome}, check {status}"


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--scenario", action="append", help="a scenario name (FULL, EQ, ...); repeatable")
    parser.add_argument("--key-date", action="append", help="YYYY-MM-DD; repeatable")
    parser.add_argument("--test", action="append", help="a test of the probe (MEMBERS, SLICER, ...); repeatable")
    parser.add_argument("--show", type=int, default=10, help="differences shown per scenario and key date")
    parser.add_argument("--statement", help="check this statement only, for --user at --key-date, and print the answer")
    parser.add_argument("--user", help="with --statement: the user checked")
    parser.add_argument("--sql", action="store_true", help="with --statement: print the SQL statements the check ran")
    parser.add_argument("--dir", default=os.path.join(ROOT, "reference", "auth"))
    args = parser.parse_args()
    env = read_env()
    scheme = "https" if env.get("SAP_USE_SSL", "").lower() in ("true", "1", "yes") else "http"
    api = Session(f"{scheme}://{env['SAP_ASHOST']}:{env['SAP_PORT']}/zzxxmla1", env.get("SAP_CLIENT", "001"),
                  env["SAP_USER"], env["SAP_PASSWORD"])
    try:
        if args.statement:
            answer = check(api, args.user or env["SAP_USER"], (args.key_date or ["9999-12-31"])[0], args.statement,
                           args.sql)
            statements = answer.pop("sql", None)
            print(json.dumps(answer, indent=1))
            for logged in statements or []:
                print(f"-- {logged['phase']}: {logged['rows']} rows, {logged['us']} us {logged['error']}\n{logged['sql']}")
            return 0
        statements = json.load(open(os.path.join(args.dir, "statements.json"), encoding="utf-8"))
        files = sorted(f for f in glob.glob(os.path.join(args.dir, "*.json")) if not f.endswith("statements.json"))
        documents = [json.load(open(f, encoding="utf-8")) for f in files]
        documents = [d for d in documents if not args.scenario or d["scenario"] in args.scenario]
        if args.scenario and len(documents) != len(set(args.scenario)):
            sys.exit(f"unknown scenario among {args.scenario}")
        failed = 0
        for document in documents:
            for key_date in [k for k in document["keyDates"] if not args.key_date or k in args.key_date]:
                counts, differences, asked = {"agree": 0, "switch": 0}, [], []
                for bw in document["results"]:
                    if bw["keyDate"] != key_date or bw["test"] == "HIERARCHIES" \
                            or (args.test and bw["test"] not in args.test):
                        continue
                    statement = statements.get(statement_key(bw))
                    if not statement:
                        differences.append((bw, "no statement in statements.json", None))
                        continue
                    asked.append((bw, statement))
                answers = []
                for start in range(0, len(asked), BATCH):
                    answers += check_batch(api, document["user"], key_date,
                                           [statement for _, statement in asked[start:start + BATCH]])
                for (bw, _), answer in zip(asked, answers):
                    difference = compare(bw, answer)
                    if difference is None:
                        counts["agree"] += 1
                    elif difference == "switch":
                        counts["switch"] += 1
                    else:
                        differences.append((bw, difference, answer))
                print(f"{document['scenario']} {key_date}: {counts['agree']} agree, {counts['switch']} empty through "
                      f"the switch, {len(differences)} differ", flush=True)
                kinds = {}
                for bw, difference, _ in differences:
                    kind = f"{bw['test']}: {difference}"
                    kinds[kind] = kinds.get(kind, 0) + 1
                for kind, count in sorted(kinds.items(), key=lambda item: -item[1]):
                    print(f"    {count:5} {kind}")
                for bw, difference, answer in differences[:args.show]:
                    why = f" ({answer.get('reason')}: {answer.get('message')})" if answer else ""
                    print(f"      {describe(bw)}: {difference}{why}")
                failed += len(differences)
        print("all agree" if not failed else f"{failed} differences")
        return 1 if failed else 0
    finally:
        api.logoff()


if __name__ == "__main__":
    sys.exit(main())
