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
- NO AUTH, UNKNOWN: BW gives the same; where the file has no logon (the other key dates; 9999-12-31 of a scenario
  recorded without --verify), BW's EMPTY counts as refused where the check refuses a hierarchy without a line or a
  characteristic without values (the switch answers those EMPTY, the logon refuses them, as --verify established on
  the first 21 scenarios; counted apart as "empty through the switch");
- ALLOWED where BW refuses at reading the cells or the axis (EYE 007) on a hierarchy the user has a level-limited
  line on (type 0 or 2): BW checks a set of leaves, or an expansion that ends on leaves, as the node with its whole
  subtree, which such a line does not cover (docs/known-issues.md, BW's unexpected answers); counted apart as
  "widened by BW";
- out of scope: the check refuses the user for a hierarchy line of validity 2 or 3 (reason VALIDITY, docs/mvp-scope.md,
  Authorisation decision), whatever BW answers, and lists no hierarchy then; counted apart as "out of scope";
- HIERARCHIES where the check refuses the user every selection (reason PROVIDER) and lists nothing, while BW lists
  hierarchies to the user it refuses every query (ACTVT, docs/known-issues.md, BW's unexpected answers); counted apart as
  "listed by BW to a refused user".
For a restricted hierarchy the members the check says the query shows are compared with BW's rows: equal, or for a
NON EMPTY query BW's among them. The hierarchies BW lists (HIERARCHIES) are compared as sets.

    python scripts/auth_check_test.py                       # every scenario at its key dates
    python scripts/auth_check_test.py --engine sql          # the check in HANA (ZZXXMLA1_CL_BW_AUTH_SQL)
    python scripts/auth_check_test.py --engine api          # the ABAP API (ZZXXMLA1_IF_BW_AUTH_CHECK)

With --engine api only the queries whose selection is a product of members are answered (the API takes no other
question); the check answers the others SKIPPED, counted apart.
    python scripts/auth_check_test.py --scenario H1 --key-date 9999-12-31 --show 50
"""
import argparse
import glob
import json
import os
import re
import sys

from auth_probe import PAIRS, ROOT, Session, read_env, statement_key

REFUSED = ("NO AUTH", "UNKNOWN")
SWITCH_REASONS = ("HIERARCHY", "NO VALUES")
# the check's refusal of a user outside olap4abap's scope: a hierarchy line of validity 2 or 3
OUT_OF_SCOPE = "VALIDITY"
# the check's refusal of a user without an authorisation for the provider
NO_PROVIDER = "PROVIDER"
# BW's refusal at reading the cells or the axis (the probe's prefix), as opposed to the node check's refusal
WIDENED_MESSAGE = re.compile(r"^(cells|axis): EYE 007")
LIMITED_LINE = re.compile(r"^(\S+) (\S+) version (\S*) .* type ([0-4]) ")


def without_logon(row):
    """Whether BW's answer of the row is the switch's alone: no logged-on answer, at a key date that has none (the other
    key dates) or in a file recorded without --verify (_verified, set when the file is read)."""
    return "loggedOn" not in row and (row["keyDate"] != "9999-12-31" or not row.get("_verified"))


def read_documents(files):
    """The scenario files, each row marked with whether its file was verified by a logon."""
    documents = [json.load(open(f, encoding="utf-8")) for f in files]
    for document in documents:
        limited = set()
        for line in document.get("authorizations", []):
            match = LIMITED_LINE.match(line.get("details", ""))
            if line.get("assigned") and line.get("kind") == "HIERARCHY" and match and match.group(4) in "02":
                limited.add(f"{match.group(2)} {match.group(3)}".strip())
        for row in document["results"]:
            row["_verified"] = bool(document.get("verified"))
            row["_limited"] = limited
    return documents


def widened(row):
    """Whether BW's refusal of the row is its check of a set of leaves or an expansion to leaves as the node with its
    whole subtree, on a hierarchy the user has a level-limited line on (docs/known-issues.md)."""
    return bool(WIDENED_MESSAGE.match(row.get("message", ""))) and bool(
        {row.get("hierarchy"), row.get("filterHierarchy")} & row.get("_limited", set()))


def bw_outcome(row):
    refused = row.get("loggedOn", {}).get("refused")
    if refused is not None:
        return "UNKNOWN" if "unknown" in refused.lower() else "NO AUTH"
    return "NO AUTH" if row["status"] == "ERROR" else row["status"]


def compare(bw, check, out_of_scope=False, refused_user=False):
    """None if they agree, "switch" if they agree as an EMPTY of the switch, "widened" if BW refuses by widening a set
    of leaves, "scope" if the check refuses the user as out of scope (out_of_scope: it does so for the scenario),
    "listed" if BW lists hierarchies to a user the check refuses every selection (refused_user), else what differs."""
    outcome, status, test = bw_outcome(bw), check["status"], bw["test"]
    if check.get("reason") == OUT_OF_SCOPE or (out_of_scope and test == "HIERARCHIES"):
        return "scope"
    if test == "HIERARCHIES":
        listed = {h for h in bw.get("answer", "").split("; ") if h}
        mine = {h for h in check["answer"].split("; ") if h}
        if listed == mine:
            return None
        return "listed" if refused_user and not mine else f"listed {sorted(listed)}, check {sorted(mine)}"
    if status == "ALLOWED" and outcome == "NO AUTH" and widened(bw):
        return "widened"
    if status == "ALLOWED":
        agrees = outcome == "OK" or (outcome == "EMPTY" and test.endswith(" NE"))
    elif status in REFUSED and outcome == "EMPTY" and without_logon(bw) and check["reason"] in SWITCH_REASONS:
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
    parser.add_argument("--engine", choices=("abap", "sql", "api"), default="abap",
                        help="the check in ABAP (ZZXXMLA1_CL_BW_AUTH), in HANA (ZZXXMLA1_CL_BW_AUTH_SQL) or the ABAP "
                             "API (ZZXXMLA1_IF_BW_AUTH_CHECK)")
    parser.add_argument("--show", type=int, default=10, help="differences shown per scenario and key date")
    parser.add_argument("--dir", default=os.path.join(ROOT, "reference", "auth"))
    args = parser.parse_args()
    env = read_env()
    scheme = "https" if env.get("SAP_USE_SSL", "").lower() in ("true", "1", "yes") else "http"
    api = Session(f"{scheme}://{env['SAP_ASHOST']}:{env['SAP_PORT']}/zzxxmla1", env.get("SAP_CLIENT", "001"),
                  env["SAP_USER"], env["SAP_PASSWORD"])

    files = sorted(f for f in glob.glob(os.path.join(args.dir, "*.json")) if not f.endswith("statements.json"))
    documents = read_documents(files)
    documents = [d for d in documents if not args.scenario or d["scenario"] in args.scenario]
    if args.scenario and len(documents) != len(set(args.scenario)):
        sys.exit(f"unknown scenario among {args.scenario}")

    failed = 0
    try:
        for document in documents:
            for key_date in [k for k in document["keyDates"] if not args.key_date or k in args.key_date]:
                status, body = api.get_json("/schema/api/auth/check",
                                            {"user": document["user"], "keyDate": key_date, "pairs": ",".join(PAIRS),
                                             "engine": args.engine})
                if status != 200:
                    sys.exit(f"{document['scenario']} {key_date}: {status} {body.get('error', body)}")
                checked = {}
                for row in body["results"]:
                    checked.setdefault(statement_key({**row, "keyDate": key_date}), []).append(row)
                counts, differences, unasked = {"agree": 0, "switch": 0, "widened": 0, "skipped": 0, "scope": 0,
                                                "listed": 0}, [], 0
                out_of_scope = any(row.get("reason") == OUT_OF_SCOPE for row in body["results"])
                refused_user = any(row.get("test") == "TOTAL" and row.get("reason") == NO_PROVIDER
                                   for row in body["results"])
                for bw in (r for r in document["results"] if r["keyDate"] == key_date):
                    candidates = checked.get(statement_key(bw))
                    if not candidates:
                        unasked += 1
                        differences.append((bw, "the check does not ask it", None))
                        continue
                    mine = candidates.pop(0)
                    if mine["status"] == "SKIPPED":
                        counts["skipped"] += 1
                        continue
                    difference = compare(bw, mine, out_of_scope, refused_user)
                    if difference is None:
                        counts["agree"] += 1
                    elif difference in ("switch", "widened", "scope", "listed"):
                        counts[difference] += 1
                    else:
                        differences.append((bw, difference, mine))
                extra = sum(len(rows) for rows in checked.values())
                print(f"{document['scenario']} {key_date}: {counts['agree']} agree, {counts['switch']} empty through "
                      f"the switch, {len(differences) - unasked} differ, {unasked} not asked by the check, {extra} "
                      f"asked only by the check, {counts['widened']} widened by BW, {counts['scope']} out of scope, "
                      f"{counts['listed']} listed by BW to a refused user, "
                      f"{counts['skipped']} skipped (not a product) "
                      f"(authorizations {body['authorizations']})", flush=True)
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
